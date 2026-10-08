import Foundation
import Testing
import Model
@testable import Intelligence

struct HeuristicUnderstanderTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=1", SemanticKind.video),
        ("https://maps.apple.com/?q=ramen", .place),
        ("https://www.google.com/maps/place/x", .place),
        ("https://www.amazon.com/dp/B000", .product),
        ("https://example.com/paper.pdf", .document),
        ("https://example.com/blog/post", .article),
    ])
    func guessesKindFromURL(url: String, expected: SemanticKind) {
        #expect(HeuristicUnderstander.kind(for: UnderstandingInput(url: URL(string: url))) == expected)
    }

    @Test func fallsBackToFirstLineThenHost() {
        #expect(HeuristicUnderstander.title(for: UnderstandingInput(text: "First line\nSecond")) == "First line")
        #expect(HeuristicUnderstander.title(for: UnderstandingInput(url: URL(string: "https://example.com/x"))) == "example.com")
    }

    @Test func keywordsAreFrequentNonStopwords() {
        let input = UnderstandingInput(title: "Ramen ramen guide", text: "The best ramen shops with late hours in Kyoto. Kyoto ramen.")
        #expect(Array(HeuristicUnderstander.keywords(for: input).prefix(2)) == ["ramen", "kyoto"])
    }

    @Test func promptIsTruncated() {
        let input = UnderstandingInput(text: String(repeating: "a", count: 10_000))
        #expect(input.promptText.count < UnderstandingInput.maxContentCharacters + 50)
    }
}
