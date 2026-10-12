//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

#if canImport(Darwin)
import Darwin
import Foundation

/// Says across processes that a capture was committed (Docs/architecture.md §3.1). The
/// name starts with the App Group, which sandboxed apps require for Darwin notifications.
public enum InboxSignal {
    static let name = "group.com.nextmark.app.inbox-changed" as CFString

    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true
        )
    }
}

/// Calls `onChange` when a capture surface commits an envelope, so a running app
/// ingests immediately: on the Inbox directory's own changes, and on `InboxSignal`
/// from the extensions (which commit inside a subdirectory).
public final class InboxWatcher: @unchecked Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.nextmark.inbox-watcher")
    private var source: DispatchSourceFileSystemObject?   // guarded by `queue`

    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(InboxSignal.name), nil
        )
        source?.cancel()
    }

    public func start() {
        queue.sync {
            guard source == nil else { return }
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
            guard descriptor >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: .write, queue: queue
            )
            let onChange = onChange
            source.setEventHandler { onChange() }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.source = source
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<InboxWatcher>.fromOpaque(observer).takeUnretainedValue().signalled()
            },
            InboxSignal.name, nil, .deliverImmediately
        )
    }

    public func stop() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(InboxSignal.name), nil
        )
        queue.sync {
            source?.cancel()
            source = nil
        }
    }

    private func signalled() {
        let onChange = onChange
        queue.async { onChange() }
    }
}
#endif
