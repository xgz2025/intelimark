import Testing
import Search
@testable import Grouping

struct GroupDiscoveryTests {
    /// Two tight topics and a loner, already in the group space.
    let points: [(id: String, vector: [Float])] = [
        ("kyoto-1", [1, 0.05, 0]), ("kyoto-2", [0.95, 0.1, 0]), ("kyoto-3", [1, 0, 0.05]), ("kyoto-4", [0.9, 0.05, 0.1]),
        ("desk-1", [0, 1, 0.05]), ("desk-2", [0.05, 0.95, 0]), ("desk-3", [0, 1, 0.1]),
        ("loner", [0, 0, 1]),
    ]

    @Test func findsOneClusterPerTopic() {
        let clusters = GroupDiscovery(mergeThreshold: 0.8).clusters(among: points)
        #expect(clusters.map { Set($0.itemIDs) } == [["kyoto-1", "kyoto-2", "kyoto-3", "kyoto-4"], ["desk-1", "desk-2", "desk-3"]])
        #expect(clusters.allSatisfy { $0.cohesion > 0.9 })
    }

    @Test func smallClustersAreNotProposed() {
        let clusters = GroupDiscovery(mergeThreshold: 0.8, minimumSize: 4).clusters(among: points)
        #expect(clusters.map(\.itemIDs.count) == [4])
        #expect(GroupDiscovery().clusters(among: Array(points.prefix(2))).isEmpty)
    }

    @Test func dismissedClustersAreNotProposedAgain() {
        let dismissed: Set<String> = ["desk-1", "desk-2", "desk-3"]
        let clusters = GroupDiscovery(mergeThreshold: 0.8).clusters(among: points, dismissed: [dismissed])
        #expect(clusters.map { Set($0.itemIDs) } == [["kyoto-1", "kyoto-2", "kyoto-3", "kyoto-4"]])
    }

    @Test func theThresholdControlsHowFarClustersMerge() {
        // The topics are only weakly related (average similarity about 0.07), so a
        // near-zero threshold merges everything and a real one keeps them apart.
        #expect(GroupDiscovery(mergeThreshold: 0.01).clusters(among: points).map(\.itemIDs.count) == [8])
        #expect(GroupDiscovery(mergeThreshold: 0.5).clusters(among: points).map(\.itemIDs.count) == [4, 3])
    }

    @Test func centeringRemovesTheSharedComponent() {
        // Both vectors share a large common direction; raw cosine says "similar".
        let a: [Float] = [1, 1, 0.2]
        let b: [Float] = [1, 1, -0.2]
        #expect(VectorMath.cosineSimilarity(a, b) > 0.9)
        let space = GroupSpace(library: [a, b])
        #expect(VectorMath.cosineSimilarity(space.project(a), space.project(b)) < -0.9)
        #expect(abs(VectorMath.dot(space.project(a), space.project(a)) - 1) < 1e-5)
    }
}
