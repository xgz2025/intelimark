import Foundation

/// A time-sortable 128-bit identifier: 48-bit millisecond timestamp plus 80 random
/// bits, encoded as 26 Crockford base32 characters. Sorting the string sorts by time,
/// which keeps Inbox directories and database rows in capture order.
public struct ULID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: String

    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let decoding: [Character: UInt64] = Dictionary(
        uniqueKeysWithValues: alphabet.enumerated().map { ($1, UInt64($0)) }
    )

    public init(date: Date = Date()) {
        var generator = SystemRandomNumberGenerator()
        self.init(date: date, using: &generator)
    }

    public init<G: RandomNumberGenerator>(date: Date, using generator: inout G) {
        var time = UInt64(max(0, date.timeIntervalSince1970 * 1000)) & 0xFFFF_FFFF_FFFF
        var characters = [Character](repeating: "0", count: 26)
        for index in stride(from: 9, through: 0, by: -1) {
            characters[index] = Self.alphabet[Int(time & 31)]
            time >>= 5
        }
        for index in 10..<26 {
            characters[index] = Self.alphabet[Int(generator.next() & 31)]
        }
        rawValue = String(characters)
    }

    public init?(_ string: String) {
        let upper = string.uppercased()
        guard upper.count == 26, upper.allSatisfy({ Self.decoding[$0] != nil }) else { return nil }
        rawValue = upper
    }

    /// The capture time encoded in the first 10 characters.
    public var date: Date {
        var millis: UInt64 = 0
        for character in rawValue.prefix(10) {
            millis = (millis << 5) | (Self.decoding[character] ?? 0)
        }
        return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    public var description: String { rawValue }

    public static func < (lhs: ULID, rhs: ULID) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension ULID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = ULID(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ULID \(string)")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
