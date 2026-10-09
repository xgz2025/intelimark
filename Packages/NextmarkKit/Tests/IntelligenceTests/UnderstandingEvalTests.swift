#if canImport(FoundationModels)
import Foundation
import Testing
import Model
@testable import Intelligence

/// Runs the real on-device model on a few fixtures. Skipped wherever Apple
/// Intelligence isn't available — including CI's virtual machines — so run
/// `make test` on a Mac with Apple Intelligence before changing the prompt or
/// the generation schema. Assertions are deliberately loose: the model is not
/// deterministic, but grounding must never let an invented fact through.
@Suite(.enabled(if: IntelligenceStatus.current == .available, "Needs Apple Intelligence"))
struct UnderstandingEvalTests {
    let understander = FoundationModelsUnderstander()
    let saved: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9))!
    }()

    @Test func concertTicket() async throws {
        let input = UnderstandingInput(
            title: "Your tickets: Autumn concert",
            text: "Autumn concert at Budokan. Saturday, November 21, 2026 — doors 6:00 PM, show 7:30 PM. Seat B-12. Refunds until November 1, 2026.",
            kind: .text,
            capturedAt: saved
        )
        let understanding = try await understander.understand(input)
        #expect(!understanding.isProvisional)
        #expect([SemanticKind.event, .ticket].contains(understanding.semanticKind))
        #expect(understanding.dates.contains { Calendar.current.component(.day, from: $0.date) == 21 })
        #expect(understanding.places.contains { $0.name.localizedCaseInsensitiveContains("Budokan") })
        // Every kept fact is quoted from the input.
        for date in understanding.dates {
            #expect(input.groundingText.localizedCaseInsensitiveContains(date.evidence ?? "∅"))
        }
    }

    @Test func recipe() async throws {
        let understanding = try await understander.understand(UnderstandingInput(
            title: "Miso ramen at home",
            text: "Ingredients: 200 g fresh noodles, 2 tbsp white miso, 1 litre chicken stock, 2 eggs. Simmer the stock, whisk in the miso, cook the noodles for 3 minutes.",
            kind: .link,
            capturedAt: saved
        ))
        #expect(understanding.semanticKind == .recipe)
        #expect(understanding.dates.isEmpty)
    }

    @Test func screenshotIsDescribed() async throws {
        let understanding = try await understander.understand(UnderstandingInput(
            ocrText: "Hotel Kyoto Guest Wi-Fi\nNetwork: HK_Guest\nPassword: momiji2026",
            imageLabels: ["document", "text"],
            kind: .image,
            capturedAt: saved
        ))
        let description = try #require(understanding.imageDescription)
        #expect(!description.isEmpty)
    }

    @Test func japaneseContentStaysInJapanese() async throws {
        let understanding = try await understander.understand(UnderstandingInput(
            title: "京都の紅葉スポット",
            text: String(repeating: "嵐山と東福寺の紅葉は十一月中旬から下旬が見頃です。", count: 200),
            kind: .link,
            capturedAt: saved
        ))
        #expect(understanding.summary.unicodeScalars.contains { TokenBudget.isWide($0) })
    }
}
#endif
