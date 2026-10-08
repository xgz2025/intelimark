import Testing
@testable import Search

struct RankFusionTests {
    @Test func itemsInBothListsRankFirst() {
        let fused = RankFusion.reciprocalRank([["a", "b", "c"], ["b", "c", "d"]])
        #expect(fused == ["b", "c", "a", "d"])
    }

    @Test func cosineSimilarity() {
        #expect(VectorMath.cosineSimilarity([1, 0], [1, 0]) == 1)
        #expect(VectorMath.cosineSimilarity([1, 0], [0, 1]) == 0)
        #expect(VectorMath.cosineSimilarity([0, 0], [1, 1]) == 0)
        #expect(VectorMath.mean([[1, 3], [3, 5]]) == [2, 4])
    }
}
