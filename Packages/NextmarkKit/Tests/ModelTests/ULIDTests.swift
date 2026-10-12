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
@testable import Model

struct ULIDTests {
    @Test func encodesTimestampInFirstTenCharacters() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.123)
        let id = ULID(date: date)
        #expect(id.rawValue.count == 26)
        #expect(abs(id.date.timeIntervalSince(date)) < 0.01)
    }

    @Test func sortsByTime() {
        let earlier = ULID(date: Date(timeIntervalSince1970: 1_000))
        let later = ULID(date: Date(timeIntervalSince1970: 2_000))
        #expect(earlier < later)
    }

    @Test func rejectsInvalidStrings() {
        #expect(ULID("too-short") == nil)
        #expect(ULID(String(repeating: "U", count: 26)) == nil)   // U is not in Crockford base32
    }

    @Test func roundTripsThroughJSON() throws {
        let id = ULID()
        let data = try JSONEncoder().encode([id])
        #expect(try JSONDecoder().decode([ULID].self, from: data) == [id])
    }

    @Test func envelopeRoundTripsThroughJSON() throws {
        let envelope = CaptureEnvelope(
            id: ULID(),
            device: "test-device",
            surface: .shareSheet,
            url: URL(string: "https://example.com/a"),
            selection: TextQuote(exact: "hello", prefix: "say", suffix: "world"),
            payloadFiles: [PayloadFile(fileName: "0-photo.jpg", contentType: "public.jpeg", byteSize: 42)],
            userIntent: .tryIt
        )
        let decoded = try JSONDecoder().decode(CaptureEnvelope.self, from: JSONEncoder().encode(envelope))
        #expect(decoded == envelope)
    }
}
