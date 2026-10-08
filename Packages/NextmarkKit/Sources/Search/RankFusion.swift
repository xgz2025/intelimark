import Foundation

/// Reciprocal Rank Fusion: merges the lexical (FTS5) and semantic (vector) result
/// lists without having to calibrate their scores against each other.
public enum RankFusion {
    public static func reciprocalRank<ID: Hashable>(_ rankings: [[ID]], k: Double = 60) -> [ID] {
        var scores: [ID: Double] = [:]
        var firstSeen: [ID: Int] = [:]
        for ranking in rankings {
            for (rank, id) in ranking.enumerated() {
                if firstSeen[id] == nil { firstSeen[id] = firstSeen.count }
                scores[id, default: 0] += 1 / (k + Double(rank + 1))
            }
        }
        return firstSeen.keys.sorted { lhs, rhs in
            let (l, r) = (scores[lhs] ?? 0, scores[rhs] ?? 0)
            return l != r ? l > r : (firstSeen[lhs] ?? 0) < (firstSeen[rhs] ?? 0)
        }
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
