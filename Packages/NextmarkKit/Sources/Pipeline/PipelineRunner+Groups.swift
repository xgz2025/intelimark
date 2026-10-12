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
import Model
import Library
import Intelligence
import Search
import Grouping

/// Thresholds for the group engine, in the centered space of `GroupSpace`.
/// Starting values, to be tuned on the eval set (Docs/architecture.md §7).
public struct GroupingOptions: Sendable {
    /// A new item is suggested for the nearest accepted group at or above this similarity.
    public var assignThreshold: Float
    /// Clusters of ungrouped items merge down to this average similarity.
    public var mergeThreshold: Float
    public var minimumClusterSize: Int

    public init(assignThreshold: Float = 0.6, mergeThreshold: Float = 0.5, minimumClusterSize: Int = 3) {
        self.assignThreshold = assignThreshold
        self.mergeThreshold = mergeThreshold
        self.minimumClusterSize = minimumClusterSize
    }
}

/// The group engine (Docs/architecture.md §7): online assignment of new items,
/// batch discovery of suggested groups, and Briefs.
extension PipelineRunner {
    static let groupSpaceLifetime: TimeInterval = 10 * 60
    static let discoveryInterval: TimeInterval = 30 * 60
    static let discoveryWindow: TimeInterval = 90 * 86_400
    static let maximumSuggestionsPerPass = 3
    static let maximumBriefsPerPass = 5

    /// Group stage: suggests the nearest accepted group for a newly embedded item.
    /// The user confirms or removes the suggestion; a removal is never undone.
    func suggestGroup(forItem itemID: String, now: Date) async throws {
        guard embedder != nil,
              let item = try await repository.item(id: itemID), item.status == .inbox || item.status == .active,
              let embedding = try await repository.embedding(forItem: itemID)
        else { return }
        let memberVectors = try await groups.memberVectors(modelID: embedding.modelID)
        guard !memberVectors.isEmpty else { return }
        let space = try await groupSpace(for: embedding.modelID, now: now)
        let centroids = memberVectors.map { groupID, vectors in
            GroupCentroid(
                groupID: groupID,
                vector: VectorMath.mean(vectors.map { space.project($0) }),
                memberCount: vectors.count
            )
        }
        guard let suggestion = assigner.suggestion(for: space.project(embedding.floats), among: centroids) else { return }
        try await groups.suggestMembership(
            itemID: itemID, groupID: suggestion.groupID, score: Double(suggestion.similarity), now: now
        )
    }

    /// Proposes new groups (at most every 30 minutes, or when forced) and writes the
    /// Briefs of groups whose members changed. Call after draining the queue.
    public func maintainGroups(now: Date = Date(), force: Bool = false) async {
        let due = lastDiscovery.map { now.timeIntervalSince($0) >= Self.discoveryInterval } ?? true
        if force || due {
            lastDiscovery = now
            await discoverGroups(now: now)
        }
        await writeBriefs(now: now)
    }

    /// Queues Briefs written without the model (or with an older prompt) to be
    /// written again. Call when the on-device model is available. Returns how many.
    @discardableResult
    public func requeueStaleBriefs() async -> Int {
        guard let ids = try? await groups.groupIDsWithStaleBriefs(below: Self.briefVersion), !ids.isEmpty else { return 0 }
        try? await groups.invalidateBriefs(ids)
        return ids.count
    }

    func discoverGroups(now: Date) async {
        guard embedder != nil, let modelIDs = try? await repository.embeddingModelIDs() else { return }
        let dismissed = (try? await groups.dismissedMemberSets()) ?? []
        var suggested = 0
        for modelID in modelIDs where suggested < Self.maximumSuggestionsPerPass {
            guard let points = try? await groups.ungroupedVectors(modelID: modelID, since: now.addingTimeInterval(-Self.discoveryWindow)),
                  points.count >= discovery.minimumSize,
                  let space = try? await groupSpace(for: modelID, now: now)
            else { continue }
            let projected = points.map { (id: $0.itemID, vector: space.project($0.vector)) }
            let clusters = discovery.clusters(among: projected, dismissed: dismissed)
            for cluster in clusters.prefix(Self.maximumSuggestionsPerPass - suggested) {
                let items = (try? await repository.items(ids: cluster.itemIDs)) ?? []
                let title = TopicNamer.topic(of: items.map(\.digest))
                guard (try? await groups.addSuggestedGroup(
                    title: title, itemIDs: cluster.itemIDs, score: Double(cluster.cohesion), now: now
                )) != nil else { continue }
                suggested += 1
            }
        }
    }

    func writeBriefs(now: Date) async {
        guard let ids = try? await groups.groupIDsNeedingBrief(now: now) else { return }
        for id in ids.prefix(Self.maximumBriefsPerPass) {
            guard let inputs = try? await groups.briefInputs(for: id) else { continue }
            let input = BriefInput(
                title: inputs.group.userTitle,
                goal: inputs.group.goal,
                targetDate: inputs.group.targetDate,
                items: inputs.members.map(\.digest)
            )
            guard let brief = try? await briefWriter.brief(for: input) else { continue }
            let version = brief.isProvisional ? 0 : Self.briefVersion
            try? await groups.saveBrief(brief, inputsHash: inputs.hash, version: version, toGroup: id, now: now)
        }
    }

    /// The centered space for one embedding model, refreshed every few minutes.
    func groupSpace(for modelID: String, now: Date) async throws -> GroupSpace {
        if let cached = groupSpaces[modelID], abs(now.timeIntervalSince(cached.computedAt)) < Self.groupSpaceLifetime {
            return cached.space
        }
        let vectors = try await repository.vectors(modelID: modelID, matching: SearchQuery())
        let space = GroupSpace(library: vectors.map(\.vector))
        groupSpaces[modelID] = (space, now)
        return space
    }
}
