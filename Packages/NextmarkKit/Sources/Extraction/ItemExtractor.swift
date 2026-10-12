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

    public init(fetcher: any PageFetcher = URLSessionPageFetcher(), imageAnalyzer: (any ImageAnalyzing)? = ItemExtractor.defaultImageAnalyzer) {
        self.fetcher = fetcher
        self.imageAnalyzer = imageAnalyzer
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
        } catch let error as URLError where Self.isTransient(error) {
            throw ExtractionError.temporarilyUnavailable(error.localizedDescription)
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
            let analysis = try? await analyzer.analyze(imageData: resource.data)
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
             .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .callIsActive:
            true
        default:
            false
        }
    }

    // MARK: Files

    private func extractFile(_ file: LocalFile) async throws -> Extraction {
        let type = UTType(file.contentType)
        if type?.conforms(to: .pdf) == true {
            return Extraction(contentText: Self.pdfText(url: file.url))
        }
        if type?.conforms(to: .image) == true {
            guard let analyzer = imageAnalyzer, let analysis = try? await analyzer.analyze(imageAt: file.url) else {
                return Extraction()
            }
            return Extraction(ocrText: analysis.text, imageLabels: analysis.labels, barcodes: analysis.barcodes)
        }
        if type?.conforms(to: .plainText) == true || type?.conforms(to: .sourceCode) == true,
           let data = try? Data(contentsOf: file.url),
           let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Extraction(contentText: trimmed.isEmpty ? nil : HTMLText.truncate(trimmed, to: Self.maxPlainTextCharacters))
        }
        return Extraction()
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
