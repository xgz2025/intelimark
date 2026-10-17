//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import Foundation
import UniformTypeIdentifiers
import Model

/// A file belonging to the item (its original attachment).
public struct LocalFile: Sendable, Equatable {
    public var url: URL
    public var contentType: String

    public init(url: URL, contentType: String) {
        self.url = url
        self.contentType = contentType
    }
}

public struct ExtractionInput: Sendable, Equatable {
    public var kind: ItemKind
    public var url: URL?
    public var pageContext: PageContext?
    public var files: [LocalFile]
    /// The text shared with the item: a shopping app's "Wool Coat – $89.99 https://…".
    public var text: String?
    /// When it was saved: a boarding pass barcode's day is placed in the year around it.
    public var capturedAt: Date?

    public init(
        kind: ItemKind, url: URL? = nil, pageContext: PageContext? = nil, files: [LocalFile] = [],
        text: String? = nil, capturedAt: Date? = nil
    ) {
        self.kind = kind
        self.url = url
        self.pageContext = pageContext
        self.files = files
        self.text = text
        self.capturedAt = capturedAt
    }
}

public enum ExtractionError: Error, Equatable {
    /// Worth retrying later: offline, timed out, server busy.
    case temporarilyUnavailable(String)
}

/// The Extract stage (PRD U1, Docs/architecture.md §5.2): facts from the item's
/// source — link metadata, readable text, schema.org data, PDF text, OCR — with
/// no model involved. Throws only for failures worth retrying; anything else
/// returns whatever could be extracted, so enrichment never stalls.
public struct ItemExtractor: Sendable {
    static let maxPlainTextCharacters = 20_000

    private let fetcher: any PageFetcher
    private let imageAnalyzer: (any ImageAnalyzing)?
    private let placeNamer: (any PlaceNaming)?

    public init(
        fetcher: any PageFetcher = URLSessionPageFetcher(),
        imageAnalyzer: (any ImageAnalyzing)? = ItemExtractor.defaultImageAnalyzer,
        placeNamer: (any PlaceNaming)? = ItemExtractor.defaultPlaceNamer
    ) {
        self.fetcher = fetcher
        self.imageAnalyzer = imageAnalyzer
        self.placeNamer = placeNamer
    }

    public static var defaultPlaceNamer: (any PlaceNaming)? {
        #if canImport(MapKit)
        return MapKitPlaceNamer()
        #else
        return nil
        #endif
    }

    public static var defaultImageAnalyzer: (any ImageAnalyzing)? {
        #if canImport(Vision)
        return VisionImageAnalyzer()
        #else
        return nil
        #endif
    }

    public func extract(_ input: ExtractionInput) async throws -> Extraction {
        switch input.kind {
        case .link:
            return Self.addingSharedPrice(try await extractLink(input), input: input)
        case .image, .pdf, .file:
            guard let file = input.files.first else { return Extraction() }
            return try await extractFile(file, reference: input.capturedAt ?? Date())
        case .text, .note, .email, .aiSession:
            return Extraction()
        }
    }

    // MARK: Links

    private func extractLink(_ input: ExtractionInput) async throws -> Extraction {
        // Safari already captured the page as the user saw it — including pages behind
        // a login, which a fresh fetch can't see. Use that and stay off the network.
        if let page = input.pageContext, page.excerpt != nil || !page.jsonLD.isEmpty {
            let tags = page.meta ?? [:]
            let tagged = ProductPage.product(
                tags: tags, title: nil, description: tags["og:description"], imageURL: tags["og:image"], siteName: tags["og:site_name"]
            )
            return Extraction(
                siteName: tags["og:site_name"],
                language: page.language,
                canonicalURL: page.canonicalURL,
                heroImageURL: tags["og:image"].flatMap { URL(string: $0) },
                contentText: page.excerpt,
                structured: ProductPage.complete(SchemaOrg.structuredData(fromJSONLD: page.jsonLD), with: tagged)
            )
        }
        guard let url = input.url, url.scheme == "http" || url.scheme == "https" else { return Extraction() }

        let resource: FetchedResource
        do {
            resource = try await fetcher.fetch(url)
        } catch let error as URLError where error.code == .cancelled || Task.isCancelled {
            // Stopped, not failed: the job runs again later.
            throw CancellationError()
        } catch let error as URLError where Self.isTransient(error) {
            throw ExtractionError.temporarilyUnavailable(error.localizedDescription)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return Extraction()
        }
        if resource.statusCode == 429 || (500..<600).contains(resource.statusCode) {
            throw ExtractionError.temporarilyUnavailable("HTTP \(resource.statusCode)")
        }
        guard (200..<300).contains(resource.statusCode) else { return Extraction() }

        let mimeType = resource.mimeType ?? "text/html"
        if mimeType == "application/pdf" {
            return Extraction(contentText: Self.pdfText(data: resource.data))
        }
        if mimeType.hasPrefix("image/"), let analyzer = imageAnalyzer {
            let data = resource.data
            let analysis = try await Self.analyzeWithinLimit { try await analyzer.analyze(imageData: data) }
            return Extraction(ocrText: analysis?.text, imageLabels: analysis?.labels ?? [], barcodes: analysis?.barcodes ?? [])
        }
        guard mimeType.contains("html") || mimeType.hasPrefix("text/"), let html = resource.text else {
            return Extraction()
        }
        return Self.extraction(fromHTML: html, baseURL: resource.finalURL)
    }

