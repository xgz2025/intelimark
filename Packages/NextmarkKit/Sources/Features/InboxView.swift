import SwiftUI
import Library

struct InboxView: View {
    let services: LibraryServices
    @State private var items: [ItemRecord] = []
    @State private var errorMessage: String?

    var body: some View {
        List(items) { item in
            ItemLinkRow(item: item, services: services)
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
                for try await snapshot in services.items.items() {
                    items = snapshot
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
