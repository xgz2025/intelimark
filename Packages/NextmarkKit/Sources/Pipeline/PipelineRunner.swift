import Foundation
import Model
import Library
import Intelligence

/// Drains the job queue one job at a time (Docs/architecture.md §5). Stages that
/// aren't built yet complete immediately so the queue never stalls.
public actor PipelineRunner {
    /// Bump when the Understand prompt or schema changes; older items are re-run lazily.
    public static let understandVersion = 1

    private let queue: JobQueue
    private let repository: ItemRepository
    private let understander: any ItemUnderstander

    public init(database: LibraryDatabase, understander: any ItemUnderstander) {
        queue = JobQueue(database: database)
        repository = ItemRepository(database: database)
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
                try? await queue.retry(job, now: now)
            }
            processed += 1
        }
        return processed
    }

    private func run(_ job: JobRecord, now: Date) async throws {
        switch job.stage {
        case .extract:
            // TODO: link metadata, readable text, JSON-LD, PDF text, Vision OCR (PRD U1).
            try await queue.enqueue(.understand, itemID: job.itemID, notBefore: now)

        case .understand:
            guard let item = try await repository.item(id: job.itemID) else { return }
            let input = UnderstandingInput(
                title: item.userTitle ?? item.sourceTitle,
                text: item.text ?? item.pageContext?.excerpt,
                url: item.canonicalURL.flatMap { URL(string: $0) },
                note: item.note,
                ocrText: item.ocrText
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
