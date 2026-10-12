import BackgroundTasks
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
            isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
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
            handle.task.setTaskCompleted(success: false)
            return
        }
        pendingWork = nil
        let job = Task {
            await work { progress in handle.report(progress) }
        }
        handle.task.expirationHandler = { job.cancel() }
        Task {
            let success = await job.value
            handle.task.setTaskCompleted(success: success)
        }
    }
}

/// The system's task, handed between its queue and the main actor. Its progress
/// object is thread-safe; nothing else is touched concurrently.
private struct TaskHandle: @unchecked Sendable {
    let task: BGTask

    func report(_ progress: RescueProgress) {
        guard let task = task as? BGContinuedProcessingTask else { return }
        task.progress.totalUnitCount = Int64(progress.total)
        task.progress.completedUnitCount = Int64(progress.done)
    }
}
