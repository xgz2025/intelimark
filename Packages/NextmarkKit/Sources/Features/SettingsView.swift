import SwiftUI
import Intelligence
import Moments

public struct SettingsView: View {
    /// Called when a setting that affects scheduling changes.
    private let onChange: @Sendable () async -> Void

    @AppStorage(MomentSettings.Key.enabled) private var momentsEnabled = true
    @AppStorage(MomentSettings.Key.maxPerDay) private var maxPerDay = 3
    @AppStorage(MomentSettings.Key.quietStart) private var quietStart = 22
    @AppStorage(MomentSettings.Key.quietEnd) private var quietEnd = 8
    @AppStorage(MomentSettings.Key.reviewEnabled) private var reviewEnabled = true
    @AppStorage(MomentSettings.Key.reviewWeekday) private var reviewWeekday = 1
    @AppStorage(MomentSettings.Key.reviewHour) private var reviewHour = 18

    public init(onChange: @escaping @Sendable () async -> Void = {}) {
        self.onChange = onChange
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
        [momentsEnabled ? 1 : 0, maxPerDay, quietStart, quietEnd, reviewEnabled ? 1 : 0, reviewWeekday, reviewHour]
    }

    static func label(forHour hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
