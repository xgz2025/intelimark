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
import Integrations

/// First launch: what Nextmark does, then (on iPhone and iPad) Screenshot Rescue,
/// so the library isn't empty on day one (Docs/product_strategy.md §4).
public struct OnboardingView: View {
    public static let completedKey = "onboarding.completed"

    let rescue: RescueController?
    let onFinish: (_ startedRescue: Bool) -> Void
    @State private var showsRescue = false

    public init(rescue: RescueController?, onFinish: @escaping (_ startedRescue: Bool) -> Void) {
        self.rescue = rescue
        self.onFinish = onFinish
    }

    public var body: some View {
        // Scrolls at large text sizes, so Continue is always reachable.
        ScrollView {
            VStack(spacing: 24) {
                if showsRescue, let rescue {
                    rescuePage(rescue)
                } else {
                    welcomePage
                }
            }
            .padding(32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .animation(.default, value: showsRescue)
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Save with purpose")
                .font(.largeTitle.bold())
            Feature(symbol: "square.and.arrow.up", title: "Save from anywhere") {
                #if os(macOS)
                Text("Press ⌥⌘S in any app, choose Services › Save to Nextmark, or use Share. Say why: to read, buy, try or go.")
                #else
                Text("Tap Share in any app and choose Nextmark. Say why: to read, buy, try or go.")
                #endif
            }
            Feature(symbol: "sparkles", title: "Nextmark does the sorting") {
                Text("It reads what you saved, finds dates and places, and groups related saves, on your device.")
            }
            Feature(symbol: "bell.badge", title: "Back when it matters") {
                Text("The evening before the concert, the day before a sale ends, five days before your trip, and in a weekly review.")
            }
            Spacer(minLength: 0)
            Button {
                if rescue == nil { onFinish(false) } else { showsRescue = true }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func rescuePage(_ rescue: RescueController) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            RescuePitch(count: rescue.access == .granted ? rescue.screenshotCount : nil)
            Text("Keep what matters and clear the rest out of Photos. Nothing leaves your devices except through your own iCloud.")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                Task {
                    if rescue.access == .notDetermined { await rescue.requestAccess() }
                    rescue.start()
                    onFinish(rescue.access == .granted)
                }
            } label: {
                Text("Sort My Screenshots").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Not Now") { onFinish(false) }
                .frame(maxWidth: .infinity)
        }
        .task { await rescue.refresh() }
    }
}

private struct Feature<Detail: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                detail.foregroundStyle(.secondary)
            }
        }
    }
}
