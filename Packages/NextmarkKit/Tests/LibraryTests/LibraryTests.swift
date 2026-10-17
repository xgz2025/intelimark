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
import GRDB
import Model
import Capture
@testable import Library

struct LibraryTests {
    let database: LibraryDatabase
    let store: EnvelopeStore
    let ingestor: Ingestor

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LibraryTests-\(UUID().uuidString)")
        database = try LibraryDatabase.inMemory()
        store = EnvelopeStore(inboxURL: root.appending(path: "Inbox"))
        ingestor = Ingestor(store: store, database: database, itemsDirectory: root.appending(path: "Items"))
    }

    @Test func savingAProductPageAgainRefreshesTheSavedProduct() async throws {
        let first = CaptureEnvelope(
            id: ULID(), device: "d", surface: .shareSheet,
            url: URL(string: "https://www.amazon.com/Wool-Coat/dp/B0ABC12345/ref=sr_1_3?tag=x"), title: "Wool Coat"
        )
        try store.commit(first)
        try await ingestor.ingestPending()
        let repository = ItemRepository(database: database)
        // The product as the extract stage would leave it.
        let recorded = try await repository.recordPrice(120, currency: "USD", forItem: first.id.rawValue)
        #expect(recorded == nil)
        try await database.writer.write { db in try db.execute(sql: "DELETE FROM job") }

        let again = CaptureEnvelope(
            id: ULID(), device: "d", surface: .safariExtension,
            url: URL(string: "https://amazon.com/dp/B0ABC12345?psc=1"), title: "Wool Coat"
        )
        try store.commit(again)
        let ingested = try await ingestor.ingestPending()
        #expect(ingested == [first.id.rawValue])
        #expect(try await repository.item(id: again.id.rawValue) == nil)
        #expect(try store.committedCaptures().isEmpty)
        let jobs = try await database.writer.read { db in try JobRecord.filter(Column("itemID") == first.id.rawValue).fetchCount(db) }
        #expect(jobs == 1)

        // A highlight on the same page is a new save.
        let highlight = CaptureEnvelope(
            id: ULID(), device: "d", surface: .safariExtension,
            url: URL(string: "https://amazon.com/dp/B0ABC12345"), title: "Wool Coat", selection: TextQuote(exact: "100% wool")
        )
        try store.commit(highlight)
        #expect(try await ingestor.ingestPending() == [highlight.id.rawValue])
    }

    @Test func ingestsALinkWithAHighlight() async throws {
        let envelope = CaptureEnvelope(
            id: ULID(),
            device: "d",
            surface: .shareSheet,
            url: URL(string: "https://example.com/ramen"),
            title: "Best ramen in Kyoto",
            selection: TextQuote(exact: "open until midnight"),
            userIntent: .go,
            userNote: "for the trip"
        )
        try store.commit(envelope)

        let ingested = try await ingestor.ingestPending()
        #expect(ingested == [envelope.id.rawValue])
        #expect(try store.committedCaptures().isEmpty)

        let item = try #require(try await ItemRepository(database: database).item(id: envelope.id.rawValue))
        #expect(item.kind == .link)
        #expect(item.status == .inbox)
        #expect(item.intent == .go)
        #expect(item.note == "for the trip")
        #expect(item.text == "open until midnight")
        guard case .web(let fragmentURL, _)? = item.anchor else {
            Issue.record("Expected a web anchor")
            return
        }
        #expect(fragmentURL.absoluteString.hasSuffix("#:~:text=open%20until%20midnight"))
        #expect(try await JobQueue(database: database).count() == 1)
    }

    @Test func ingestionIsIdempotent() async throws {
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .services, text: "a quote")
        try store.commit(envelope)
        try await ingestor.ingestPending()
        try store.commit(envelope)          // e.g. the app crashed before removing the envelope
        try await ingestor.ingestPending()
        #expect(try await JobQueue(database: database).count() == 1)
    }

    @Test func movesPayloadFilesIntoTheItemDirectory() async throws {
        let id = ULID()
        let payload = try store.makePayloadDirectory(for: id)
        try Data([0xFF, 0xD8]).write(to: payload.appending(path: "0-photo.jpg"))
        let envelope = CaptureEnvelope(
            id: id, device: "d", surface: .shareSheet,
            payloadFiles: [PayloadFile(fileName: "0-photo.jpg", contentType: "public.jpeg", byteSize: 2)]
        )
        try store.commit(envelope)
        try await ingestor.ingestPending()

        let item = try #require(try await ItemRepository(database: database).item(id: id.rawValue))
        #expect(item.kind == .image)
        let moved = ingestor.itemsDirectory.appending(path: id.rawValue).appending(path: "0-photo.jpg")
        #expect(FileManager.default.fileExists(atPath: moved.path(percentEncoded: false)))
    }

    @Test func fullTextSearchMatchesPrefixes() async throws {
        try store.commit(CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://a.example"), title: "Standing desk review"))
        try store.commit(CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, url: URL(string: "https://b.example"), title: "Kyoto ryokan list"))
        try await ingestor.ingestPending()

        let results = try await ItemRepository(database: database).search("ryok")
        #expect(results.map(\.sourceTitle) == ["Kyoto ryokan list"])
    }

    @Test func understandingNeverTouchesTheUserLayer() async throws {
        let envelope = CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet, text: "notes", userIntent: .read, userNote: "mine")
        try store.commit(envelope)
        try await ingestor.ingestPending()

        let repository = ItemRepository(database: database)
        let understanding = Understanding(
            title: "AI title", summary: "AI summary", semanticKind: .quote,
            likelyIntent: .reference, keywords: ["notes"], producer: "test"
        )
        try await repository.applyUnderstanding(understanding, toItem: envelope.id.rawValue, version: 3)

        let item = try #require(try await repository.item(id: envelope.id.rawValue))
        #expect(item.aiTitle == "AI title")
        #expect(item.keywords == ["notes"])
        #expect(item.derivedVersion == 3)
        #expect(item.intent == .read)
        #expect(item.note == "mine")
        #expect(item.displayTitle == "AI title")
    }

    @Test func filesSharedOnTheirOwnAreTitledByName() async throws {
        let id = ULID()
        let payload = try store.makePayloadDirectory(for: id)
        try Data("%PDF-1.4".utf8).write(to: payload.appending(path: "0-Lease agreement.pdf"))
        let envelope = CaptureEnvelope(
            id: id, device: "d", surface: .shareSheet,
            payloadFiles: [PayloadFile(fileName: "0-Lease agreement.pdf", contentType: "com.adobe.pdf", byteSize: 8)]
        )
        try store.commit(envelope)
        try await ingestor.ingestPending()

        let item = try #require(try await ItemRepository(database: database).item(id: id.rawValue))
        #expect(item.sourceTitle == "Lease agreement")
        #expect(item.displayTitle == "Lease agreement")
    }

    @Test func untitledItemsAreNamedByKind() {
        var item = ItemRecord(envelope: CaptureEnvelope(id: ULID(), device: "d", surface: .shareSheet))
        item.kind = .pdf
        #expect(item.displayTitle == "PDF Document")
        item.kind = .image
        item.imageDescription = "A receipt from a ramen shop"
        #expect(item.displayTitle == "A receipt from a ramen shop")
    }
}
