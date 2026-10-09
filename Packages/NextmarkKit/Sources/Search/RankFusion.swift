import Foundation

/// Reciprocal Rank Fusion: merges the lexical (FTS5) and semantic (vector) result
/// lists without having to calibrate their scores against each other.
public enum RankFusion {
    public static func reciprocalRank<ID: Hashable>(_ rankings: [[ID]], k: Double = 60) -> [ID] {
        let fused = scores(rankings, k: k)
        return fused.order.sorted { lhs, rhs in
            let (l, r) = (fused.scores[lhs] ?? 0, fused.scores[rhs] ?? 0)
            return l != r ? l > r : (fused.firstSeen[lhs] ?? 0) < (fused.firstSeen[rhs] ?? 0)
        }
    }

    /// Each ID's fused score, Σ 1 / (k + rank), plus the order IDs were first seen in
    /// (to break ties deterministically).
    public static func scores<ID: Hashable>(
        _ rankings: [[ID]], k: Double = 60
    ) -> (scores: [ID: Double], order: [ID], firstSeen: [ID: Int]) {
        var scores: [ID: Double] = [:]
        var firstSeen: [ID: Int] = [:]
        var order: [ID] = []
        for ranking in rankings {
            for (rank, id) in ranking.enumerated() {
                if firstSeen[id] == nil {
                    firstSeen[id] = order.count
                    order.append(id)
                }
                scores[id, default: 0] += 1 / (k + Double(rank + 1))
            }
        }
        return (scores, order, firstSeen)
    }
}

public enum VectorMath {
    public static func dot(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "Vectors must have the same dimension")
        var sum: Float = 0
        for index in a.indices { sum += a[index] * b[index] }
        return sum
    }

    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let denominator = dot(a, a).squareRoot() * dot(b, b).squareRoot()
        return denominator == 0 ? 0 : dot(a, b) / denominator
    }

    /// The vector scaled to unit length (zero vectors stay zero).
    public static func normalized(_ vector: [Float]) -> [Float] {
        let norm = dot(vector, vector).squareRoot()
        return norm == 0 ? vector : vector.map { $0 / norm }
    }

    /// Element-wise mean, e.g. to pool token embeddings into one sentence vector.
    public static func mean(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors {
            for index in sum.indices { sum[index] += vector[index] }
        }
        return sum.map { $0 / Float(vectors.count) }
    }
}
