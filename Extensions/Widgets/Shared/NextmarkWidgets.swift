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
import WidgetKit
import Model

/// Next Actions widget (PRD A4). Reads the JSON snapshot the app writes to the
/// App Group; widgets never open the database.
struct NextActionsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct NextActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextActionsEntry {
        NextActionsEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextActionsEntry) -> Void) {
        completion(entry(isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextActionsEntry>) -> Void) {
        // The app calls WidgetCenter.reloadAllTimelines() when actions change; this is a fallback.
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry(isPreview: false)], policy: .after(refresh)))
    }

    private func entry(isPreview: Bool) -> NextActionsEntry {
        let snapshot: WidgetSnapshot = isPreview
            ? .placeholder
            : WidgetSnapshot.load() ?? WidgetSnapshot(generatedAt: .now, actions: [])
        return NextActionsEntry(date: .now, snapshot: snapshot)
    }
}

struct NextActionsView: View {
    let entry: NextActionsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Next", systemImage: "checklist")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if entry.snapshot.actions.isEmpty {
                Text("Nothing due.")
                    .font(.callout)
            } else {
                ForEach(Array(entry.snapshot.actions.prefix(4))) { action in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(action.title).font(.callout).lineLimit(1)
                        if let group = action.groupTitle {
                            Text(group).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NextActionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextActions", provider: NextActionsProvider()) { entry in
            NextActionsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next Actions")
        .description("Your next steps from saved items and plans.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct NextmarkWidgets: WidgetBundle {
    var body: some Widget {
        NextActionsWidget()
    }
}
