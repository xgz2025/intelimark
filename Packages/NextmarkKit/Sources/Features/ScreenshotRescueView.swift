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
import Model
import Library
import Integrations
import DesignSystem

/// Screenshot Rescue (PRD C9): screenshots sorted into receipts, tickets, recipes,
/// quotes… as they are understood, with one step to clear them out of Photos.
struct ScreenshotRescueView: View {
    let services: LibraryServices
    let controller: RescueController
    @State private var items: [ItemRecord] = []
    @State private var confirmsCleanUp = false
    @State private var cleanUpError: String?

    /// The kinds screenshots tend to be, in the order people look for them.
    static let order: [SemanticKind] = [
        .receipt, .ticket, .event, .recipe, .quote, .product, .place, .article, .document, .video, .person, .other,
    ]

    var body: some View {
        List {
            status
            ForEach(Self.order, id: \.self) { kind in
                let members = items.filter { $0.semanticKind == kind }
                if !members.isEmpty {
                    Section {
                        ScreenshotGrid(items: members, services: services)
                    } header: {
                        Label { Text(kind.pluralTitle) } icon: { Image(systemName: kind.symbolName) }
                            .badge(members.count)
                    }
                }
            }
            let unsorted = items.filter { $0.semanticKind == nil }
            if !unsorted.isEmpty {
                Section {
                    ScreenshotGrid(items: unsorted, services: services)
                } header: {
                    Label("Still Sorting", systemImage: "hourglass")
                        .badge(unsorted.count)
                }
            }
        }
        .navigationTitle("Screenshots")
        .toolbar {
            if controller.inPhotosCount > 0, !controller.isImporting {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clean Up Photos", systemImage: "trash") { confirmsCleanUp = true }
                }
            }
        }
        .confirmationDialog(
            "Delete \(controller.inPhotosCount) screenshots from Photos?",
            isPresented: $confirmsCleanUp,
            titleVisibility: .visible
        ) {
            Button("Delete from Photos", role: .destructive) {
                Task {
                    do {
                        try await controller.cleanUpPhotos()
                    } catch {
                        cleanUpError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("They stay in Nextmark, searchable by their text. Photos keeps deleted items in Recently Deleted for 30 days.")
        }
        .alert("Couldn't Delete from Photos", isPresented: Binding(
            get: { cleanUpError != nil },
            set: { if !$0 { cleanUpError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cleanUpError ?? "")
        }
        .task {
            await controller.refresh()
            for await snapshot in services.items.screenshots().ignoringErrors() {
                items = snapshot
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch controller.access {
        case .notDetermined:
            Section {
                RescuePitch(count: nil)
                Button("Allow Access to Photos") {
                    Task {
                        await controller.requestAccess()
                        controller.start()
                    }
                }
            }
        case .denied:
            Section {
                Label("Nextmark can't see your photos. Allow access in Settings › Privacy › Photos.", systemImage: "lock")
                    .foregroundStyle(.secondary)
            }
        case .granted:
            switch controller.phase {
            case .importing(let progress):
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        if progress.total == 0 {
                            Text("Looking for screenshots…")
                        } else {
                            Text("Importing \(progress.done) of \(progress.total)")
                        }
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("They're sorted as they come in. You can leave the app; the import keeps going.")
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                    Button("Try Again") { controller.start() }
                }
            case .idle, .finished:
                if items.isEmpty {
                    Section {
                        RescuePitch(count: controller.screenshotCount)
                        Button("Sort My Screenshots") { controller.start() }
                            .disabled(controller.screenshotCount == 0)
                    }
                }
            }
        }
    }
}

/// "You have 2,341 screenshots. Let's sort them."
struct RescuePitch: View {
    let count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let count, count > 0 {
                Text("You have \(count) screenshots. Let's sort them.")
                    .font(.headline)
            } else {
                Text("Let's sort your screenshots.")
                    .font(.headline)
            }
            Text("Nextmark reads the text in each one and sorts out the receipts, tickets, recipes and quotes. Everything stays on your devices.")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ScreenshotGrid: View {
    let items: [ItemRecord]
    let services: LibraryServices

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
            ForEach(items) { item in
                NavigationLink(value: ItemLink(id: item.id)) {
                    ItemThumbnail(url: item.thumbnailURL(in: services.itemsDirectory), symbolName: "camera.viewfinder")
                        .id(item.updatedAt)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(item.displayTitle))
                .contextMenu {
                    Button("Move to Trash", systemImage: "trash", role: .destructive) {
                        let (repository, id) = (services.items, item.id)
                        Task { try? await repository.setStatus(.trashed, forItem: id) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
