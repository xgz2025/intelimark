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
#if canImport(Compression)
import Compression
#endif

/// Reads single entries from a ZIP archive: a Wallet pass (`pass.json`) or a Word
/// document (`word/document.xml`). Stored and deflated entries only; no ZIP64,
/// no encryption. Sizes are capped, so a hostile archive can't exhaust memory.
struct ZipArchive {
    static let maxArchiveBytes = 50 * 1024 * 1024
    static let maxEntryBytes = 20 * 1024 * 1024

    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    let data: Data
    let entries: [Entry]

    init?(url: URL) {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= Self.maxArchiveBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return nil }
        self.init(data: data)
    }

    init?(data: Data) {
        // Offsets below count from zero: a slice of other data starts elsewhere.
        let data = data.startIndex == 0 ? data : Data(data)
        guard data.count <= Self.maxArchiveBytes, let entries = Self.centralDirectory(of: data) else { return nil }
        self.data = data
        self.entries = entries
    }

    /// The entry named `name` (exact, case-insensitive), uncompressed.
    func contents(of name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return nil }
        return contents(of: entry)
    }

    func contents(of entry: Entry) -> Data? {
        guard entry.uncompressedSize <= Self.maxEntryBytes,
              let nameLength = data.uint16(at: entry.localHeaderOffset + 26),
              let extraLength = data.uint16(at: entry.localHeaderOffset + 28),
              data.uint32(at: entry.localHeaderOffset) == 0x0403_4B50
        else { return nil }
        let start = entry.localHeaderOffset + 30 + Int(nameLength) + Int(extraLength)
        let end = start + entry.compressedSize
        guard start >= 0, end <= data.count, start <= end else { return nil }
        let compressed = data.subdata(in: start..<end)
        switch entry.method {
        case 0: return compressed
        case 8: return Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default: return nil
        }
    }

    /// The End of Central Directory record, then each file header.
    static func centralDirectory(of data: Data) -> [Entry]? {
        // The record is in the last 64 KB + 22 bytes (its comment is at most 64 KB).
        let lowest = max(0, data.count - 65_557)
        var position = data.count - 22
        var directoryOffset: Int?
        var count = 0
        while position >= lowest {
            if data.uint32(at: position) == 0x0605_4B50 {
                count = Int(data.uint16(at: position + 10) ?? 0)
                directoryOffset = data.uint32(at: position + 16).map(Int.init)
                break
            }
            position -= 1
        }
        guard var offset = directoryOffset, count > 0, count < 10_000 else { return nil }
        var entries: [Entry] = []
        for _ in 0..<count {
            guard data.uint32(at: offset) == 0x0201_4B50,
                  let method = data.uint16(at: offset + 10),
                  let compressed = data.uint32(at: offset + 20),
                  let uncompressed = data.uint32(at: offset + 24),
                  let nameLength = data.uint16(at: offset + 28),
                  let extraLength = data.uint16(at: offset + 30),
                  let commentLength = data.uint16(at: offset + 32),
                  let localOffset = data.uint32(at: offset + 42),
                  offset + 46 + Int(nameLength) <= data.count
            else { return entries.isEmpty ? nil : entries }
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + Int(nameLength)))
            let name = String(decoding: nameData, as: UTF8.self)
            entries.append(Entry(
                name: name, method: method, compressedSize: Int(compressed),
                uncompressedSize: Int(uncompressed), localHeaderOffset: Int(localOffset)
            ))
            offset += 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
        }
        return entries
    }

    /// Raw deflate (what ZIP uses; Compression's zlib is raw deflate).
    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        #if canImport(Compression)
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            data.withUnsafeBytes { source -> Int in
                guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    destinationBase, expectedSize, sourceBase, data.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        output.count = written
        return output
        #else
        return nil
        #endif
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let base = startIndex + offset
        return UInt16(self[base]) | UInt16(self[base + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let base = startIndex + offset
        return UInt32(self[base]) | UInt32(self[base + 1]) << 8 | UInt32(self[base + 2]) << 16 | UInt32(self[base + 3]) << 24
    }
}
