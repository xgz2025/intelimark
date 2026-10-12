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
import Observation
import Integrations

/// Runs long work so it can finish while the app is in the background. On iOS the
/// app hands it to a continued-processing task with the system's progress UI.
@MainActor
public protocol LongTaskRunner: AnyObject {
    /// Returns false when it can't take the work; the caller then runs it itself.
    func run(
        title: String,
        work: @escaping @Sendable (_ report: @escaping @Sendable (RescueProgress) -> Void) async -> Bool
    ) -> Bool
}

/// Screenshot Rescue's state for the screens (PRD C9).
@MainActor
@Observable
public final class RescueController {
    public enum Phase: Equatable {
        case idle
        case importing(RescueProgress)
        case finished(imported: Int)
        case failed(String)
    }

    public static let completedKey = "rescue.completed"
    /// Set when a rescue starts, so one that was stopped partway resumes.
    public static let startedKey = "rescue.started"

    public private(set) var phase: Phase = .idle
    public private(set) var access: PhotosAccess
    /// Screenshots in Photos, once access is granted.
    public private(set) var screenshotCount = 0
    /// Imported screenshots still in Photos, which Clean Up can delete.
    public private(set) var inPhotosCount = 0
    /// Screenshots in Photos not in the library yet.
    public private(set) var pendingCount = 0
    @ObservationIgnored private var isImportingNew = false

    @ObservationIgnored public let rescue: ScreenshotRescue
    @ObservationIgnored public weak var runner: (any LongTaskRunner)?
    /// Runs enrichment after each batch, so the first screenshots are sorted while the rest load.
    @ObservationIgnored private let onImported: @Sendable () async -> Void

    public init(rescue: ScreenshotRescue, onImported: @escaping @Sendable () async -> Void) {
        self.rescue = rescue
        self.onImported = onImported
        access = rescue.access()
    }

    public var isImporting: Bool {
        if case .importing = phase { true } else { false }
    }

    public func refresh() async {
        access = rescue.access()
        guard access == .granted else { return }
        screenshotCount = await rescue.screenshotCount()
        inPhotosCount = await rescue.inPhotosCount()
        pendingCount = await rescue.pending().count
    }

    public func requestAccess() async {
        access = await rescue.requestAccess()
        await refresh()
    }

    /// Imports every screenshot not yet in the library, in the background if the app can.
    public func start() {
        guard access == .granted, !isImporting else { return }
        UserDefaults.standard.set(true, forKey: Self.startedKey)
        phase = .importing(RescueProgress(done: 0, total: 0))
        let (rescue, onImported) = (rescue, onImported)
        // The controller lives as long as the app, so the work holds it strongly.
        let work: @Sendable (@escaping @Sendable (RescueProgress) -> Void) async -> Bool = { report in
            do {
                let imported = try await rescue.run(onProgress: report) { progress in
                    await self.update(progress)
                    // Not awaited: sorting can take much longer than importing, and an
                    // expiring background task must be able to stop at once.
                    Task { await onImported() }
                }
                await self.finish(imported: imported)
                return true
            } catch {
                await self.fail(error)
                return false
            }
        }
        let title = String(localized: "Sorting your screenshots")
        if runner?.run(title: title, work: work) != true {
            Task { _ = await work { _ in } }
        }
    }

    /// New screenshots since the last import, quietly (PRD C9: "import new screenshots when the app runs").
    public func importNew() async {
        let hasStarted = UserDefaults.standard.bool(forKey: Self.startedKey)
            || UserDefaults.standard.bool(forKey: Self.completedKey)
        guard access == .granted, !isImporting, !isImportingNew, hasStarted else { return }
        // Two passes at once would import the same screenshots twice.
        isImportingNew = true
        defer { isImportingNew = false }
        if let imported = try? await rescue.run(), imported > 0 {
            await onImported()
        }
        await refresh()
    }

    /// Deletes the imported screenshots from Photos; the system asks the user first.
    public func cleanUpPhotos() async throws {
        _ = try await rescue.cleanUpPhotos()
        await refresh()
    }

    private func update(_ progress: RescueProgress) {
        phase = .importing(progress)
    }

    private func finish(imported: Int) async {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        phase = .finished(imported: imported)
        await refresh()
    }

    private func fail(_ error: any Error) {
        phase = error is CancellationError ? .idle : .failed(error.localizedDescription)
    }
}
