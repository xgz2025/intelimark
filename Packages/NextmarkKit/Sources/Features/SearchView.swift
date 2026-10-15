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
import Search
import DesignSystem

/// Hybrid search with kind, intent and date filters (PRD F1, F2). Filters live in a
/// toolbar menu and show as removable chips above the results.
struct SearchView: View {
    let services: LibraryServices
    @State private var text = ""
    @State private var filters = SearchFilters()
    @State private var results: [ItemRecord] = []
    @State private var hasSearched = false
    /// Bumped when the library changes, so results don't show an item as it was.
    @State private var revision = ""
    @FocusState private var isSearchFocused: Bool

    private struct Request: Equatable {
        var text: String
        var filters: SearchFilters
        var revision: String

        var isBlank: Bool {
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filters.isEmpty
        }
    }

    private var request: Request { Request(text: text, filters: filters, revision: revision) }

    var body: some View {
        List(results) { item in
            ItemLinkRow(item: item, services: services)
        }
        .overlay { emptyState }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !filters.isEmpty {
                FilterChipRow(filters: $filters)
            }
        }
        .searchable(text: $text, prompt: "Words, meanings, text in photos")
        .searchFocused($isSearchFocused)
        .onAppear { isSearchFocused = true }
        .task {
            for await value in services.items.revisions().ignoringErrors() {
                revision = value
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FilterMenu(filters: $filters)
            }
        }
        .task(id: request) { await run(request) }
        .navigationTitle("Search")
    }

    private func run(_ request: Request) async {
        guard !request.isBlank else {
            results = []
            hasSearched = false
            return
        }
        try? await Task.sleep(for: .milliseconds(200))   // debounce typing
        guard !Task.isCancelled else { return }
        let query = request.filters.query(text: request.text, now: Date())
        let found = (try? await services.search.search(query)) ?? []
        guard !Task.isCancelled else { return }
        results = found
        hasSearched = true
    }

    @ViewBuilder
    private var emptyState: some View {
        if request.isBlank {
            ContentUnavailableView(
                "Search Your Saves", systemImage: "magnifyingglass",
                description: Text("Find things by their words or their meaning, including text in photos and screenshots.")
            )
        } else if hasSearched && results.isEmpty {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No Matches", systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Nothing you saved matches these filters.")
                )
            } else {
                ContentUnavailableView.search(text: text)
            }
        }
    }
}

private struct FilterMenu: View {
    @Binding var filters: SearchFilters

    var body: some View {
        Menu {
            Section("Kind") {
                ForEach(KindFilter.allCases) { kind in
                    Toggle(isOn: $filters[kind: kind]) {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
            }
            Section("Intent") {
                ForEach(Intent.allCases) { intent in
                    Toggle(isOn: $filters[intent: intent]) {
                        Label(intent.title, systemImage: intent.symbolName)
                    }
                }
            }
            Picker("Saved", selection: $filters.period) {
                ForEach(SavedPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Clear Filters", systemImage: "xmark.circle") {
                filters = SearchFilters()
            }
            .disabled(filters.isEmpty)
        } label: {
            Label(
                "Filter",
                systemImage: filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
        }
        .keepsMenuOpenOnSelection()
    }
}

private extension View {
    /// On iOS the menu stays open so several filters can be picked in one go.
    /// macOS menus always close on selection.
    @ViewBuilder
    func keepsMenuOpenOnSelection() -> some View {
        #if os(iOS)
        menuActionDismissBehavior(.disabled)
        #else
        self
        #endif
    }
}

private struct FilterChipRow: View {
    @Binding var filters: SearchFilters

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filters.chips) { chip in
                    Button {
                        withAnimation(.snappy) { filters.remove(chip) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: chip.symbolName)
                            Text(chip.title)
                            Image(systemName: "xmark")
                                .imageScale(.small)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityHint(Text("Removes this filter"))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }
}
