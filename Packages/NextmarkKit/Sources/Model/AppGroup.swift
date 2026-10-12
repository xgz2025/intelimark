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

/// Locations shared by the app and its extensions.
///
/// Tests must not touch these: on macOS, reading another app group's container
/// can trigger a privacy prompt. Inject explicit URLs instead.
public enum AppGroup {
    public static let identifier = "group.com.nextmark.app"

    public static var containerURL: URL {
        #if canImport(Darwin)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        #endif
        // Unsigned builds have no group container; keep working from Application Support.
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Nextmark", directoryHint: .isDirectory)
    }

    /// Capture envelopes waiting to be ingested.
    public static var inboxURL: URL { containerURL.appending(path: "Inbox", directoryHint: .isDirectory) }
    /// Original files and thumbnails, one directory per item.
    public static var itemsURL: URL { containerURL.appending(path: "Items", directoryHint: .isDirectory) }
    public static var databaseURL: URL { containerURL.appending(path: "Database/library.sqlite") }
    public static var widgetSnapshotURL: URL { containerURL.appending(path: "widget-snapshot.json") }
}

/// A stable per-installation identifier, shared by the app and its extensions.
public enum DeviceIdentity {
    static let key = "deviceIdentifier"

    public static func current(defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.identifier)) -> String {
        let defaults = defaults ?? .standard
        if let existing = defaults.string(forKey: key) { return existing }
        let identifier = UUID().uuidString
        defaults.set(identifier, forKey: key)
        return identifier
    }
}
