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

/// "Correct?": fields Laterwise read by rules or a model, not stated by the item,
/// put to the person once: right, wrong in places, or not that kind of thing.
struct CorrectionBanner: View {
    let item: ItemRecord
    let services: LibraryServices
    let onEdit: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(question).font(.headline)
                        Text(Self.explanation(for: origin))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    Button { correct(.confirm) } label: {
                        Label("Correct", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .help(Text("Keep these details as they are"))
                    Button("Edit…", action: onEdit)
                        .buttonStyle(.bordered)
                        .help(Text("Fix what Laterwise read"))
                    Button(role: .destructive) { correct(.reject(item.saveType)) } label: {
                        Text(Self.rejectTitle(for: item.saveType))
                    }
                    .buttonStyle(.bordered)
                    .help(Text("Laterwise read it wrong: show it as an ordinary save"))
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    private var origin: FieldOrigin? {
        let fields = item.typedFields
        return switch item.saveType {
        case .travel: fields?.trip?.origin
        case .show: fields?.ticket?.origin
        case .receipt: fields?.receipt.map { $0.origin ?? .text }
        case .product: fields?.product?.origin
        case .article, .link, .other: nil
        }
    }

    private var question: String {
        switch item.saveType {
        case .travel: String(localized: "Is this trip right?")
        case .show: String(localized: "Are the show's details right?")
        case .receipt: String(localized: "Is this receipt right?")
        case .product:
            if let product = item.typedFields?.product, let price = product.price {
                String(localized: "Is \(ItemRecord.money(price, currency: product.currency)) the price?")
            } else {
                String(localized: "Is this product right?")
            }
        case .article, .link, .other: ""
        }
    }

    static func explanation(for origin: FieldOrigin?) -> LocalizedStringKey {
        switch origin {
        case .model: "Apple Intelligence read these from the item's words. Check them before you rely on them."
        case .shown: "Read from how the shop's page looks, not from its data: it may be another price on the page."
        default: "Laterwise read these from the item's words. Check them before you rely on them."
        }
    }

    static func rejectTitle(for type: SaveType) -> LocalizedStringKey {
        switch type {
        case .travel: "Not a Trip"
        case .show: "Not a Show"
        case .receipt: "Not a Receipt"
        case .product: "Not a Product"
        case .article, .link, .other: "Not This"
        }
    }

    private func correct(_ correction: FieldCorrection) {
        let (items, id) = (services.items, item.id)
        performEdit { try await items.correct(correction, forItem: id) }
    }
}

/// Edits the fields that make an item what it is: a trip's legs, a show's details,
/// a receipt's total, a product's price. What's saved is marked as the person's.
struct FieldsEditor: View {
    let item: ItemRecord
    let services: LibraryServices
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch item.saveType {
                case .travel:
                    TripEditor(trip: item.typedFields?.trip ?? TripFields(mode: .flight, legs: [TripLeg()]), save: save)
                case .show:
                    TicketEditor(ticket: item.typedFields?.ticket ?? TicketFields(name: item.displayTitle), save: save)
                case .receipt:
                    ReceiptEditor(receipt: item.typedFields?.receipt ?? ReceiptFields(), save: save)
                case .product:
                    ProductEditor(product: item.typedFields?.product ?? ProductFields(name: item.displayTitle), save: save)
                case .article, .link, .other:
                    EmptyView()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func save(_ correction: FieldCorrection) {
        let (items, id) = (services.items, item.id)
        performEdit { try await items.correct(correction, forItem: id) }
        dismiss()
    }
}

/// The text in an optional field; empty means none.
private func text(_ binding: Binding<String?>) -> Binding<String> {
    Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0 })
}

private func cleaned(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

/// A date that may be unknown: a switch, then the date (and, optionally, its time).
private struct OptionalDateRow: View {
    let title: LocalizedStringKey
    @Binding var date: Date?
    var hasTime: Binding<Bool>?

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { date = $0 ? (date ?? Calendar.current.startOfDay(for: .now).addingTimeInterval(9 * 3600)) : nil }
        ))
        if let current = date {
            let binding = Binding(get: { current }, set: { date = $0 })
            if let hasTime {
                Toggle("Time Known", isOn: hasTime)
                DatePicker(title, selection: binding, displayedComponents: hasTime.wrappedValue ? [.date, .hourAndMinute] : [.date])
                    .labelsHidden()
            } else {
                DatePicker(title, selection: binding, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }
}

private struct TripEditor: View {
    /// A leg with an identity, so removing one doesn't mix up the fields of the others.
    struct Entry: Identifiable {
        let id = UUID()
        var leg: TripLeg
        /// As read, to tell which places were typed over.
        let original: TripLeg

        init(leg: TripLeg) {
            self.leg = leg
            original = leg
        }
    }

    @State private var mode: TripFields.Mode
    @State private var bookingCode: String
    @State private var legs: [Entry]
    let save: (FieldCorrection) -> Void

    init(trip: TripFields, save: @escaping (FieldCorrection) -> Void) {
        _mode = State(initialValue: trip.mode)
        _bookingCode = State(initialValue: trip.bookingCode ?? "")
        _legs = State(initialValue: (trip.legs.isEmpty ? [TripLeg()] : trip.legs).map { Entry(leg: $0) })
        self.save = save
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $mode) {
                    Text("Flight").tag(TripFields.Mode.flight)
                    Text("Train").tag(TripFields.Mode.train)
                    Text("Bus").tag(TripFields.Mode.bus)
                    Text("Boat").tag(TripFields.Mode.boat)
                    Text("Trip").tag(TripFields.Mode.other)
                }
                TextField("Booking Code", text: $bookingCode)
            }
            ForEach($legs) { $entry in
                Section {
                    TextField("Carrier", text: text($entry.leg.carrier))
                    TextField("Number", text: text($entry.leg.number))
                    TextField("From", text: text($entry.leg.from))
                    TextField("To", text: text($entry.leg.to))
                    OptionalDateRow(title: "Departs", date: $entry.leg.departure, hasTime: $entry.leg.departureHasTime)
                    OptionalDateRow(title: "Arrives", date: $entry.leg.arrival)
                    TextField("Terminal", text: text($entry.leg.terminal))
                    TextField("Gate", text: text($entry.leg.gate))
                    TextField("Platform", text: text($entry.leg.platform))
                    TextField("Seat", text: text($entry.leg.seat))
                    if legs.count > 1 {
                        let id = entry.id
                        Button("Remove This Leg", role: .destructive) { legs.removeAll { $0.id == id } }
                    }
                } header: {
                    Text(title(of: entry.id))
                }
            }
            Section {
                Button("Add a Leg", systemImage: "plus") { legs.append(Entry(leg: TripLeg())) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(.trip(trip)) }
            }
        }
    }

    private func title(of id: UUID) -> String {
        guard legs.count > 1, let index = legs.firstIndex(where: { $0.id == id }) else { return String(localized: "Journey") }
        return String(localized: "Leg \(index + 1)")
    }

    /// The trip as typed: empty fields are none, and an empty leg is dropped.
    private var trip: TripFields {
        let legs = legs.map { entry in
            var leg = entry.leg
            leg.carrier = cleaned(leg.carrier)
            leg.number = cleaned(leg.number)
            leg.from = cleaned(leg.from)
            leg.to = cleaned(leg.to)
            // A place typed over drops the airport code read with the old one.
            if leg.from != entry.original.from { leg.fromCode = nil }
            if leg.to != entry.original.to { leg.toCode = nil }
            leg.terminal = cleaned(leg.terminal)
            leg.gate = cleaned(leg.gate)
            leg.platform = cleaned(leg.platform)
            leg.seat = cleaned(leg.seat)
            return leg
        }
        .filter { $0.from != nil || $0.to != nil || $0.number != nil || $0.departure != nil }
        return TripFields(mode: mode, legs: legs, bookingCode: cleaned(bookingCode))
    }
}

