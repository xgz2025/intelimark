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

    /// In the app's own container, not the App Group's: iOS ends an app that is
    /// suspended while holding a SQLite lock in a shared container (0xdead10cc), and
    /// only the app opens the library.
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Database/library.sqlite")
    }

    /// Moves a library that earlier builds kept at `legacy` (with its WAL files) to
    /// `url`, unless one is already there. Returns where the library is: `url`, or
    /// `legacy` when it couldn't be moved, so it's opened there rather than an empty
    /// one being made at `url`.
    @discardableResult
    public static func moveLegacyDatabase(from legacy: URL, to url: URL) -> URL {
        let fileManager = FileManager.default
        let old = legacy.path(percentEncoded: false)
        let new = url.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: old), !fileManager.fileExists(atPath: new) else { return url }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The database file goes last, so a failure never leaves it apart from its log.
        var moved: [(from: String, to: String)] = []
        for suffix in ["-wal", "-shm", ""] where fileManager.fileExists(atPath: old + suffix) {
            do {
                try fileManager.moveItem(atPath: old + suffix, toPath: new + suffix)
                moved.append((old + suffix, new + suffix))
            } catch {
                for file in moved.reversed() {
                    try? fileManager.moveItem(atPath: file.to, toPath: file.from)
                }
                return legacy
            }
        }
        return url
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
