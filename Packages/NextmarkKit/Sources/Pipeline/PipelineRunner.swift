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
import Extraction
import Grouping

/// Drains the job queue one job at a time (Docs/architecture.md §5). Stages that
/// aren't built yet complete immediately so the queue never stalls.
public actor PipelineRunner {
    /// Bump when extraction changes; older items are re-run lazily.
    public static let extractVersion = 1
    /// Bump when the Understand prompt or schema changes; older items are re-run lazily.
    /// Provisional (no-model) results are stored as version 0 so they are re-run too.
    public static let understandVersion = 2
    /// Bump when the Brief prompt or schema changes. Heuristic briefs are stored as 0.
    public static let briefVersion = 1

    let queue: JobQueue
    let repository: ItemRepository
    let groups: GroupRepository
    private let extractor: ItemExtractor
    private let understander: any ItemUnderstander
    let embedder: (any EmbeddingProvider)?
    let briefWriter: any GroupBriefWriter
    private let itemsDirectory: URL

    // Group engine state (PipelineRunner+Groups.swift).
    let assigner: GroupAssigner
    let discovery: GroupDiscovery
    var groupSpaces: [String: (space: GroupSpace, computedAt: Date)] = [:]
    var lastDiscovery: Date?
    /// Groups whose Brief the model was too busy to write: when to try again, and how
    /// many times it has been busy, for a growing backoff.
    var briefRetries: [String: (after: Date, failures: Int)] = [:]

    /// - Parameters:
    ///   - itemsDirectory: where the ingestor keeps each item's files (`<itemsDirectory>/<itemID>/…`).
    ///   - embedder: computes item vectors for semantic search and grouping; without one
    ///     the Embed and Group stages are skipped.
    ///   - briefWriter: writes group Briefs.
    ///   - grouping: thresholds for suggesting groups and members.
    public init(
        database: LibraryDatabase,
        itemsDirectory: URL,
        extractor: ItemExtractor = ItemExtractor(),
        understander: any ItemUnderstander,
        embedder: (any EmbeddingProvider)? = nil,
        briefWriter: any GroupBriefWriter = HeuristicBriefWriter(),
        grouping: GroupingOptions = GroupingOptions()
    ) {
        assigner = GroupAssigner(threshold: grouping.assignThreshold)
        discovery = GroupDiscovery(mergeThreshold: grouping.mergeThreshold, minimumSize: grouping.minimumClusterSize)
        queue = JobQueue(database: database)
        repository = ItemRepository(database: database)
        groups = GroupRepository(database: database)
        self.itemsDirectory = itemsDirectory
        self.extractor = extractor
        self.understander = understander
        self.embedder = embedder
        self.briefWriter = briefWriter
    }

    /// How often a stage is tried before giving up. Fetching gets about two days, so
    /// links saved offline (a flight, the subway) still get their page once back online.
    /// Understanding gets a couple of hours while the model is busy or downloading.
    static func maxAttempts(for stage: PipelineStage) -> Int {
        switch stage {
        case .extract: 12
        case .understand: 8
        default: 5
        }
    }

    /// Runs up to `limit` due jobs. Returns how many ran. Stops early when the queue
    /// can't be written (storage full), or the task is cancelled.
    @discardableResult
    public func drain(limit: Int = 25, now: Date = Date()) async -> Int {
        var processed = 0
        while processed < limit, !Task.isCancelled {
            let job: JobRecord
            do {
                guard let claimed = try await queue.claimNext(now: now) else { break }
                job = claimed
            } catch {
                break
            }
            processed += 1
            let lastAttempt = job.attempts >= Self.maxAttempts(for: job.stage)
            if job.attempts > Self.maxAttempts(for: job.stage) {
                // Claimed that often without finishing: it may be what ends the app.
                await giveUp(on: job, now: now)
                continue
            }
            do {
                try await run(job, now: now)
                try await queue.complete(job)
            } catch {
                // Cancelled from outside: the claim already put the job off; it runs later.
                if Task.isCancelled { break }
                if lastAttempt { await giveUp(on: job, now: now) }
            }
        }
        return processed
    }

    private func giveUp(on job: JobRecord, now: Date) async {
        try? await queue.complete(job)
        // Extraction gave up (e.g. offline for days): understand what we have, unless the
        // item already is (a link fetched again later and given up on again).
        if job.stage == .extract,
           let item = try? await repository.item(id: job.itemID), item.derivedVersion < Self.understandVersion {
            try? await queue.enqueue(.understand, itemID: job.itemID, notBefore: now)
        }
    }

    /// Queues Extract again for recent links whose page never arrived, e.g. saved
    /// offline and given up on. Call at launch and when the network comes back.
    @discardableResult
    public func requeueMissingPages(limit: Int = 100, now: Date = Date()) async -> Int {
        let since = now.addingTimeInterval(-14 * 86_400)
        guard let ids = try? await repository.linkIDsNeedingExtraction(below: Self.extractVersion, since: since, limit: limit) else {
            return 0
        }
        // A few more tries each time, not the full two days: a link that's simply gone
        // (a dead domain) costs little.
        let attempts = Self.maxAttempts(for: .extract) - Self.requeuedExtractTries
        var queued = 0
        for id in ids {
            do {
                try await queue.enqueue(.extract, itemID: id, notBefore: now, attempts: attempts)
                queued += 1
            } catch {
                continue
            }
        }
        return queued
    }

    static let requeuedExtractTries = 3

    /// Fetches waiting out a backoff run now: the network just came back.
    public func retryFetchesNow(now: Date = Date()) async {
        try? await queue.makeDue(.extract, now: now)
    }

    /// When the next postponed job is due, to wake the pipeline then.
    public func nextDueDate() async -> Date? {
        try? await queue.nextDueDate()
    }

    /// Queues Understand again for items with provisional or outdated results.
    /// Call when the on-device model is available (e.g. at launch). Returns how many were queued.
    @discardableResult
    public func requeueStaleUnderstanding(limit: Int = 200, now: Date = Date()) async -> Int {
        guard let ids = try? await repository.itemIDsNeedingUnderstanding(below: Self.understandVersion, limit: limit) else {
            return 0
        }
        return await enqueue(.understand, ids: ids, now: now)
    }

    /// Queues Embed for items without a vector, or with one from a model the embedder
    /// has replaced (e.g. after an OS update). Call at launch. Returns how many were queued.
    @discardableResult
    public func requeueStaleEmbeddings(limit: Int = 200, now: Date = Date()) async -> Int {
        guard let embedder else { return 0 }
        var staleModelIDs: [String] = []
        for modelID in (try? await repository.embeddingModelIDs()) ?? [] {
            if !(await embedder.isCurrent(modelID)) { staleModelIDs.append(modelID) }
        }
        guard let ids = try? await repository.itemIDsNeedingEmbedding(staleModelIDs: staleModelIDs, limit: limit) else {
            return 0
        }
        return await enqueue(.embed, ids: ids, now: now)
    }

    /// Items another device created or changed (PRD U6). Vectors don't sync, so they are
    /// embedded here. When this device has the on-device model and the sender's
    /// understanding is older or provisional, it is understood again; the result syncs
    /// back and wins by its higher version. Returns how many were queued.
    @discardableResult
    public func enqueueSyncedItems(_ ids: [String], canUnderstand: Bool, now: Date = Date()) async -> Int {
        var queued = 0
        for id in ids {
            guard let item = try? await repository.item(id: id), item.status != .trashed,
                  (try? await queue.hasJob(forItem: id)) == false
            else { continue }
            // Extraction belongs to the device that has the files; wait for its result.
            let understands = canUnderstand && item.extractVersion > 0 && item.derivedVersion < Self.understandVersion
            do {
                try await queue.enqueue(understands ? .understand : .embed, itemID: id, notBefore: now)
                queued += 1
            } catch {
                continue
            }
        }
        return queued
    }

    func enqueue(_ stage: PipelineStage, ids: [String], now: Date) async -> Int {
        var queued = 0
        for id in ids {
            do {
                try await queue.enqueue(stage, itemID: id, notBefore: now)
                queued += 1
            } catch {
                continue
            }
        }
        return queued
    }

    static func understandingInput(for item: ItemRecord) -> UnderstandingInput {
        let pageText = item.contentText ?? item.pageContext?.excerpt
        return UnderstandingInput(
            title: item.userTitle ?? item.sourceTitle,
            text: pageText ?? item.text,
            highlight: pageText == nil ? nil : item.text,
            url: item.canonicalURL.flatMap { URL(string: $0) },
            note: item.note,
            ocrText: item.ocrText,
            imageLabels: item.imageLabels,
            kind: item.kind,
            capturedAt: item.createdAt
        )
    }

    /// What an item's vector stands for, most telling parts first; the embedder cuts
    /// the end off if it's too long. User words (title, note) come before derived ones.
    static func embeddingText(for item: ItemRecord) -> String {
        var parts: [String] = []
        func add(_ text: String?, limit: Int = 600) {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            if !parts.contains(text) { parts.append(String(text.prefix(limit))) }
        }
        add(item.userTitle ?? item.aiTitle ?? item.sourceTitle)
        add(item.note)
        add(item.summary)
        add(item.text)                    // the highlight, or the saved text
        add(item.imageDescription)
        add(item.keywords.joined(separator: ", "))
        add(item.siteName)
        add(item.ocrText, limit: 400)
        add(item.contentText, limit: 1_000)
        return parts.joined(separator: "\n")
    }

    private func run(_ job: JobRecord, now: Date) async throws {
        switch job.stage {
        case .extract:
            guard let item = try await repository.item(id: job.itemID) else { return }
            let files = try await repository.attachments(forItem: job.itemID)
                .filter { $0.role == .original }
                .map { attachment in
                    LocalFile(
                        url: itemsDirectory.appending(path: job.itemID).appending(path: attachment.fileName),
                        contentType: attachment.contentType
                    )
                }
            let input = ExtractionInput(
                kind: item.kind,
                url: item.canonicalURL.flatMap { URL(string: $0) },
                pageContext: item.pageContext,
                files: files,
                text: item.text,
                capturedAt: item.createdAt
            )
            let extraction = try await extractor.extract(input)
            // The preview first: saving the extraction updates the item, which redraws it.
            if let original = files.first {
                let thumbnail = itemsDirectory.appending(path: job.itemID).appending(path: Thumbnailer.fileName)
                if let byteSize = Thumbnailer.write(from: original, to: thumbnail) {
                    try await repository.saveThumbnail(forItem: job.itemID, fileName: Thumbnailer.fileName, byteSize: byteSize)
                }
            }
            try await repository.applyExtraction(extraction, toItem: job.itemID, version: Self.extractVersion, now: now)
            try await queue.enqueue(.understand, itemID: job.itemID, notBefore: now)

        case .understand:
            guard let item = try await repository.item(id: job.itemID) else { return }
            let understanding: Understanding
            var declined = false
            do {
                understanding = try await understander.understand(Self.understandingInput(for: item))
            } catch let failure as ModelFailure<Understanding> {
                switch failure {
                case .temporary(let fallback):
                    // Busy or still downloading: try the model again later; keep the
                    // stand-in only once the attempts run out.
                    guard job.attempts >= Self.maxAttempts(for: .understand) else { throw failure }
                    understanding = fallback
                case .permanent(let fallback):
                    understanding = fallback
                    declined = true
                }
            }
            let version = understanding.isProvisional ? 0 : Self.understandVersion
            try await repository.applyUnderstanding(understanding, toItem: job.itemID, version: version, now: now)
            if declined {
                // Not tried again at every launch; an OS update may bring a model that can.
                try? await repository.database.recordModelSkip(.understand, subjectID: job.itemID)
            } else if !understanding.isProvisional {
                try? await repository.database.clearModelSkip(.understand, subjectID: job.itemID)
            }
            try await queue.enqueue(.embed, itemID: job.itemID, notBefore: now)

        case .embed:
            guard let embedder, let item = try await repository.item(id: job.itemID) else { return }
            let text = Self.embeddingText(for: item)
            guard !text.isEmpty else {
                try? await repository.database.recordModelSkip(.embed, subjectID: job.itemID)
                return
            }
            let embedding: TextEmbedding
            do {
                embedding = try await embedder.embed(text)
            } catch EmbeddingError.unsupportedLanguage, EmbeddingError.emptyText {
                // Retrying won't help, so it isn't re-queued at every launch (where it would
                // crowd out items that can be embedded); full-text search still finds it.
                try? await repository.database.recordModelSkip(.embed, subjectID: job.itemID)
                return
            }
            try await repository.saveEmbedding(embedding.vector, modelID: embedding.modelID, forItem: job.itemID)
            try? await repository.database.clearModelSkip(.embed, subjectID: job.itemID)
            try await queue.enqueue(.group, itemID: job.itemID, notBefore: now)

        case .group:
            try await suggestGroup(forItem: job.itemID, now: now)

        case .prefilter, .digest, .index, .moments, .rollup:
            // TODO: later milestones (Docs/architecture.md §14, Docs/ai_sessions_spec.md §4).
            break
        }
    }
}
