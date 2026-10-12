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
import UniformTypeIdentifiers
import Model

/// A committed capture waiting in the Inbox.
public struct CommittedCapture: Sendable {
    public let envelope: CaptureEnvelope
    public let directory: URL

    public func payloadURL(for file: PayloadFile) -> URL {
        directory
            .appending(path: EnvelopeStore.payloadDirectoryName, directoryHint: .isDirectory)
            .appending(path: file.fileName)
    }
}

/// Reads and writes capture envelopes in the App Group Inbox:
///
///     Inbox/<ULID>/payload/…        raw files, written first
///     Inbox/<ULID>/envelope.json    written last (atomic) = commit marker
///
/// Capture surfaces only ever call `makePayloadDirectory` and `commit`; the main
/// app reads, ingests and removes. Directories without an envelope are abandoned
/// captures and are garbage-collected after a day.
public struct EnvelopeStore: Sendable {
    public static let envelopeFileName = "envelope.json"
    public static let payloadDirectoryName = "payload"

    public let inboxURL: URL

    public init(inboxURL: URL = AppGroup.inboxURL) {
        self.inboxURL = inboxURL
    }

    public func directory(for id: ULID) -> URL {
        inboxURL.appending(path: id.rawValue, directoryHint: .isDirectory)
    }

    @discardableResult
    public func makePayloadDirectory(for id: ULID) throws -> URL {
        let url = directory(for: id).appending(path: Self.payloadDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies a file into the capture's payload directory as `<index>-<name>`.
    /// The content type comes from the file itself, falling back to its extension.
    public func addPayloadFile(copying source: URL, for id: ULID, index: Int) throws -> PayloadFile {
        let fileName = "\(index)-\(source.lastPathComponent)"
        let destination = try makePayloadDirectory(for: id).appending(path: fileName)
        try FileManager.default.copyItem(at: source, to: destination)
        let values = try? destination.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
        let type = values?.contentType ?? UTType(filenameExtension: source.pathExtension) ?? .data
        return PayloadFile(fileName: fileName, contentType: type.identifier, byteSize: values?.fileSize.map { Int64($0) })
    }

    /// Writes data (e.g. a screenshot) into the capture's payload directory.
    public func addPayload(_ data: Data, fileName: String, contentType: UTType, for id: ULID) throws -> PayloadFile {
        let destination = try makePayloadDirectory(for: id).appending(path: fileName)
        try data.write(to: destination, options: .atomic)
        return PayloadFile(fileName: fileName, contentType: contentType.identifier, byteSize: Int64(data.count))
    }

    public func commit(_ envelope: CaptureEnvelope) throws {
        let directory = directory(for: envelope.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        try data.write(to: directory.appending(path: Self.envelopeFileName), options: .atomic)
    }

    /// Committed captures, oldest first. Unreadable envelopes are skipped and left in place.
    public func committedCaptures() throws -> [CommittedCapture] {
        let decoder = JSONDecoder()
        return try captureDirectories()
            .compactMap { directory -> CommittedCapture? in
                guard
                    let data = try? Data(contentsOf: directory.appending(path: Self.envelopeFileName)),
                    let envelope = try? decoder.decode(CaptureEnvelope.self, from: data)
                else { return nil }
                return CommittedCapture(envelope: envelope, directory: directory)
            }
            .sorted { $0.envelope.id < $1.envelope.id }
    }

    public func discard(_ id: ULID) throws {
        let directory = directory(for: id)
        if FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Removes uncommitted capture directories older than `age`. Returns how many were removed.
    @discardableResult
    public func collectGarbage(olderThan age: TimeInterval = 24 * 60 * 60, now: Date = Date()) throws -> Int {
        var removed = 0
        for directory in try captureDirectories() {
            guard let id = ULID(directory.lastPathComponent), now.timeIntervalSince(id.date) > age else { continue }
            let envelopePath = directory.appending(path: Self.envelopeFileName).path(percentEncoded: false)
            if !FileManager.default.fileExists(atPath: envelopePath) {
                try FileManager.default.removeItem(at: directory)
                removed += 1
            }
        }
        return removed
    }

    private func captureDirectories() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: inboxURL.path(percentEncoded: false)) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: inboxURL, includingPropertiesForKeys: nil)
            .filter { ULID($0.lastPathComponent) != nil }
    }
}
