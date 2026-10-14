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
import UniformTypeIdentifiers
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
    /// Why the last attempt to save failed; Save stays available to try again.
    public var error: String?
    /// Shown above the details, e.g. a screenshot about to be saved.
    public var thumbnail: Image?

    public init() {}

    public var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The capture UI shared by the iOS and macOS share extensions (PRD C1, C3) and
/// the Mac quick capture panel (C5). Buttons live in the view rather than a toolbar
/// so the layout is identical in an iOS share sheet and a macOS popover or panel.
/// `accessory` appears above the preview (the quick capture panel's source picker).
public struct CaptureSheet<Accessory: View>: View {
    @Bindable private var draft: CaptureDraft
    private let onSave: () -> Void
    private let onCancel: () -> Void
    private let accessory: Accessory

    public init(
        draft: CaptureDraft,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onCancel = onCancel
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                if Accessory.self != EmptyView.self {
                    Section { accessory }
                }
                if let error = draft.error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
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
            Text("Save to Laterwise").font(.headline)
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
                if let thumbnail = draft.thumbnail {
                    thumbnail
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .clipShape(.rect(cornerRadius: 6))
                        .accessibilityHidden(true)
                }
                Text(content.title ?? content.url?.host() ?? Self.placeholderTitle(for: content))
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

extension CaptureSheet {
    /// What to show for content without a title: what kind of file it is.
    static func placeholderTitle(for content: SharedContent) -> String {
        guard let file = content.files.first else { return String(localized: "Untitled") }
        let type = UTType(file.contentType)
        if type?.conforms(to: .image) == true { return String(localized: "Photo") }
        if type?.conforms(to: .pdf) == true { return String(localized: "PDF Document") }
        return String(localized: "File")
    }
}

extension CaptureSheet where Accessory == EmptyView {
    public init(draft: CaptureDraft, onSave: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.init(draft: draft, onSave: onSave, onCancel: onCancel, accessory: { EmptyView() })
    }
}
