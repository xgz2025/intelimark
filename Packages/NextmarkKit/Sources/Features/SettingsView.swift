import SwiftUI
import Intelligence
import Library
import Moments

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

    public init(onChange: @escaping @Sendable () async -> Void = {}, onSyncNow: @escaping @Sendable () async -> Void = {}) {
        self.onChange = onChange
        self.onSyncNow = onSyncNow
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Remind Me About Dates in My Saves", isOn: $momentsEnabled)
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
                Text("Your library syncs through your private iCloud database, end-to-end encrypted. Nextmark has no server. Without original files, titles, notes, text and AI results still sync, using little iCloud space.")
            }
            Section("Apple Intelligence") {
                LabeledContent("On-device model", value: IntelligenceStatus.current.description)
            }
            Section("About") {
                LabeledContent(
                    "Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
