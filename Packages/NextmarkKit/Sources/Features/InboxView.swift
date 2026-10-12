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
                for try await snapshot in services.items.inboxItems() {
                    items = snapshot
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
