import Foundation
import Model
import Library
import Intelligence
import Extraction

/// Drains the job queue one job at a time (Docs/architecture.md §5). Stages that
/// aren't built yet complete immediately so the queue never stalls.
public actor PipelineRunner {
    /// Bump when extraction changes; older items are re-run lazily.
    public static let extractVersion = 1
    /// Bump when the Understand prompt or schema changes; older items are re-run lazily.
    public static let understandVersion = 1

    private let queue: JobQueue
    private let repository: ItemRepository
    private let extractor: ItemExtractor
    private let understander: any ItemUnderstander
    private let itemsDirectory: URL

    /// - Parameter itemsDirectory: where the ingestor keeps each item's files (`<itemsDirectory>/<itemID>/…`).
    public init(
        database: LibraryDatabase,
        itemsDirectory: URL,
        extractor: ItemExtractor = ItemExtractor(),
        understander: any ItemUnderstander
    ) {
        queue = JobQueue(database: database)
        repository = ItemRepository(database: database)
        self.itemsDirectory = itemsDirectory
        self.extractor = extractor
        self.understander = understander
    }

    /// Runs up to `limit` due jobs. Returns how many ran.
    @discardableResult
    public func drain(limit: Int = 25, now: Date = Date()) async -> Int {
        var processed = 0
        while processed < limit, let job = try? await queue.next(now: now) {
            do {
                try await run(job, now: now)
                try await queue.complete(job)
            } catch {
                let willRetry = (try? await queue.retry(job, now: now)) ?? false
                if !willRetry, job.stage == .extract {
                    // Extraction gave up (e.g. offline for days): understand what we have.
                    try? await queue.enqueue(.understand, itemID: job.itemID, notBefore: now)
                }
            }
            processed += 1
        }
        return processed
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
                files: files
            )
            let extraction = try await extractor.extract(input)
            try await repository.applyExtraction(extraction, toItem: job.itemID, version: Self.extractVersion, now: now)
            try await queue.enqueue(.understand, itemID: job.itemID, notBefore: now)

        case .understand:
            guard let item = try await repository.item(id: job.itemID) else { return }
            let input = UnderstandingInput(
                title: item.userTitle ?? item.sourceTitle,
                text: item.text ?? item.contentText ?? item.pageContext?.excerpt,
                url: item.canonicalURL.flatMap { URL(string: $0) },
                note: item.note,
                ocrText: item.ocrText,
                imageLabels: item.imageLabels
            )
            let understanding = try await understander.understand(input)
            try await repository.applyUnderstanding(understanding, toItem: job.itemID, version: Self.understandVersion, now: now)
            try await queue.enqueue(.embed, itemID: job.itemID, notBefore: now)

        case .prefilter, .digest, .embed, .index, .group, .moments, .rollup:
            // TODO: later milestones (Docs/architecture.md §14, Docs/ai_sessions_spec.md §4).
            break
        }
    }
}
