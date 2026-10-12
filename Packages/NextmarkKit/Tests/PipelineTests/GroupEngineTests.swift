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
import Testing
import Model
import Capture
import Library
import Intelligence
import Extraction
@testable import Pipeline

/// Words map to topics; every text shares a constant component, like real sentence vectors.
struct TopicEmbedder: EmbeddingProvider {
    static let topics: [[String]] = [["kyoto", "temple", "ramen", "garden"], ["desk", "chair", "lamp"]]

    func embed(_ text: String) async throws -> TextEmbedding {
        let lowered = text.lowercased()
        let hits = Self.topics.map { words in Float(words.filter { lowered.contains($0) }.count) }
        let vector = hits + [0.3]
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return TextEmbedding(modelID: "topics#1", vector: vector.map { $0 / norm })
    }

    func isCurrent(_ modelID: String) async -> Bool { true }
}

struct GroupEngineTests {
    let harness: PipelineHarness
    let now = Date()

    init() throws {
        harness = try PipelineHarness()
    }

    var groups: GroupRepository { GroupRepository(database: harness.database) }

    func makeRunner() -> PipelineRunner {
        PipelineRunner(
            database: harness.database,
            itemsDirectory: harness.itemsDirectory,
            extractor: ItemExtractor(fetcher: StubFetcher.html(""), imageAnalyzer: nil),
            understander: HeuristicUnderstander(),
            embedder: TopicEmbedder(),
            briefWriter: HeuristicBriefWriter()
        )
    }

    /// Saves notes and runs them through the pipeline. Returns their item IDs.
    @discardableResult
    func save(_ texts: [String], with runner: PipelineRunner) async throws -> [String] {
        var ids: [String] = []
        for text in texts {
            let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: text)
            try await harness.capture(envelope, now: now)
            ids.append(envelope.id.rawValue)
        }
        await runner.drain(limit: 200, now: now)
        return ids
    }

    func summaries(_ states: [GroupState]) async throws -> [GroupSummary] {
        for try await value in groups.summaries(states: states) { return value }
        return []
    }

    @Test func relatedSavesBecomeSuggestedGroups() async throws {
        let runner = makeRunner()
        let kyoto = try await save(["Kyoto temple visit", "Kyoto ramen shop", "Kyoto garden tour"], with: runner)
        let desk = try await save(["Standing desk", "Desk lamp", "Office chair"], with: runner)

        await runner.maintainGroups(now: now, force: true)
        let suggested = try await summaries([.suggested])
        #expect(suggested.count == 2)
        var memberSets: [Set<String>] = []
        for summary in suggested {
            for try await detail in groups.detail(id: summary.id) {
                memberSets.append(Set(detail?.members.map(\.item.id) ?? []))
                break
            }
        }
        #expect(Set(memberSets) == [Set(kyoto), Set(desk)])

        // Grouped (even suggested) items aren't proposed again.
        await runner.maintainGroups(now: now, force: true)
        #expect(try await summaries([.suggested]).count == 2)
    }

    @Test func newSavesAreSuggestedForTheirGroup() async throws {
        let runner = makeRunner()
        let kyoto = try await save(["Kyoto temple visit", "Kyoto ramen shop", "Kyoto garden tour"], with: runner)
        try await save(["Standing desk", "Desk lamp", "Office chair"], with: runner)
        let groupID = try await groups.createGroup(title: "Kyoto trip", itemIDs: kyoto, now: now)

        let newcomer = try await save(["Kyoto ramen alley"], with: runner)
        try await save(["Desk mat"], with: runner)

        let summary = try #require(try await summaries([.accepted]).first { $0.id == groupID })
        #expect(summary.memberCount == 3)
        #expect(summary.suggestedCount == 1)
        for try await detail in groups.detail(id: groupID) {
            #expect(detail?.members.filter(\.membership.isSuggested).map(\.item.id) == newcomer)
            break
        }
    }

    @Test func groupsGetABriefOnceTheirMembersSettle() async throws {
        let runner = makeRunner()
        let items = try await save(["Kyoto temple visit", "Kyoto ramen shop"], with: runner)
        let groupID = try await groups.createGroup(title: "Kyoto trip", itemIDs: items, now: now)

        await runner.maintainGroups(now: now)
        #expect(try await groups.group(id: groupID)?.brief == nil)                // still debounced

        await runner.maintainGroups(now: now.addingTimeInterval(11 * 60))
        let group = try #require(try await groups.group(id: groupID))
        let brief = try #require(group.brief)
        #expect(brief.title == "Kyoto trip")
        #expect(brief.isProvisional)
        #expect(group.briefVersion == 0)

        // With the model available, provisional briefs are queued again.
        #expect(await runner.requeueStaleBriefs() == 1)
        #expect(try await groups.groupIDsNeedingBrief(now: now.addingTimeInterval(11 * 60)) == [groupID])
    }
}
