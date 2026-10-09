import Testing
@testable import Search

struct RankFusionTests {
    @Test func itemsInBothListsRankFirst() {
        let fused = RankFusion.reciprocalRank([["a", "b", "c"], ["b", "c", "d"]])
        #expect(fused == ["b", "c", "a", "d"])
    }

    @Test func scoresSumReciprocalRanks() {
        let fused = RankFusion.scores([["a", "b"], ["b"]], k: 1)
        #expect(fused.scores == ["a": 0.5, "b": 1.0 / 3 + 0.5])
        #expect(fused.order == ["a", "b"])
    }

    @Test func cosineSimilarity() {
        #expect(VectorMath.cosineSimilarity([1, 0], [1, 0]) == 1)
        #expect(VectorMath.cosineSimilarity([1, 0], [0, 1]) == 0)
        #expect(VectorMath.cosineSimilarity([0, 0], [1, 1]) == 0)
        #expect(VectorMath.mean([[1, 3], [3, 5]]) == [2, 4])
        #expect(VectorMath.normalized([3, 4]) == [0.6, 0.8])
        #expect(VectorMath.normalized([0, 0]) == [0, 0])
    }
}
