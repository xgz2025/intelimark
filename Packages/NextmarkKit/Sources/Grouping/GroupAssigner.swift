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

public struct GroupCentroid: Sendable, Equatable {
    public var groupID: String
    public var vector: [Float]
    public var memberCount: Int

    public init(groupID: String, vector: [Float], memberCount: Int) {
        self.groupID = groupID
        self.vector = vector
        self.memberCount = memberCount
    }

    /// Running mean: the centroid after adding one member.
    public func adding(_ vector: [Float]) -> GroupCentroid {
        let n = Float(memberCount)
        let updated = zip(self.vector, vector).map { ($0 * n + $1) / (n + 1) }
        return GroupCentroid(groupID: groupID, vector: updated, memberCount: memberCount + 1)
    }
}

/// Online assignment of a new item to an accepted group (Docs/architecture.md §7).
/// Returns a *suggestion*; the user (or their auto-file setting) decides.
public struct GroupAssigner: Sendable {
    public struct Suggestion: Sendable, Equatable {
        public var groupID: String
        public var similarity: Float
    }

    /// Tuned on the eval set; start conservative.
    public var threshold: Float

    public init(threshold: Float = 0.78) {
        self.threshold = threshold
    }

    public func suggestion(for vector: [Float], among centroids: [GroupCentroid]) -> Suggestion? {
        centroids
            .filter { $0.vector.count == vector.count }
            .map { Suggestion(groupID: $0.groupID, similarity: VectorMath.cosineSimilarity(vector, $0.vector)) }
            .filter { $0.similarity >= threshold }
            .max { $0.similarity < $1.similarity }
    }
}
