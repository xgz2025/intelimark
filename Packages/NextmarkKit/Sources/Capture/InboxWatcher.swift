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

/// Watches the Inbox directory and calls `onChange` when a capture surface adds
/// an envelope, so a running app ingests immediately. Works across processes
/// (share extension, Safari extension, Services) without Darwin notifications.
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
    }

    public func stop() {
        queue.sync {
            source?.cancel()
            source = nil
        }
    }
}
#endif
