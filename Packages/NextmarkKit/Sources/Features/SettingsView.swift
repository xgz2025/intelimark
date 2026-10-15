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
import Intelligence
import Library
import Moments
import Store
import StoreKit

public struct SettingsView: View {
    /// Called when a setting that affects scheduling or sync changes.
    private let onChange: @Sendable () async -> Void
    private let onSyncNow: @Sendable () async -> Void

    @AppStorage(MomentSettings.Key.enabled) private var momentsEnabled = true
    @AppStorage(MomentSettings.Key.maxPerDay) private var maxPerDay = 3
    @AppStorage(MomentSettings.Key.quietStart) private var quietStart = 22
    @AppStorage(MomentSettings.Key.quietEnd) private var quietEnd = 8
    @AppStorage(MomentSettings.Key.reviewEnabled) private var reviewEnabled = true
    @AppStorage(MomentSettings.Key.reviewWeekday) private var reviewWeekday = 1
    @AppStorage(MomentSettings.Key.reviewHour) private var reviewHour = 18
    @AppStorage(SyncSettings.Key.enabled) private var syncEnabled = true
    @AppStorage(SyncSettings.Key.originals) private var syncOriginals = true
    @AppStorage(SyncSettings.Key.lastSyncedAt) private var lastSyncedAt: Double = 0
    @AppStorage(SyncSettings.Key.status) private var syncStatus = ""
    @State private var isSyncing = false
    @State private var showsPaywall = false
    @State private var showsAcknowledgements = false
    @State private var showsManageSubscriptions = false
    @Environment(ProAccess.self) private var pro: ProAccess?
    @Environment(\.openURL) private var openURL

    public init(onChange: @escaping @Sendable () async -> Void = {}, onSyncNow: @escaping @Sendable () async -> Void = {}) {
        self.onChange = onChange
        self.onSyncNow = onSyncNow
    }

    public var body: some View {
        Form {
            Section {
                if pro?.isPro == true {
                    LabeledContent("Laterwise Pro") {
                        if pro?.hasLifetime == true { Text("Lifetime") } else { Text("Active") }
                    }
                    if pro?.hasSubscription == true {
                        Button("Manage Subscription") { showsManageSubscriptions = true }
                    }
                } else {
                    Button("Upgrade to Pro", systemImage: "sparkles") { showsPaywall = true }
                    RestorePurchasesButton()
                }
            } header: {
                Text("Laterwise Pro")
            } footer: {
                if pro?.isPro != true {
                    Text("Pro adds Moments, Briefs and unlimited smart groups. Saving, search, sync and the Weekly Review are always free.")
                } else if pro?.hasLifetime == true, pro?.hasSubscription == true {
                    Text("You own Pro for life, so you can cancel your subscription in Manage Subscription.")
                }
            }
            Section {
                if pro?.isPro != true {
                    ProUpsellRow(text: "Date reminders come with Pro", reason: "Moments bring saves back when they matter.")
                }
                NotificationAccessRow(isNeeded: momentsEnabled || reviewEnabled)
                Toggle("Remind Me About Dates in My Saves", isOn: $momentsEnabled)
                    .disabled(pro?.isPro != true)
                if momentsEnabled {
                    Stepper("At most \(maxPerDay) a day", value: $maxPerDay, in: 1...6)
                    Picker("Quiet from", selection: $quietStart) { hourOptions }
                    Picker("Quiet until", selection: $quietEnd) { hourOptions }
                }
            } header: {
                Text("Moments")
            } footer: {
                Text("Events, deadlines, sale ends, plan dates and due actions come back as notifications. Types you keep dismissing are paused for a month.")
            }
            Section("Weekly Review") {
                Toggle("Remind Me to Review", isOn: $reviewEnabled)
                if reviewEnabled {
                    Picker("Day", selection: $reviewWeekday) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                        }
                    }
                    Picker("Time", selection: $reviewHour) { hourOptions }
                }
            }
            Section {
                Toggle("Sync with iCloud", isOn: $syncEnabled)
                if syncEnabled {
                    Toggle("Sync Original Files", isOn: $syncOriginals)
                    if !syncStatus.isEmpty {
                        Label(syncStatus, systemImage: "exclamationmark.icloud")
                            .foregroundStyle(.secondary)
                    } else if lastSyncedAt > 0 {
                        LabeledContent("Last Synced") {
                            Text(Date(timeIntervalSinceReferenceDate: lastSyncedAt), format: .relative(presentation: .named))
                        }
                    }
                    Button("Sync Now", systemImage: "arrow.triangle.2.circlepath.icloud") {
                        let onSyncNow = onSyncNow
                        isSyncing = true
                        Task {
                            await onSyncNow()
                            isSyncing = false
                        }
                    }
                    .disabled(isSyncing)
                }
            } header: {
                Text("iCloud")
            } footer: {
                Text("Your library syncs through your private iCloud database; Laterwise has no server. The text of each save is end-to-end encrypted, and files are too with Advanced Data Protection. Without original files, titles, notes, text and previews still sync, using little iCloud space.")
            }
            Section {
                let status = IntelligenceStatus.current
                LabeledContent("Apple Intelligence") {
                    Label {
                        Text(status.description)
                    } icon: {
                        Image(systemName: status.isAvailable ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(status.isAvailable ? Color.green : Color.secondary)
                    }
                }
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text(IntelligenceStatus.current.explanation)
            }
            Section("About") {
                LabeledContent("Version", value: NextmarkLinks.versionDescription)
                if let review = NextmarkLinks.writeReview {
                    Link(destination: review) {
                        Label("Rate Laterwise on the App Store", systemImage: "star")
                    }
                }
                Link(destination: NextmarkLinks.feedbackMail) {
                    Label("Send Feedback", systemImage: "envelope")
                }
                ShareLink(item: NextmarkLinks.appStore ?? NextmarkLinks.website) {
                    Label("Share Laterwise", systemImage: "square.and.arrow.up")
                }
                Link("Support", destination: NextmarkLinks.support)
                Link("Privacy Policy", destination: NextmarkLinks.privacy)
                Button("Acknowledgements") { showsAcknowledgements = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $showsPaywall) {
            ProPaywallView()
        }
        .sheet(isPresented: $showsAcknowledgements) {
            AcknowledgementsView()
        }
        #if os(iOS)
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        #else
        .onChange(of: showsManageSubscriptions) {
            if showsManageSubscriptions {
                showsManageSubscriptions = false
                openURL(URL(string: "https://apps.apple.com/account/subscriptions")!)
            }
        }
        #endif
        .onChange(of: settingsFingerprint) {
            let onChange = onChange
            Task { await onChange() }
        }
    }

    private var hourOptions: some View {
        ForEach(0..<24, id: \.self) { hour in
            Text(Self.label(forHour: hour)).tag(hour)
        }
    }

    /// Changes whenever a scheduling setting does.
    private var settingsFingerprint: [Int] {
        [momentsEnabled ? 1 : 0, maxPerDay, quietStart, quietEnd, reviewEnabled ? 1 : 0, reviewWeekday, reviewHour,
         syncEnabled ? 1 : 0, syncOriginals ? 1 : 0]
    }

    static func label(forHour hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
