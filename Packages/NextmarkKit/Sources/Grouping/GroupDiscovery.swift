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
import Search

/// The space groups are compared in. Mean-pooled sentence vectors share a large
/// common component, so even unrelated texts look similar. Subtracting the
/// library's mean vector removes it and makes thresholds meaningful.
public struct GroupSpace: Sendable {
    public let center: [Float]?

    public init(center: [Float]?) {
        self.center = center
    }

    /// The library's mean vector as the center.
    public init(library vectors: [[Float]]) {
        center = vectors.isEmpty ? nil : VectorMath.mean(vectors)
    }

    /// Centered and scaled to unit length.
    public func project(_ vector: [Float]) -> [Float] {
        guard let center, center.count == vector.count else { return VectorMath.normalized(vector) }
        return VectorMath.normalized(zip(vector, center).map { $0 - $1 })
    }
}

/// A set of related items found by clustering.
public struct DiscoveredCluster: Sendable, Equatable {
    public var itemIDs: [String]
    /// Mean pairwise similarity of the members, in the group space.
    public var cohesion: Float
}

/// Finds groups to suggest (Docs/architecture.md §7, PRD G2): agglomerative
/// clustering with average linkage over ungrouped items. Pure and deterministic.
public struct GroupDiscovery: Sendable {
    /// Clusters stop merging below this average similarity (centered cosine).
    /// Tuned on the eval set; start conservative.
    public var mergeThreshold: Float
    public var minimumSize: Int
    public var maximumSize: Int
    /// A cluster this similar (Jaccard) to a dismissed suggestion isn't proposed again.
    public var dismissedOverlap: Double

    public init(mergeThreshold: Float = 0.5, minimumSize: Int = 3, maximumSize: Int = 40, dismissedOverlap: Double = 0.6) {
        self.mergeThreshold = mergeThreshold
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.dismissedOverlap = dismissedOverlap
    }

    /// Clusters among `points` (vectors already projected into the group space),
    /// largest first.
    public func clusters(among points: [(id: String, vector: [Float])], dismissed: [Set<String>] = []) -> [DiscoveredCluster] {
        let dimension = points.first?.vector.count ?? 0
        let points = points.filter { $0.vector.count == dimension && dimension > 0 }
        let n = points.count
        guard n >= minimumSize else { return [] }

        var similarity = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let value = VectorMath.cosineSimilarity(points[i].vector, points[j].vector)
                similarity[i][j] = value
                similarity[j][i] = value
            }
        }
        let original = similarity

        var members: [[Int]] = (0..<n).map { [$0] }
        var active = [Bool](repeating: true, count: n)
        while true {
            var best: (i: Int, j: Int, value: Float)?
            for i in 0..<n where active[i] {
                // Never grow past the largest group worth suggesting: a big topic stays as
                // several suggestions instead of one that's thrown away.
                for j in (i + 1)..<n where active[j] && similarity[i][j] >= mergeThreshold
                    && members[i].count + members[j].count <= maximumSize {
                    if similarity[i][j] > (best?.value ?? -.infinity) {
                        best = (i, j, similarity[i][j])
                    }
                }
            }
            guard let best else { break }
            let (i, j) = (best.i, best.j)
            // Average linkage (Lance–Williams): the merged cluster's similarity to k
            // is the size-weighted mean of its parts' similarities.
            let (sizeI, sizeJ) = (Float(members[i].count), Float(members[j].count))
            for k in 0..<n where active[k] && k != i && k != j {
                let merged = (sizeI * similarity[i][k] + sizeJ * similarity[j][k]) / (sizeI + sizeJ)
                similarity[i][k] = merged
                similarity[k][i] = merged
            }
            members[i] += members[j]
            members[j] = []
            active[j] = false
        }

        return members.enumerated()
            .filter { index, group in active[index] && group.count >= minimumSize && group.count <= maximumSize }
            .map { _, group in
                var total: Float = 0
                var pairs = 0
                for a in 0..<group.count {
                    for b in (a + 1)..<group.count {
                        total += original[group[a]][group[b]]
                        pairs += 1
                    }
                }
                return DiscoveredCluster(itemIDs: group.map { points[$0].id }, cohesion: pairs > 0 ? total / Float(pairs) : 0)
            }
            .filter { cluster in !dismissed.contains { Self.jaccard(Set(cluster.itemIDs), $0) >= dismissedOverlap } }
            .sorted { $0.itemIDs.count != $1.itemIDs.count ? $0.itemIDs.count > $1.itemIDs.count : $0.cohesion > $1.cohesion }
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        let union = a.union(b).count
        return union == 0 ? 0 : Double(a.intersection(b).count) / Double(union)
    }
}
