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
import SwiftUI

/// The last edit that couldn't be saved (the device's storage is full, say). Shown
/// once, in an alert at the root, instead of a tap that silently does nothing.
@MainActor
@Observable
public final class EditFailure {
    public static let shared = EditFailure()

    public var message: String?

    func report(_ error: any Error) {
        guard !(error is CancellationError) else { return }
        message = error.localizedDescription
    }
}

/// Saves that are committed but couldn't be added to the library yet (its storage is
/// full, say). The app updates it after each pass; the Inbox shows it.
@MainActor
@Observable
public final class CaptureStatus {
    public static let shared = CaptureStatus()

    public var stuckCount = 0
    public var reason: String?
}

/// Runs an edit the person made. Observation redraws the screens when it lands;
/// when it fails, `EditFailure` says so.
@MainActor
func performEdit(_ work: @escaping () async throws -> Void) {
    Task {
        do {
            try await work()
        } catch {
            EditFailure.shared.report(error)
        }
    }
}

extension View {
    /// Shows edits that couldn't be saved. Attach once, at the root.
    func editFailureAlert() -> some View {
        modifier(EditFailureAlert())
    }
}

private struct EditFailureAlert: ViewModifier {
    private var failure: EditFailure { EditFailure.shared }

    func body(content: Content) -> some View {
        content.alert(
            "Couldn't Save the Change",
            isPresented: Binding(get: { failure.message != nil }, set: { if !$0 { failure.message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure.message ?? "")
        }
    }
}
