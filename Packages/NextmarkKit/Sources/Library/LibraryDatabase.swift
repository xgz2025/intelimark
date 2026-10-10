import Foundation
import GRDB

/// The on-device library: SQLite through GRDB, with FTS5 for search.
/// Only the main app opens it; extensions write capture envelopes instead.
public final class LibraryDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func onDisk(at url: URL) throws -> LibraryDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration)
        return try LibraryDatabase(writer: pool)
    }

    public static func inMemory() throws -> LibraryDatabase {
        try LibraryDatabase(writer: DatabaseQueue())
    }
}

extension LibraryDatabase {
    /// A live query: emits the value now and again whenever its tables change, so
    /// UI code observes through `AsyncThrowingStream`s and never imports GRDB.
    func observe<Value: Sendable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncThrowingStream<Value, any Error> {
        let writer = writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in ValueObservation.tracking(fetch).values(in: writer) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
