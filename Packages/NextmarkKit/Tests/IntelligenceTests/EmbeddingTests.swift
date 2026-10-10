import Foundation
import Testing
@testable import Intelligence

struct VectorPoolTests {
    @Test func meanIsNormalized() throws {
        var pool = VectorPool()
        pool.add([1, 2])
        pool.add([5, 6])
        let mean = try #require(pool.unitMean)
        #expect(abs(mean[0] - 0.6) < 1e-6)
        #expect(abs(mean[1] - 0.8) < 1e-6)
    }

    @Test func emptyOrMismatchedInputHasNoMean() {
        var pool = VectorPool()
        #expect(pool.unitMean == nil)
        pool.add([0, 0])
        #expect(pool.unitMean == nil)
        pool.add([1, 2, 3])       // wrong dimension: ignored
        #expect(pool.count == 1)
    }
}

/// Runs the real `NLContextualEmbedding` model where its assets are already on the
/// device (they download on demand, so CI's machines usually skip this).
@Suite(.enabled(if: ContextualEmbeddingProvider.hasAssets(forLanguage: "en"), "Needs the English embedding model"))
struct ContextualEmbeddingTests {
    let provider = ContextualEmbeddingProvider()

    func similarity(_ a: TextEmbedding, _ b: TextEmbedding) -> Float {
        zip(a.vector, b.vector).reduce(0) { $0 + $1.0 * $1.1 }
    }

    @Test func relatedTextsAreCloser() async throws {
        let ramen = try await provider.embed("A small ramen restaurant near Kyoto station")
        let noodles = try await provider.embed("Where to eat noodles in Japan")
        let taxes = try await provider.embed("How to file quarterly estimated taxes")
        #expect(ramen.modelID == noodles.modelID)
        #expect(similarity(ramen, noodles) > similarity(ramen, taxes))
        #expect(abs(similarity(ramen, ramen) - 1) < 1e-3)
        #expect(await provider.isCurrent(ramen.modelID))
        #expect(!(await provider.isCurrent("unknown#0")))
    }

    @Test func emptyTextIsRejected() async {
        await #expect(throws: EmbeddingError.emptyText) {
            try await provider.embed("   ")
        }
    }
}