    public static func extraction(fromHTML html: String, baseURL: URL) -> Extraction {
        let metadata = HTMLParser.metadata(from: html, baseURL: baseURL)
        var tags = metadata.productTags
        // No tag states it: the price the shop keeps in the page's scripts.
        if ProductPage.isShop(baseURL), let embedded = ProductPage.embeddedPrice(inHTML: html, host: baseURL.host()) {
            tags["laterwise:price"] = String(embedded.price)
            tags["laterwise:pricesource"] = "selector"
            if let currency = embedded.currency { tags["laterwise:currency"] = currency }
        }
        let tagged = ProductPage.product(
            tags: tags, title: metadata.title, description: metadata.description,
            imageURL: metadata.imageURL?.absoluteString, siteName: metadata.siteName
        )
        return Extraction(
            title: metadata.title,
            siteName: metadata.siteName,
            language: metadata.language,
            canonicalURL: metadata.canonicalURL,
            heroImageURL: metadata.imageURL,
            contentText: ReadableText.extract(fromHTML: html) ?? metadata.description,
            structured: ProductPage.complete(SchemaOrg.structuredData(fromJSONLD: metadata.jsonLD), with: tagged)
        )
    }

    /// A shop's link whose page gave no price (it needs scripts, or a sign-in): the
    /// price in the text the shopping app shared with it.
    static func addingSharedPrice(_ extraction: Extraction, input: ExtractionInput) -> Extraction {
        guard extraction.typedFields?.product?.price == nil, let text = input.text,
              let shared = ProductPage.product(sharedText: text, url: input.url, siteName: extraction.siteName)
        else { return extraction }
        var result = extraction
        if var product = result.structured?.fields.product, result.structured?.kind == .product {
            product.price = shared.price
            product.currency = product.currency ?? shared.currency
            result.structured?.fields.product = product
        } else if result.structured == nil {
            var product = shared
            product.imageURL = extraction.heroImageURL?.absoluteString
            product.name = extraction.title ?? product.name
            result.structured = StructuredData(kind: .product, fields: TypedFields(product: product))
        }
        return result
    }

