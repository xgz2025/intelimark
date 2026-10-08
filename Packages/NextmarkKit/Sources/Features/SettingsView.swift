import SwiftUI
import Intelligence

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        Form {
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
    }
}
