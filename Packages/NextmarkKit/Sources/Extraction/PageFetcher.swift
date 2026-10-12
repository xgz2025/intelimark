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

/// A downloaded web resource, capped in size.
public struct FetchedResource: Sendable, Equatable {
    public var data: Data
    public var mimeType: String?
    public var textEncodingName: String?
    public var finalURL: URL
    public var statusCode: Int

    public init(data: Data, mimeType: String?, textEncodingName: String? = nil, finalURL: URL, statusCode: Int = 200) {
        self.data = data
        self.mimeType = mimeType
        self.textEncodingName = textEncodingName
        self.finalURL = finalURL
        self.statusCode = statusCode
    }

    public var text: String? {
        if let name = textEncodingName {
            let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if encoding != kCFStringEncodingInvalidId {
                let nsEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
                if let text = String(data: data, encoding: nsEncoding) { return text }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

public protocol PageFetcher: Sendable {
    func fetch(_ url: URL) async throws -> FetchedResource
}

/// Fetches the saved URL directly — the only page Nextmark ever requests
/// (Docs/architecture.md §12). Ephemeral session: no cookies, no cache.
public struct URLSessionPageFetcher: PageFetcher {
    static let maxHTMLBytes = 3_000_000
    static let maxDocumentBytes = 25_000_000

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "Accept": "text/html,application/xhtml+xml,application/pdf;q=0.9,image/*;q=0.8,*/*;q=0.5",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15 Nextmark/0.1",
        ]
        session = URLSession(configuration: configuration)
    }

    public func fetch(_ url: URL) async throws -> FetchedResource {
        let (bytes, response) = try await session.bytes(from: url)
        let http = response as? HTTPURLResponse
        let mimeType = response.mimeType?.lowercased()
        let isDocument = mimeType == "application/pdf" || mimeType?.hasPrefix("image/") == true
        let limit = isDocument ? Self.maxDocumentBytes : Self.maxHTMLBytes

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), limit))
        }
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return FetchedResource(
            data: data,
            mimeType: mimeType,
            textEncodingName: response.textEncodingName,
            finalURL: response.url ?? url,
            statusCode: http?.statusCode ?? 200
        )
    }
}
