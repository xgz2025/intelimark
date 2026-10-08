import SwiftUI
import Library

struct InboxView: View {
    let repository: ItemRepository
    @State private var items: [ItemRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        List(items) { item in
            ItemRow(item: item)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing saved yet", systemImage: "tray",
                    description: Text("Tap Share in any app and choose Nextmark.")
                )
            }
        }
        .navigationTitle("Inbox")
        .task {
            do {
                for try await snapshot in repository.items() {
                    items = snapshot
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct SearchView: View {
    let repository: ItemRepository
    @State private var query = ""
    @State private var results: [ItemRecord] = []

    var body: some View {
        List(results) { item in
            ItemRow(item: item)
        }
        .searchable(text: $query, prompt: "Titles, notes, highlights…")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(200))   // debounce typing
            guard !Task.isCancelled else { return }
            results = (try? await repository.search(query)) ?? []
        }
        .navigationTitle("Search")
    }
}
