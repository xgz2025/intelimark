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
import PhotosUI
import UniformTypeIdentifiers
import Model
import Capture
import DesignSystem

/// Saving from inside the app (PRD C8): a note or a link, photos, or files. Each
/// becomes a capture like one from the Share menu, so it's processed the same way.
struct AddMenu: View {
    let services: LibraryServices
    @State private var showsNote = false
    @State private var showsPhotos = false
    @State private var importsFiles = false
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        Menu {
            Button("New Note or Link…", systemImage: "square.and.pencil") { showsNote = true }
            Button("Photos…", systemImage: "photo.on.rectangle") { showsPhotos = true }
            Button("Files…", systemImage: "doc") { importsFiles = true }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .help(Text("Add a note, a link, photos or files"))
        .sheet(isPresented: $showsNote) {
            NewNoteSheet(services: services)
        }
        .photosPicker(isPresented: $showsPhotos, selection: $photoItems, maxSelectionCount: 20, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            let (store, refresh) = (services.captureStore, services.refresh)
            performEdit {
                for item in items {
                    try await Self.savePhoto(item, store: store)
                }
                await refresh()
            }
        }
        .fileImporter(isPresented: $importsFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            let (store, refresh) = (services.captureStore, services.refresh)
            performEdit {
                try await Self.saveFiles(urls, store: store)
                await refresh()
            }
        }
    }

    /// One item per photo, as if each had been shared.
    static func savePhoto(_ item: PhotosPickerItem, store: EnvelopeStore) async throws {
        guard let data = try await item.loadTransferable(type: Data.self) else { return }
        let type = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
        let id = ULID()
        let file = try store.addPayload(
            data, fileName: "0-photo.\(type.preferredFilenameExtension ?? "jpg")", contentType: type, for: id
        )
        try CaptureWriter.commit(SharedContent(files: [file]), id: id, surface: .inApp, store: store)
    }

    /// One item per file. Copied off the main actor: a large file takes a while.
    static func saveFiles(_ urls: [URL], store: EnvelopeStore) async throws {
        try await Task.detached(priority: .userInitiated) {
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let id = ULID()
                var content = SharedContent()
                content.files = [try store.addPayloadFile(copying: url, for: id, index: 0)]
                content.useFileNameAsTitle()
                try CaptureWriter.commit(content, id: id, surface: .inApp, store: store)
            }
        }.value
    }
}

/// A note or a link typed or pasted in the app.
struct NewNoteSheet: View {
    let services: LibraryServices
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var intent: Intent?
    @State private var error: String?
    @FocusState private var isFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("A link, an idea, anything to come back to", text: $text, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($isFocused)
                } footer: {
                    Text("A link is saved as its page. Anything else is kept as a note.")
                }
                Section("Why are you saving this?") {
                    IntentPicker(selection: $intent)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Note or Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmed.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .onAppear { isFocused = true }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 340)
        #endif
    }

    private func save() {
        var content = SharedContent()
        content.appendText(trimmed)
        content.promoteLinkText()
        do {
            try CaptureWriter.commit(content, surface: .inApp, intent: intent, store: services.captureStore)
        } catch {
            self.error = String(localized: "Couldn't save: \(error.localizedDescription)")
            return
        }
        let refresh = services.refresh
        Task { await refresh() }
        dismiss()
    }
}
