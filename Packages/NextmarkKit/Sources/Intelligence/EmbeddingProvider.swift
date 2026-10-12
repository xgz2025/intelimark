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

/// A sentence vector and the model that produced it. Vectors are only comparable
/// with vectors from the same `modelID`.
public struct TextEmbedding: Sendable, Equatable {
    public var modelID: String
    /// Unit length, so a dot product is the cosine similarity.
    public var vector: [Float]

    public init(modelID: String, vector: [Float]) {
        self.modelID = modelID
        self.vector = vector
    }
}

/// Turns text into vectors for semantic search and grouping (Docs/architecture.md §6.1).
public protocol EmbeddingProvider: Sendable {
    func embed(_ text: String) async throws -> TextEmbedding
    /// False when vectors from `modelID` should be recomputed, e.g. after an OS
    /// update replaced the model.
    func isCurrent(_ modelID: String) async -> Bool
}

public enum EmbeddingError: Error, Equatable {
    case emptyText
    case unsupportedLanguage
    /// The model's assets aren't on the device yet; the job retries later.
    case assetsUnavailable
}

/// Mean-pools token vectors into one unit-length sentence vector.
struct VectorPool {
    private(set) var sum: [Double] = []
    private(set) var count = 0

    mutating func add(_ vector: [Double]) {
        if sum.isEmpty { sum = [Double](repeating: 0, count: vector.count) }
        guard vector.count == sum.count else { return }
        for index in sum.indices { sum[index] += vector[index] }
        count += 1
    }

    /// The normalized mean, or nil when nothing (or only zeros) was added.
    var unitMean: [Float]? {
        guard count > 0 else { return nil }
        let norm = sum.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return nil }
        // The mean's direction equals the sum's, so normalizing the sum is enough.
        return sum.map { Float($0 / norm) }
    }
}
