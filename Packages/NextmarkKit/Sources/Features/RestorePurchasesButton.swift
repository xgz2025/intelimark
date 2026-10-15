//
//  Copyright © 2026 Gaoliang Luo. All rights reserved.
//
//  This software and associated documentation are proprietary
//  and confidential. Unauthorized copying, modification,
//  distribution, or use of this software is strictly prohibited.
//
//  Created by Gaoliang Luo.
//

import SwiftUI
import Store

/// "Restore Purchases", saying what it found. Dismissing the App Store sign-in
/// says nothing.
struct RestorePurchasesButton: View {
    @Environment(ProAccess.self) private var pro: ProAccess?
    @State private var isRestoring = false
    @State private var outcome: Outcome?

    private enum Outcome {
        case restored, nothingToRestore, failed
    }

    var body: some View {
        Button("Restore Purchases") {
            guard let pro else { return }
            isRestoring = true
            Task {
                defer { isRestoring = false }
                do {
                    switch try await pro.restore() {
                    case .restored: outcome = .restored
                    case .nothingToRestore: outcome = .nothingToRestore
                    case .cancelled: break
                    }
                } catch {
                    outcome = .failed
                }
            }
        }
        .disabled(isRestoring)
        .alert(
            title,
            isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            message
        }
    }

    private var title: LocalizedStringKey {
        switch outcome {
        case .restored: "Laterwise Pro Restored"
        case .nothingToRestore: "No Purchases Found"
        case .failed, nil: "Couldn't Restore Purchases"
        }
    }

    private var message: Text {
        switch outcome {
        case .restored: Text("Thanks for supporting Laterwise. Everything in Pro is unlocked.")
        case .nothingToRestore: Text("This Apple Account hasn't bought Laterwise Pro. If you bought it with another account, sign in to the App Store with that one.")
        case .failed, nil: Text("Check your connection and that you're signed in to the App Store, then try again.")
        }
    }
}
