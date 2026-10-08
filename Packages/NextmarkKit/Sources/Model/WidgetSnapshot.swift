import Foundation

/// A small JSON snapshot the app writes for widgets, so widgets never open the database.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Action: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var groupTitle: String?
        public var dueDate: Date?

        public init(id: String, title: String, groupTitle: String? = nil, dueDate: Date? = nil) {
            self.id = id
            self.title = title
            self.groupTitle = groupTitle
            self.dueDate = dueDate
        }
    }

    public var generatedAt: Date
    public var actions: [Action]

    public init(generatedAt: Date, actions: [Action]) {
        self.generatedAt = generatedAt
        self.actions = actions
    }

    public static let placeholder = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        actions: [
            Action(id: "1", title: "Book the ryokan", groupTitle: "Kyoto trip"),
            Action(id: "2", title: "Compare the two standing desks", groupTitle: "Home office"),
        ]
    )

    public static func load(from url: URL = AppGroup.widgetSnapshotURL) -> WidgetSnapshot? {
        try? JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL = AppGroup.widgetSnapshotURL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
