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
import QuickLook
import Model
import Library
import Intelligence
import DesignSystem

/// One item: what it is, what it says about itself (and where each fact came
/// from), why it was saved, its groups and its next steps.
struct ItemDetailView: View {
    let itemID: String
    let services: LibraryServices
    @Environment(\.dismiss) private var dismiss
    @State private var item: ItemRecord?
    @State private var context = ItemContext()
    @State private var newAction = ""
    @State private var showsAddToGroup = false
    @State private var showsDonePrompt = false
    @State private var showsFullText = false
    @State private var showsRecognizedText = false
    @State private var showsShare = false
    @State private var showsRename = false
    @State private var showsFieldsEditor = false
    @State private var titleDraft = ""
    @State private var noteDraft = ""
    @FocusState private var isEditingNote: Bool
    /// The saved photo, PDF or file itself, when it's on this device.
    @State private var original: URL?
    @State private var previewedFile: URL?
    /// Laying out a very long text at once stalls the screen; longer text is shown on request.
    static let previewCharacters = 4_000

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                ProgressView()
            }
        }
        .task(id: itemID) {
            // Opening an item keeps it out of the stale pile in the Weekly Review.
            try? await services.items.markOpened(itemID)
            for await value in services.items.observeItem(id: itemID).ignoringErrors() {
                item = value
                // Kept as typed while editing; otherwise follows the item (another device).
                if !isEditingNote { noteDraft = value?.note ?? "" }
                // Deleted for good (Empty Trash, another device): nothing left to show.
                if value == nil { dismiss() }
            }
        }
        .task(id: itemID) {
            original = await originalFile()
        }
        .quickLookPreview($previewedFile)
        .task(id: itemID) {
            for await value in services.groups.context(forItem: itemID).ignoringErrors() {
                context = value
            }
        }
    }

    private func content(_ item: ItemRecord) -> some View {
        let suggestions = ActionSuggester.suggestions(for: item.digest)
            .filter { !context.knownActionTitles.contains($0.title.lowercased()) }
        return List {
            Section {
                header(item)
            }

            if item.needsConfirmation, item.status != .trashed {
                CorrectionBanner(item: item, services: services) { showsFieldsEditor = true }
            }

            if let quote = item.text, !quote.isEmpty {
                Section {
                    longText(quote)
                        .italic(item.anchor != nil)
                } header: {
                    if item.anchor == nil { Text("Text") } else { Text("Highlight") }
                }
            }

            if let trip = item.typedFields?.trip {
                ForEach(Array(trip.legs.enumerated()), id: \.offset) { index, leg in
                    TripLegSection(leg: leg, mode: trip.mode, index: index, count: trip.legs.count, origin: trip.origin)
                }
            }

            Section("Details") {
                ForEach(item.facts) { fact in
                    FactRow(fact: fact, mapsURL: fact.label == .location ? item.photoMapsURL : nil)
                }
            }

            if item.saveType == .show || item.saveType == .travel {
                ItemRemindersSection(item: item, services: services)
            }

            if item.saveType == .product {
                ProductPriceSection(item: item, services: services)
            }

            foundInText(item)

            if item.kind == .image, let recognized = item.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !recognized.isEmpty {
                Section {
                    DisclosureGroup("Text in the Picture", isExpanded: $showsRecognizedText) {
                        longText(recognized)
                            .font(.callout)
                    }
                }
            }

            Section("Why You Saved It") {
                IntentPicker(selection: Binding(
                    get: { item.intent },
                    set: { intent in
                        let (items, id) = (services.items, item.id)
                        // A binding's setter may run off the main actor: report from a main-actor task.
                        Task { @MainActor in
                            do {
                                try await items.setIntent(intent, forItem: id)
                            } catch {
                                EditFailure.shared.report(error)
                            }
                        }
                    }
                ))
                if item.intent == nil, let suggested = item.suggestedIntent {
                    Text("Looks like: \(Text(suggested.title))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Add a note", text: $noteDraft, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($isEditingNote)
                    .onSubmit { saveNote() }
                    .onChange(of: isEditingNote) { _, editing in
                        if !editing { saveNote() }
                    }
            }

            Section {
                ForEach(context.groups) { group in
                    NavigationLink(value: GroupLink(id: group.id)) {
                        GroupLabel(group: group)
                    }
                }
                Button("Add to Group…", systemImage: "plus") { showsAddToGroup = true }
            } header: {
                Text("Groups")
            }

            Section("Actions") {
                ForEach(context.actions) { action in
                    ActionRow(action: action) { toggle(action) }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleteAction(action) }
                        }
                        .contextMenu {
                            Button("Delete Action", systemImage: "trash", role: .destructive) { deleteAction(action) }
                        }
                }
                ForEach(suggestions, id: \.self) { suggestion in
                    SuggestedActionRow(suggestion: suggestion) {
                        let repository = services.actions
                        performEdit { _ = try await repository.accept(suggestion) }
                    } onDismiss: {
                        let repository = services.actions
                        performEdit { try await repository.dismiss(suggestion) }
                    }
                }
                TextField("Add an action", text: $newAction)
                    .onSubmit { addAction() }
                    .submitLabel(.done)
            }
        }
        .navigationTitle(item.displayTitle)
        #if os(iOS)
        // The header shows the title large; the bar only needs it once scrolled away.
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbar(item) }
        // Leaving while still typing keeps the note.
        .onDisappear { saveNote() }
        .sheet(isPresented: $showsAddToGroup) {
            AddToGroupSheet(itemIDs: [item.id], services: services)
        }
        .sheet(isPresented: $showsFieldsEditor) {
            FieldsEditor(item: item, services: services)
        }
        .alert("Rename", isPresented: $showsRename) {
            TextField("Title", text: $titleDraft)
            Button("Save") {
                let (items, id, title) = (services.items, item.id, titleDraft)
                performEdit { try await items.setTitle(title, forItem: id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it empty to use the title Laterwise found.")
        }
        .alert("All Actions Done", isPresented: $showsDonePrompt) {
            Button("Mark Item as Done") { finish(item, as: .done) }
            Button("Keep in Inbox", role: .cancel) {}
        } message: {
            Text("You've finished every action for “\(item.displayTitle)”. Mark the item as done too? It moves from the Inbox to Done.")
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ item: ItemRecord) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            switch item.status {
            case .done:
                Button { setStatus(.active) } label: {
                    Label("Mark as Not Done", systemImage: "arrow.uturn.backward.circle")
                }
                .help(Text("Not done after all: move it back to the Inbox"))
            case .trashed:
                Button { setStatus(.active) } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .help(Text("Take it out of the Trash and back into the Inbox"))
            default:
                Button { finish(item, as: .done) } label: {
                    Label("Mark as Done", systemImage: "checkmark.circle")
                }
                .help(Text("Mark as done: it leaves the Inbox and waits in Done. It stays in its groups and in Search."))
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                titleDraft = item.userTitle ?? item.displayTitle
                showsRename = true
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            .help(Text("Give it your own title"))
        }
        if [.travel, .show, .receipt, .product].contains(item.saveType) {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showsFieldsEditor = true
                } label: {
                    Label("Edit Details…", systemImage: "square.and.pencil")
                }
                .help(Text("Fix the details Laterwise read: times, places, prices"))
            }
        }
        if item.status != .trashed {
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) { finish(item, as: .trashed) } label: {
                    Label("Move to Trash", systemImage: "trash")
                }
                .help(Text("Move to the Trash: it leaves the Inbox and its groups. You can restore it for 30 days."))
            }
        }
    }

    private func header(_ item: ItemRecord) -> some View {
        let card = item.card
        return VStack(alignment: .leading, spacing: 8) {
            if let preview = item.thumbnailURL(in: services.itemsDirectory) {
                Button {
                    previewedFile = original
                } label: {
                    AsyncImage(url: preview) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        EmptyView()
                    }
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .id(item.updatedAt)
                }
                .buttonStyle(.plain)
                .disabled(original == nil)
                .accessibilityLabel(Text(Self.openTitle(for: item.kind)))
                .help(Text(Self.openTitle(for: item.kind)))
            }
            if let source = card.source {
                Text(source)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(card.title)
                    .font(.title2.bold())
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                if let figure = card.figure {
                    Text(figure)
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(card.style.tint)
                }
            }
            if let byline = card.byline {
                Text(byline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let snippet = Self.snippet(for: item, card: card) {
                Text(snippet)
                    .textSelection(.enabled)
            }
            openButtons(item)
                .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    /// What it is, in a line or two: the summary or what the picture shows, unless
    /// that's only the start of the recognized text (shown in full below) or the
    /// receipt's own lines (its facts say it better).
    static func snippet(for item: ItemRecord, card: ItemCard) -> String? {
        let candidate: String? = switch card.style {
        case .receipt, .travel: nil
        case .product: item.typedFields?.product?.description ?? item.summary
        case .photo: item.imageDescription ?? item.summary
        default: item.summary
        }
        guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              text.caseInsensitiveCompare(card.title) != .orderedSame
        else { return nil }
        let echoed = [item.ocrText, item.text, item.contentText].contains { source in
            guard let source else { return false }
            let start = text.hasSuffix("…") ? String(text.dropLast()) : text
            return source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(start)
        }
        return echoed ? nil : text
    }

    /// Dates and places found in the text, each with the words it was read from.
    @ViewBuilder
    private func foundInText(_ item: ItemRecord) -> some View {
        let dates = item.inferredDates
        let places = item.inferredPlaces
        if !dates.isEmpty || !places.isEmpty {
            Section {
                ForEach(dates, id: \.self) { date in
                    InferredFactRow(
                        title: Text(date.role.title),
                        value: date.date.formatted(date: .abbreviated, time: date.hasTime ? .shortened : .omitted),
                        systemImage: date.role == .deadline || date.role == .expiry ? "hourglass" : "calendar",
                        evidence: date.evidence.map { item.context(of: $0) ?? $0 },
                        source: date.source
                    )
                }
                ForEach(places, id: \.self) { place in
                    let row = InferredFactRow(
                        title: Text("Place"),
                        value: [place.name, place.address].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "mappin.and.ellipse",
                        evidence: nil,
                        source: place.source
                    )
                    if let maps = place.mapsURL {
                        Link(destination: maps) { row }
                            .help(Text("Show in Maps"))
                    } else {
                        row
                    }
                }
            } header: {
                Text("Found in the Text")
            } footer: {
                Text("Read from the words in this item. Check them before you rely on them.")
            }
        }
    }

    private func longText(_ text: String) -> some View {
        let isLong = text.count > Self.previewCharacters
        return VStack(alignment: .leading, spacing: 8) {
            Text(isLong && !showsFullText ? String(text.prefix(Self.previewCharacters)) + "…" : text)
                .textSelection(.enabled)
            if isLong && !showsFullText {
                Button("Show All") { showsFullText = true }
            }
        }
    }

    /// Back to the thing itself: the page (at the highlight), or the saved file.
    @ViewBuilder
    private func openButtons(_ item: ItemRecord) -> some View {
        let link = item.anchorURL ?? item.canonicalURL.flatMap { URL(string: $0) }
        let shared = [original ?? link].compactMap { $0 }
        if link != nil || original != nil {
            HStack(spacing: 10) {
                if let link {
                    Link(destination: link) {
                        Label(item.anchor == nil ? LocalizedStringKey("Open Page") : "Open at Highlight", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                    .help(Text(link.absoluteString))
                }
                if let original {
                    Button {
                        previewedFile = original
                    } label: {
                        Label(Self.openTitle(for: item.kind), systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .help(Text("Quick Look"))
                }
                Button {
                    showsShare = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .sharePicker(isPresented: $showsShare, items: shared)
                .help(Text("Share"))
            }
            .controlSize(.small)
        }
    }

    static func openTitle(for kind: ItemKind) -> LocalizedStringKey {
        switch kind {
        case .image: "View Photo"
        case .pdf: "View PDF"
        default: "View File"
        }
    }

    /// The original file, if it's on this device (originals may not sync).
    private func originalFile() async -> URL? {
        guard let directory = services.itemsDirectory,
              let attachment = try? await services.items.attachments(forItem: itemID).first(where: { $0.role == .original })
        else { return nil }
        let url = directory.appending(path: itemID).appending(path: attachment.fileName)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    private func addAction() {
        let title = newAction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newAction = ""
        let (repository, id) = (services.actions, itemID)
        performEdit { _ = try await repository.add(title: title, itemID: id) }
    }

    private func deleteAction(_ action: ActionRecord) {
        let repository = services.actions
        performEdit { try await repository.delete(action.id) }
    }

    private func toggle(_ action: ActionRecord) {
        let (repository, id) = (services.actions, itemID)
        performEdit {
            let completion = try await repository.setDone(action.status != .done, forAction: action.id)
            if completion.finishedItemID == id { showsDonePrompt = true }
        }
    }

    private func saveNote() {
        guard let item, noteDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (item.note ?? "") else { return }
        let (items, id, note) = (services.items, item.id, noteDraft)
        performEdit { try await items.setNote(note, forItem: id) }
    }

    private func setStatus(_ status: ItemStatus) {
        guard let item else { return }
        changeStatus(status, of: [item], using: services.items)
    }

    /// Done or trashed, the item leaves the list it was opened from: go back to it
    /// (the banner there offers Undo).
    private func finish(_ item: ItemRecord, as status: ItemStatus) {
        changeStatus(status, of: [item], using: services.items)
        dismiss()
    }
}

/// A fact the item states about itself, with where it came from underneath.
private struct FactRow: View {
    let fact: ItemFact
    var mapsURL: URL?

    var body: some View {
        let row = LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(for: fact.label))
                Text(Self.source(for: fact.source))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if let mapsURL {
            Link(destination: mapsURL) { row }
                .help(Text("Show in Maps"))
        } else {
            row
        }
    }

    private var value: String {
        switch fact.value {
        case .text(let text): text
        case .date(let date, let hasTime): date.formatted(date: .abbreviated, time: hasTime ? .shortened : .omitted)
        }
    }

    static func title(for label: ItemFact.Label) -> LocalizedStringKey {
        switch label {
        case .merchant: "Merchant"
        case .total: "Total"
        case .purchased: "Date on Receipt"
        case .taken: "Taken"
        case .location: "Location"
        case .author: "Author"
        case .publisher: "Publisher"
        case .published: "Published"
        case .created: "Created"
        case .price: "Price"
        case .brand: "Brand"
        case .availability: "Availability"
        case .starts: "Starts"
        case .ends: "Ends"
        case .venue: "Venue"
        case .address: "Address"
        case .phone: "Phone"
        case .cookTime: "Total Time"
        case .servings: "Servings"
        case .saved: "Saved"
        case .priceWhenSaved: "Price When Saved"
        case .lowestPrice: "Lowest Price"
        case .priceChecked: "Price Checked"
        case .store: "Store"
        case .doors: "Doors Open"
        case .seat: "Seat"
        case .bookingCode: "Booking Code"
        }
    }

    static func source(for source: ItemFact.Source) -> LocalizedStringKey {
        switch source {
        case .receiptText: "Read from the receipt"
        case .photoMetadata: "From the photo's camera data"
        case .photoLocation: "From the photo's location, named by Apple Maps"
        case .documentInfo: "From the document's properties"
        case .page: "From the page's own data"
        case .walletPass: "From the Wallet pass"
        case .calendarFile: "From the calendar file"
        case .barcode: "From the boarding pass barcode"
        case .textRules: "Read from the text"
        case .model: "Found by Apple Intelligence"
        case .shownOnPage: "As the shop's page showed it"
        case .user: "Corrected by you"
        case .capture(let surface): surface.savedFrom
        }
    }
}

/// One leg of a trip: where from and to, when, and the details that get you aboard.
private struct TripLegSection: View {
    let leg: TripLeg
    let mode: TripFields.Mode
    let index: Int
    let count: Int
    let origin: FieldOrigin?

    var body: some View {
        Section {
            row("From", leg.fromLabel)
            row("To", leg.toLabel)
            if let departure = leg.departure {
                row("Departs", departure.formatted(date: .abbreviated, time: leg.departureHasTime ? .shortened : .omitted))
            }
            if let arrival = leg.arrival {
                row("Arrives", arrival.formatted(date: .abbreviated, time: .shortened))
            }
            row("Terminal", leg.terminal)
            row("Gate", leg.gate)
            row("Platform", leg.platform)
            row("Seat", leg.seat)
        } header: {
            Text(title)
        } footer: {
            Text(FactRow.source(for: ItemRecord.source(origin)))
        }
    }

    private var title: String {
        let number = [leg.carrier, leg.number].compactMap { $0 }.joined(separator: " ")
        let kind: String = switch mode {
        case .flight: String(localized: "Flight")
        case .train: String(localized: "Train")
        case .bus: String(localized: "Bus")
        case .boat: String(localized: "Boat")
        case .other: String(localized: "Trip")
        }
        let part = count > 1 ? String(localized: "\(index + 1) of \(count)") : nil
        return [kind, number.isEmpty ? nil : number, part].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }
}

/// A date or place found in the text, with the words it came from.
private struct InferredFactRow: View {
    let title: Text
    let value: String
    let systemImage: String
    let evidence: String?
    let source: FactSource

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 8)
                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Group {
                    if let evidence, !evidence.isEmpty {
                        Text("“\(evidence)” · \(Text(Self.method(for: source)))")
                            .lineLimit(3)
                    } else {
                        Text(Self.method(for: source))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    static func method(for source: FactSource) -> LocalizedStringKey {
        switch source {
        case .structured: "From the item's own data"
        case .model: "Found by Apple Intelligence"
        case .detector: "Found in the text"
        }
    }
}

extension ItemDate.Role {
    var title: LocalizedStringKey {
        switch self {
        case .eventStart: "Starts"
        case .eventEnd: "Ends"
        case .deadline: "Deadline"
        case .expiry: "Expires"
        case .reservation: "Reservation"
        case .mentioned: "Date"
        case .departure: "Departs"
        }
    }
}

extension CaptureSurface {
    /// How something was saved, for its Details.
    var savedFrom: LocalizedStringKey {
        switch self {
        case .shareSheet: "From the Share menu"
        case .safariExtension: "From Safari"
        case .services: "From the Services menu"
        case .quickCapture: "With Quick Capture"
        case .appIntent: "With Shortcuts"
        case .inApp: "In Laterwise"
        case .screenshotImport: "From your screenshots"
        }
    }
}

extension ItemPlace {
    /// Opens the place in Apple Maps: at its coordinates when known, else by name.
    var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        var query = [URLQueryItem(name: "q", value: [name, address].compactMap { $0 }.joined(separator: ", "))]
        if let latitude, let longitude {
            query.append(URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"))
        }
        components?.queryItems = query
        return components?.url
    }
}

extension ItemRecord {
    /// The text-fragment or message link that returns to the exact place (PRD F5).
    var anchorURL: URL? {
        switch anchor {
        case .web(let url, _): url
        case .mail(let url): url
        default: nil
        }
    }

    /// Where the photo was taken, in Apple Maps.
    var photoMapsURL: URL? {
        guard let photo = typedFields?.photo, let latitude = photo.latitude, let longitude = photo.longitude else { return nil }
        return ItemPlace(
            name: photo.placeName ?? "", latitude: latitude, longitude: longitude, source: .structured
        ).mapsURL
    }
}
