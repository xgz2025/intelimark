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
import Intelligence

/// Nextmark Pro (PRD P4): what it adds, the three ways to get it, and Restore.
/// Capture, search and the library are never behind it.
public struct ProPaywallView: View {
    /// What the person was trying to do, shown first.
    let reason: LocalizedStringKey?
    @Environment(ProAccess.self) private var pro: ProAccess?
    @Environment(\.dismiss) private var dismiss
    @State private var isAwaitingApproval = false
    @State private var purchaseError: String?

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
                    if !IntelligenceStatus.current.isAvailable {
                        // Said before buying, where Apple Intelligence is off or not offered.
                        Label(
                            "Apple Intelligence isn't on for this device, so Nextmark's built-in rules write Briefs. They're improved automatically if it's turned on later.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    Text("Free always keeps unlimited saving, search, sync and the Weekly Review. Subscriptions renew until cancelled in your Apple Account settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        RestorePurchasesButton()
                        Spacer()
                        Link("Privacy Policy", destination: NextmarkLinks.privacy)
                        Link("Terms of Use", destination: NextmarkLinks.termsOfUse)
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
                switch result {
                case .success(.success(let verification)):
                    await pro?.handle(verification)
                case .success(.pending):
                    // Ask to Buy, or the bank confirming: Pro arrives when it's approved.
                    isAwaitingApproval = true
                case .success(.userCancelled):
                    break
                case .failure(let error):
                    purchaseError = error.localizedDescription
                case .success:
                    break
                }
            }
            .alert("Waiting for Approval", isPresented: $isAwaitingApproval) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nextmark Pro unlocks as soon as the purchase is approved.")
            }
            .alert(
                "Couldn't Complete the Purchase",
                isPresented: Binding(get: { purchaseError != nil }, set: { if !$0 { purchaseError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
            .onChange(of: pro?.isPro ?? false) { _, isPro in
                if isPro { dismiss() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

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
