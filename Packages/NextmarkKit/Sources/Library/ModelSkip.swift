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

/// Work the models declined for good (a guardrail, an unsupported language, text that
/// can't be embedded). The requeue queries at launch leave these out until the OS
/// version changes.
public enum ModelSkipStage: String, Sendable {
    case understand, embed, brief
}

extension LibraryDatabase {
    static var osVersion: String { ProcessInfo.processInfo.operatingSystemVersionString }

    public func recordModelSkip(_ stage: ModelSkipStage, subjectID: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO modelSkip (subjectID, stage, osVersion) VALUES (?, ?, ?)",
                arguments: [subjectID, stage.rawValue, Self.osVersion]
            )
        }
    }

    /// The model managed after all (an edit, a new prompt): consider it again later.
    public func clearModelSkip(_ stage: ModelSkipStage, subjectID: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM modelSkip WHERE subjectID = ? AND stage = ?",
                arguments: [subjectID, stage.rawValue]
            )
        }
    }

    /// SQL condition: `column` (an item or group ID) wasn't declined for `stage` on this OS.
    static func notSkipped(_ stage: ModelSkipStage, column: String) -> String {
        "NOT EXISTS (SELECT 1 FROM modelSkip WHERE modelSkip.subjectID = \(column) AND modelSkip.stage = '\(stage.rawValue)' AND modelSkip.osVersion = ?)"
    }
}
