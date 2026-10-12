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
import StoreKit
import Store

/// Nextmark Pro (PRD P4): what it adds, the three ways to get it, and Restore.
/// Capture, search and the library are never behind it.
public struct ProPaywallView: View {
    /// What the person was trying to do, shown first.
    let reason: LocalizedStringKey?
    @Environment(ProAccess.self) private var pro: ProAccess?
    @Environment(\.dismiss) private var dismiss
    @State private var restoreFailed = false

    public init(reason: LocalizedStringKey? = nil) {
        self.reason = reason
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nextmark Pro")
                            .font(.largeTitle.bold())
                        Text(reason ?? "From saved to done.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        ProFeatureRow(symbol: "bell.badge", title: "Moments") {
                            Text("Reminders the evening before an event, the day before a sale ends, before a trip, and on the day an action is due.")
                        }
                        ProFeatureRow(symbol: "doc.text.magnifyingglass", title: "Briefs") {
                            Text("Each group summed up: an overview, key points, open questions and next steps.")
                        }
                        ProFeatureRow(symbol: "square.stack.3d.up", title: "Unlimited smart groups") {
                            Text("Free keeps \(FreeTier.smartGroups). Your own groups are always unlimited.")
                        }
                    }
                    VStack(spacing: 10) {
                        ForEach(ProProduct.all, id: \.self) { id in
                            ProductView(id: id)
                                .productViewStyle(.compact)
                                .padding(12)
                                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                        }
                    }
                    Text("Free always keeps unlimited saving, search, sync and the Weekly Review. Subscriptions renew until cancelled in your Apple Account settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Restore Purchases") {
                            Task {
                                do {
                                    try await pro?.restore()
                                } catch {
                                    restoreFailed = true
                                }
                            }
                        }
                        Spacer()
                        Link("Terms of Use", destination: Self.termsOfUse)
                    }
                    .font(.footnote)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .onInAppPurchaseCompletion { _, result in
                if case .success(.success(let verification)) = result {
                    await pro?.handle(verification)
                }
            }
            .onChange(of: pro?.isPro ?? false) { _, isPro in
                if isPro { dismiss() }
            }
            .alert("Couldn't Restore Purchases", isPresented: $restoreFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check that you're signed in to the App Store with the Apple Account you bought Pro with.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    /// Apple's standard licence agreement.
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

private struct ProFeatureRow<Detail: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    @ViewBuilder let detail: Detail

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                detail.foregroundStyle(.secondary)
            }
        }
    }
}

/// A row that says a feature comes with Pro, and opens the paywall.
struct ProUpsellRow: View {
    let text: LocalizedStringKey
    let reason: LocalizedStringKey
    @State private var showsPaywall = false

    var body: some View {
        Button {
            showsPaywall = true
        } label: {
            Label {
                Text(text)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView(reason: reason)
        }
    }
}