    static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .callIsActive,
             // Also what a network that isn't really online yet (a hotel Wi-Fi login) gives.
             .cannotFindHost, .secureConnectionFailed, .cannotLoadFromNetwork,
             .serverCertificateUntrusted, .serverCertificateHasUnknownRoot:
            true
        default:
            false
        }
    }

    // MARK: Files

    private func extractFile(_ file: LocalFile, reference: Date) async throws -> Extraction {
        let type = UTType(file.contentType)
        let name = file.url.lastPathComponent.lowercased()
        // Wallet passes and calendar files state exactly what, where and when.
        if type?.identifier == "com.apple.pkpass" || name.hasSuffix(".pkpass") {
            return Extraction(structured: WalletPass.read(from: file.url))
        }
        if type?.conforms(to: .calendarEvent) == true || name.hasSuffix(".ics") {
            return Extraction(structured: CalendarFile.read(from: file.url))
        }
        if type?.conforms(to: .pdf) == true {
            let text = Self.pdfText(url: file.url)
            // An e-ticket or itinerary PDF is a trip; any other PDF a document.
            let trip = text.flatMap { TravelText.parse($0, reference: reference) }
            return Extraction(
                contentText: text,
                structured: trip.map { StructuredData(kind: .travel, fields: TypedFields(trip: $0)) },
                fileFields: Self.pdfFields(url: file.url).map { TypedFields(article: $0) }
            )
        }
        if DocumentText.canRead(type, fileName: name) {
            let document = DocumentText.read(file.url, type: type, limit: Self.maxPlainTextCharacters)
            return Extraction(contentText: document.text, fileFields: document.fields.map { TypedFields(article: $0) })
        }
        if type?.conforms(to: .image) == true {
            let url = file.url
            let photo = await photoFields(at: url)
            guard let analyzer = imageAnalyzer,
                  let analysis = try await Self.analyzeWithinLimit({ try await analyzer.analyze(imageAt: url) })
            else {
                return Extraction(fileFields: photo.map { TypedFields(photo: $0) })
            }
            return Extraction(
                ocrText: analysis.text, imageLabels: analysis.labels, barcodes: analysis.barcodes,
                structured: Self.structured(fromPicture: analysis, reference: photo?.takenAt ?? reference),
                fileFields: photo.map { TypedFields(photo: $0) }
            )
        }
        if type?.conforms(to: .plainText) == true || type?.conforms(to: .sourceCode) == true,
           let text = Self.textPrefix(of: file.url) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Extraction(contentText: trimmed.isEmpty ? nil : HTMLText.truncate(trimmed, to: Self.maxPlainTextCharacters))
        }
        return Extraction()
    }

    /// What a picture is, by what's in it: a boarding pass by its barcode, a ticket or
    /// itinerary by its text, a receipt by its merchant and total.
    static func structured(fromPicture analysis: ImageAnalysis, reference: Date) -> StructuredData? {
        if let trip = analysis.barcodes.lazy.compactMap({ BoardingPassBarcode.parse($0, near: reference) }).first {
            var trip = trip
            // The barcode has the day; the printed pass often has the time.
            if let text = analysis.text, let printed = TravelText.parse(text, reference: reference),
               let time = printed.legs.first, time.departureHasTime, let departure = time.departure,
               let barcodeDay = trip.legs.first?.departure,
               Calendar.current.isDate(departure, inSameDayAs: barcodeDay) {
                trip.legs[0].departure = departure
                trip.legs[0].departureHasTime = true
                trip.legs[0].gate = trip.legs[0].gate ?? time.gate
                trip.legs[0].terminal = trip.legs[0].terminal ?? time.terminal
            }
            return StructuredData(kind: .travel, fields: TypedFields(trip: trip))
        }
        guard let text = analysis.text else { return nil }
        if let trip = TravelText.parse(text, reference: reference) {
            return StructuredData(kind: .travel, fields: TypedFields(trip: trip))
        }
        // A photo or screenshot of a receipt says what it is: merchant and total.
        return ReceiptParser.parse(text).map { StructuredData(kind: .receipt, fields: TypedFields(receipt: $0)) }
    }

    /// The start of a text file: only what's kept is read, so a multi-gigabyte log
    /// can't exhaust memory.
    static func textPrefix(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // UTF-8 takes at most four bytes a character.
        guard var data = try? handle.read(upToCount: maxPlainTextCharacters * 4) else { return nil }
        URLSessionPageFetcher.dropIncompleteUTF8Tail(&data)
        return String(data: data, encoding: .utf8)
    }

    /// Reading text in an image normally takes a second or two.
    static let analysisTimeLimit: TimeInterval = 60

    /// Image analysis with a time limit. Too slow or cancelled: the job is tried again
    /// later. Failed: nil, and the item goes on without the image's text.
    static func analyzeWithinLimit(
        _ analyze: @escaping @Sendable () async throws -> ImageAnalysis
    ) async throws -> ImageAnalysis? {
        do {
            return try await withTimeLimit(analysisTimeLimit, operation: analyze)
        } catch is TimeLimitExceeded {
            throw ExtractionError.temporarilyUnavailable("Image analysis took too long")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
    }

    /// A photo's time and place, with the place named when it can be.
    func photoFields(at url: URL) async -> PhotoFields? {
        guard var photo = PhotoMetadata.read(from: url) else { return nil }
        if let latitude = photo.latitude, let longitude = photo.longitude, let placeNamer {
            photo.placeName = await placeNamer.name(latitude: latitude, longitude: longitude)
        }
        return photo
    }

    static func pdfFields(url: URL) -> ArticleFields? {
        #if canImport(PDFKit)
        return PDFMetadata.read(from: url)
        #else
        return nil
        #endif
    }

    static func pdfText(url: URL) -> String? {
        #if canImport(PDFKit)
        return PDFText.extract(from: url)
        #else
        return nil
        #endif
    }

    static func pdfText(data: Data) -> String? {
        #if canImport(PDFKit)
        return PDFText.extract(from: data)
        #else
        return nil
        #endif
    }
}
