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
import Library

/// Items moved to the Trash: restore them, delete them for good, or empty it all.
/// Items left here are deleted after 30 days, on every device.
struct TrashView: View {
    let services: LibraryServices
    @State private var items: [ItemRecord] = []
    @State private var confirmsEmpty = false
    @State private var pendingDeletion: ItemRecord?

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: ItemLink(id: item.id)) {
                    ItemRow(item: item)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash.slash", role: .destructive) { pendingDeletion = item }
                }
                .swipeActions(edge: .leading) {
                    Button("Restore", systemImage: "arrow.uturn.backward") { restore(item) }
                        .tint(.green)
                }
                .contextMenu {
                    Button("Restore", systemImage: "arrow.uturn.backward") { restore(item) }
                    Button("Delete Permanently…", systemImage: "trash.slash", role: .destructive) { pendingDeletion = item }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Trash Is Empty", systemImage: "trash",
                    description: Text("Items you move to the Trash stay here for 30 days, then they're deleted on all your devices.")
                )
            }
        }
        .navigationTitle("Trash")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty Trash", systemImage: "trash.slash", role: .destructive) { confirmsEmpty = true }
                    .disabled(items.isEmpty)
            }
        }
        .confirmationDialog("Delete \(items.count) items permanently?", isPresented: $confirmsEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) {
                let (repository, directory) = (services.items, services.itemsDirectory)
                Task { try? await repository.emptyTrash(itemsDirectory: directory) }
            }
        } message: {
            Text("They're deleted from all your devices and iCloud, with their files. This can't be undone.")
        }
        .confirmationDialog(
            "Delete permanently?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                let (repository, directory, id) = (services.items, services.itemsDirectory, item.id)
                Task { try? await repository.deletePermanently([id], itemsDirectory: directory) }
            }
        } message: { item in
            Text("“\(item.displayTitle)” is deleted from all your devices and iCloud. This can't be undone.")
        }
        .task {
            for await snapshot in services.items.trashedItems().ignoringErrors() {
                items = snapshot
            }
        }
    }

    private func restore(_ item: ItemRecord) {
        let (repository, id) = (services.items, item.id)
        Task { try? await repository.restore([id]) }
    }
}
