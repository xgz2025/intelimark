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
import GRDB

/// An item's embedding for one model (Docs/architecture.md §5.2 Embed). Local only:
/// vectors are cheap to recompute and differ between model revisions, so they never sync.
public struct EmbeddingRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "embedding"

    public var itemID: String
    public var modelID: String
    public var vector: Data

    public init(itemID: String, modelID: String, vector: [Float]) {
        self.itemID = itemID
        self.modelID = modelID
        self.vector = VectorBlob.encode(vector)
    }

    public var floats: [Float] { VectorBlob.decode(vector) }
}

/// An item's vector, as read for a semantic scan.
public struct StoredVector: Sendable, Equatable {
    public var itemID: String
    public var vector: [Float]

    public init(itemID: String, vector: [Float]) {
        self.itemID = itemID
        self.vector = vector
    }
}

/// Packs `Float`s into a blob in the platform's byte order (little-endian on every
/// Apple device). Embeddings never leave the device, so no portable format is needed.
public enum VectorBlob {
    public static func encode(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decode(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.stride
        // Copy rather than rebind: SQLite blobs aren't guaranteed to be aligned for Float.
        return [Float](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            _ = data.copyBytes(to: buffer)
            initializedCount = count
        }
    }
}
