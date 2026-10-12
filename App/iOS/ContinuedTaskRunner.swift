//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import BackgroundTasks
import Foundation
import Features
import Integrations

/// Runs Screenshot Rescue as a continued-processing task, so the import keeps going
/// with the system's progress UI when the user leaves the app (Docs/architecture.md §3.2).
@MainActor
final class ContinuedTaskRunner: LongTaskRunner {
    static let identifier = "com.nextmark.app.rescue"

    private var isRegistered = false
    private var pendingWork: (@Sendable (@escaping @Sendable (RescueProgress) -> Void) async -> Bool)?

    func run(
        title: String,
        work: @escaping @Sendable (@escaping @Sendable (RescueProgress) -> Void) async -> Bool
    ) -> Bool {
        if !isRegistered {
            // The system calls this on its own queue: it must not inherit this class's main-actor isolation.
            isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { @Sendable task in
                let handle = TaskHandle(task: task)
                Task { @MainActor in self.launch(handle) }
            }
        }
        guard isRegistered else { return false }
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.identifier, title: title, subtitle: String(localized: "Starting…")
        )
        request.strategy = .fail
        pendingWork = work
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            pendingWork = nil
            return false
        }
    }

    private func launch(_ handle: TaskHandle) {
        guard let work = pendingWork else {
            handle.complete(success: false)
            return
        }
        pendingWork = nil
        let job = Task {
            await work { progress in handle.report(progress) }
        }
        handle.task.expirationHandler = {
            // The system wants the task finished now, not once the work winds down.
            job.cancel()
            handle.complete(success: false)
        }
        Task {
            let success = await job.value
            handle.complete(success: success)
        }
    }
}

/// The system's task, handed between its queue and the main actor. Its progress
/// object is thread-safe, and completion is guarded so it's reported once.
private final class TaskHandle: @unchecked Sendable {
    let task: BGTask
    private let lock = NSLock()
    private var isCompleted = false

    init(task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        let first = lock.withLock {
            defer { isCompleted = true }
            return !isCompleted
        }
        if first { task.setTaskCompleted(success: success) }
    }

    func report(_ progress: RescueProgress) {
        guard let task = task as? BGContinuedProcessingTask else { return }
        task.progress.totalUnitCount = Int64(progress.total)
        task.progress.completedUnitCount = Int64(progress.done)
    }
}
