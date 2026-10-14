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

/// Fetches the saved URL directly — the only page Laterwise ever requests
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
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15 Laterwise/1.0",
        ]
        session = URLSession(configuration: configuration)
    }

    /// A page cut off at the size limit can end inside a multi-byte character, which
    /// makes the whole page fail UTF-8 decoding and come out garbled.
    static func dropIncompleteUTF8Tail(_ data: inout Data) {
        // Walk back over continuation bytes (10xxxxxx) to the last character's first byte.
        var index = data.endIndex
        var continuation = 0
        while index > data.startIndex, continuation < 3, data[index - 1] & 0b1100_0000 == 0b1000_0000 {
            index -= 1
            continuation += 1
        }
        guard index > data.startIndex else { return }
        let lead = data[index - 1]
        guard lead >= 0b1100_0000 else { return }
        let length = lead >= 0b1111_0000 ? 4 : lead >= 0b1110_0000 ? 3 : 2
        if continuation + 1 < length {
            data.removeSubrange((index - 1)...)
        }
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
        if !isDocument, data.count >= limit {
            Self.dropIncompleteUTF8Tail(&data)
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