private struct TicketEditor: View {
    @State var ticket: TicketFields
    let save: (FieldCorrection) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Show", text: text($ticket.name))
                OptionalDateRow(title: "Starts", date: $ticket.startDate, hasTime: $ticket.startHasTime)
                OptionalDateRow(title: "Doors Open", date: $ticket.doorsAt)
                OptionalDateRow(title: "Ends", date: $ticket.endDate)
            }
            Section {
                TextField("Venue", text: text($ticket.venue))
                TextField("Address", text: text($ticket.address))
                TextField("Seat", text: text($ticket.seat))
                TextField("Booking Code", text: text($ticket.bookingCode))
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var ticket = ticket
                    ticket.name = cleaned(ticket.name)
                    ticket.venue = cleaned(ticket.venue)
                    ticket.address = cleaned(ticket.address)
                    ticket.seat = cleaned(ticket.seat)
                    ticket.bookingCode = cleaned(ticket.bookingCode)
                    save(.ticket(ticket))
                }
            }
        }
    }
}

private struct ReceiptEditor: View {
    @State var receipt: ReceiptFields
    @State private var total = ""
    let save: (FieldCorrection) -> Void

    init(receipt: ReceiptFields, save: @escaping (FieldCorrection) -> Void) {
        _receipt = State(initialValue: receipt)
        _total = State(initialValue: ProductPriceSection.text(for: receipt.total))
        self.save = save
    }

    var body: some View {
        Form {
            Section {
                TextField("Merchant", text: text($receipt.merchant))
                LabeledContent("Total") {
                    HStack(spacing: 4) {
                        TextField("Total", text: $total)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("Currency", text: text($receipt.currency))
                            .labelsHidden()
                            .frame(maxWidth: 60)
                    }
                }
                OptionalDateRow(title: "Date on Receipt", date: $receipt.purchasedAt)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var receipt = receipt
                    receipt.merchant = cleaned(receipt.merchant)
                    receipt.currency = cleaned(receipt.currency)?.uppercased()
                    receipt.total = ProductPriceSection.parse(total)
                    save(.receipt(receipt))
                }
            }
        }
    }
}

private struct ProductEditor: View {
    @State private var name: String
    @State private var price: String
    @State private var currency: String
    @State private var store: String
    let save: (FieldCorrection) -> Void

    init(product: ProductFields, save: @escaping (FieldCorrection) -> Void) {
        _name = State(initialValue: product.name ?? "")
        _price = State(initialValue: ProductPriceSection.text(for: product.price))
        _currency = State(initialValue: product.currency ?? "")
        _store = State(initialValue: product.store ?? "")
        self.save = save
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                LabeledContent("Price") {
                    HStack(spacing: 4) {
                        TextField("Price", text: $price)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        TextField("Currency", text: $currency)
                            .labelsHidden()
                            .frame(maxWidth: 60)
                    }
                }
                TextField("Store", text: $store)
            } footer: {
                Text("A price you fix here replaces the one Laterwise read; it isn't counted as a price change.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save(.product(
                        name: cleaned(name), price: ProductPriceSection.parse(price),
                        currency: cleaned(currency)?.uppercased(), store: cleaned(store)
                    ))
                }
            }
        }
    }
}
