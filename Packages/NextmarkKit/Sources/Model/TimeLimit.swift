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

/// Thrown by `withTimeLimit` when the work took too long.
public struct TimeLimitExceeded: Error, Equatable {
    public init() {}
}

/// Runs `operation`, but gives up after `seconds`: the caller gets `TimeLimitExceeded`
/// and the work is cancelled. Unlike a task group, this returns on time even when the
/// work ignores cancellation (a model call or image analysis that doesn't check); that
/// work then finishes on its own and its result is dropped. Cancelling the caller
/// cancels the work and throws `CancellationError`.
public func withTimeLimit<T: Sendable>(
    _ seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let outcome = Outcome<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
            // Cancelled before it began: don't start work nobody will wait for.
            guard outcome.start(continuation) else { return }
            let work = Task {
                do {
                    outcome.finish(.success(try await operation()))
                } catch {
                    outcome.finish(.failure(error))
                }
            }
            let timer = Task {
                try? await Task.sleep(for: .seconds(seconds))
                if outcome.finish(.failure(TimeLimitExceeded())) { work.cancel() }
            }
            outcome.onFinish { work.cancel(); timer.cancel() }
        }
    } onCancel: {
        outcome.finish(.failure(CancellationError()))
    }
}

/// Resumes a continuation once, with whichever result comes first.
private final class Outcome<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var early: Result<T, any Error>?
    private var isFinished = false
    private var cleanup: (@Sendable () -> Void)?

    /// Returns false when the outcome is already known (the caller was cancelled), in
    /// which case the continuation has been resumed with it.
    func start(_ continuation: CheckedContinuation<T, any Error>) -> Bool {
        let result: Result<T, any Error>? = lock.withLock {
            if let early { return early }
            self.continuation = continuation
            return nil
        }
        guard let result else { return true }
        continuation.resume(with: result)
        return false
    }

    /// The cleanup runs once the outcome is known (now, if it already is).
    func onFinish(_ cleanup: @escaping @Sendable () -> Void) {
        let runNow = lock.withLock {
            if isFinished { return true }
            self.cleanup = cleanup
            return false
        }
        if runNow { cleanup() }
    }

    /// Returns true when this result was the one delivered.
    @discardableResult
    func finish(_ result: Result<T, any Error>) -> Bool {
        let delivery: (continuation: CheckedContinuation<T, any Error>?, cleanup: (@Sendable () -> Void)?)? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true
            if continuation == nil { early = result }
            let pending = (continuation: continuation, cleanup: cleanup)
            continuation = nil
            cleanup = nil
            return pending
        }
        guard let delivery else { return false }
        delivery.continuation?.resume(with: result)
        delivery.cleanup?()
        return true
    }
}
