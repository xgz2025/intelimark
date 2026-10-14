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

    public init(kind: ItemKind, url: URL? = nil, pageContext: PageContext? = nil, files: [LocalFile] = []) {
        self.kind = kind
        self.url = url
        self.pageContext = pageContext
        self.files = files
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
            return try await extractLink(input)
        case .image, .pdf, .file:
            guard let file = input.files.first else { return Extraction() }
            return try await extractFile(file)
        case .text, .note, .email, .aiSession:
            return Extraction()
        }
    }

    // MARK: Links

    private func extractLink(_ input: ExtractionInput) async throws -> Extraction {
        // Safari already captured the page as the user saw it — including pages behind
        // a login, which a fresh fetch can't see. Use that and stay off the network.
        if let page = input.pageContext, page.excerpt != nil || !page.jsonLD.isEmpty {
            return Extraction(
                language: page.language,
                canonicalURL: page.canonicalURL,
                contentText: page.excerpt,
                structured: SchemaOrg.structuredData(fromJSONLD: page.jsonLD)
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

    static func extraction(fromHTML html: String, baseURL: URL) -> Extraction {
        let metadata = HTMLParser.metadata(from: html, baseURL: baseURL)
        return Extraction(
            title: metadata.title,
            siteName: metadata.siteName,
            language: metadata.language,
            canonicalURL: metadata.canonicalURL,
            heroImageURL: metadata.imageURL,
            contentText: ReadableText.extract(fromHTML: html) ?? metadata.description,
            structured: SchemaOrg.structuredData(fromJSONLD: metadata.jsonLD)
        )
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

    private func extractFile(_ file: LocalFile) async throws -> Extraction {
        let type = UTType(file.contentType)
        if type?.conforms(to: .pdf) == true {
            return Extraction(
                contentText: Self.pdfText(url: file.url),
                fileFields: Self.pdfFields(url: file.url).map { TypedFields(article: $0) }
            )
        }
        if type?.conforms(to: .image) == true {
            let url = file.url
            let photo = await photoFields(at: url)
            guard let analyzer = imageAnalyzer,
                  let analysis = try await Self.analyzeWithinLimit({ try await analyzer.analyze(imageAt: url) })
            else {
                return Extraction(fileFields: photo.map { TypedFields(photo: $0) })
            }
            // A photo or screenshot of a receipt says what it is: merchant and total.
            let receipt = ReceiptParser.parse(analysis.text)
            return Extraction(
                ocrText: analysis.text, imageLabels: analysis.labels, barcodes: analysis.barcodes,
                structured: receipt.map { StructuredData(kind: .receipt, fields: TypedFields(receipt: $0)) },
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
