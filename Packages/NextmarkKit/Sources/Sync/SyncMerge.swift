import Foundation
import Library

/// Merges a row from another device into ours (Docs/architecture.md §4.3). The
/// result depends only on the two inputs, so two devices that merge the same pair
/// agree, and a merge that changes nothing on the server sends nothing back.
enum SyncMerge {
    typealias Fields = [String: SyncValue]

    static let fieldTimes = SyncTable.fieldTimesColumn

    /// `syncFieldTimes`: column (or layer) → when it was last edited on any device.
    static func times(_ fields: Fields) -> [String: String] {
        guard let json = fields[fieldTimes]?.stringValue,
              let times = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        else { return [:] }
        return times
    }

    static func encode(_ times: [String: String]) -> SyncValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(times) else { return .text("{}") }
        return .text(String(decoding: data, as: UTF8.self))
    }

    static func merge(local: Fields, remote: Fields, table: SyncTable) -> Fields {
        let localTimes = times(local)
        let remoteTimes = times(remote)
        var merged = local

        for (column, remoteValue) in remote where column != fieldTimes && !table.localColumns.contains(column) {
            guard let localValue = local[column] else {
                merged[column] = remoteValue
                continue
            }
            if table.userColumns.contains(column) {
                // The later edit wins; a tie (neither edited it) takes the server's.
                let localWins = (localTimes[column] ?? "") > (remoteTimes[column] ?? "")
                merged[column] = localWins ? localValue : remoteValue
            } else if table.latestColumns.contains(column) {
                merged[column] = later(localValue, remoteValue)
            } else if table.isWriteOnce(column) {
                merged[column] = remoteValue == .null ? localValue : remoteValue
            }
        }

        for layer in table.derivedLayers {
            let localVersion = layer.versionColumn.flatMap { local[$0]?.intValue } ?? 0
            let remoteVersion = layer.versionColumn.flatMap { remote[$0]?.intValue } ?? 0
            let localStamp = localTimes[layer.stampKey] ?? ""
            let remoteStamp = remoteTimes[layer.stampKey] ?? ""
            let localWins = localVersion > remoteVersion || (localVersion == remoteVersion && localStamp > remoteStamp)
            for column in layer.columns {
                if localWins {
                    merged[column] = local[column] ?? remote[column]
                } else if let remoteValue = remote[column] {
                    merged[column] = remoteValue
                }
            }
        }

        var mergedTimes = remoteTimes
        for (key, time) in localTimes where time > (mergedTimes[key] ?? "") {
            mergedTimes[key] = time
        }
        merged[fieldTimes] = mergedTimes == remoteTimes ? (remote[fieldTimes] ?? encode(mergedTimes)) : encode(mergedTimes)
        return merged
    }

    /// Whether the merged row says something the server's copy doesn't.
    static func differs(_ merged: Fields, from remote: Fields, columns: [String]) -> Bool {
        for column in columns {
            if column == fieldTimes {
                if times(merged) != times(remote) { return true }
            } else if (merged[column] ?? .null) != (remote[column] ?? .null) {
                return true
            }
        }
        return false
    }

    /// Dates are stored as sortable text; null loses.
    static func later(_ lhs: SyncValue, _ rhs: SyncValue) -> SyncValue {
        switch (lhs, rhs) {
        case (.null, _): rhs
        case (_, .null): lhs
        case (.text(let left), .text(let right)): left > right ? lhs : rhs
        case (.integer(let left), .integer(let right)): left > right ? lhs : rhs
        case (.real(let left), .real(let right)): left > right ? lhs : rhs
        default: rhs
        }
    }
}
