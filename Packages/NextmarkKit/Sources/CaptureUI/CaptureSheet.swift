import SwiftUI
import Model
import Capture
import DesignSystem

/// State for the share sheet. Owned by the extension's view controller.
@MainActor
@Observable
public final class CaptureDraft {
    public var content: SharedContent?
    public var intent: Intent?
    public var note = ""
    public var isLoading = true

    public init() {}

    public var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The capture UI shared by the iOS and macOS share extensions (PRD C1, C3).
/// Buttons live in the view rather than a toolbar so the layout is identical in
/// an iOS share sheet and a macOS share popover.
public struct CaptureSheet: View {
    @Bindable private var draft: CaptureDraft
    private let onSave: () -> Void
    private let onCancel: () -> Void

    public init(draft: CaptureDraft, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section { preview }
                Section("Why are you saving this?") {
                    IntentPicker(selection: $draft.intent)
                }
                Section("Note") {
                    TextField("Optional", text: $draft.note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var header: some View {
        HStack {
            Button("Cancel", role: .cancel, action: onCancel)
            Spacer()
            Text("Save to Nextmark").font(.headline)
            Spacer()
            Button("Save", action: onSave)
                .bold()
                .disabled(draft.isLoading || (draft.content?.isEmpty ?? true))
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    @ViewBuilder
    private var preview: some View {
        if draft.isLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if let content = draft.content, !content.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(content.title ?? content.url?.host() ?? String(localized: "Untitled"))
                    .font(.headline)
                    .lineLimit(2)
                if let quote = content.selection?.exact ?? content.text {
                    Text(quote).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                }
                if let url = content.url {
                    Text(url.absoluteString).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                if !content.files.isEmpty {
                    Label("\(content.files.count) file(s)", systemImage: "paperclip").font(.caption)
                }
            }
        } else {
            Text("Nothing here can be saved yet.").foregroundStyle(.secondary)
        }
    }
}
