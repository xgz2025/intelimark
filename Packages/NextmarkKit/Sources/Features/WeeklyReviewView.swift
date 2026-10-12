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
import Observation
import Model
import Library
import Intelligence
import Moments
import DesignSystem

/// Where the app should go next, e.g. after a notification tap. RootView follows it.
@MainActor
@Observable
public final class AppNavigator {
    public var destination: MomentDestination?

    public init() {}

    public func open(_ destination: MomentDestination) {
        self.destination = destination
    }
}

/// The Weekly Review (PRD M2): a short stack of saves that are coming up, have
/// open actions, are new this week, or have gone stale. Do · Keep · Toss each one.
struct WeeklyReviewView: View {
    let services: LibraryServices
    @State private var cards: [ReviewCard] = []
    @State private var index = 0
    @State private var isLoaded = false
    @State private var tally = Tally()
    @State private var lastTossed: ReviewCard?
    @State private var drag: CGSize = .zero

    struct Tally {
        var done = 0
        var kept = 0
        var tossed = 0
    }

    private enum Decision {
        case doIt, keep, toss
    }

    var body: some View {
        VStack(spacing: 20) {
            if !isLoaded {
                ProgressView()
            } else if index < cards.count {
                Text("\(index + 1) of \(cards.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                stack
                controls
            } else {
                finished
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Weekly Review")
        .task { await load() }
    }

    private var stack: some View {
        ZStack {
            ForEach(Array((index..<min(index + 3, cards.count)).reversed()), id: \.self) { position in
                let depth = position - index
                ReviewCardView(card: cards[position])
                    .scaleEffect(1 - CGFloat(depth) * 0.05)
                    .offset(y: CGFloat(depth) * 14)
                    .offset(depth == 0 ? drag : .zero)
                    .rotationEffect(.degrees(depth == 0 ? Double(drag.width) / 25 : 0))
                    .allowsHitTesting(depth == 0)
                    .gesture(swipe, isEnabled: depth == 0)
                    .accessibilityHidden(depth != 0)
            }
        }
        .frame(maxWidth: 440, maxHeight: 440)
        .animation(.snappy, value: index)
    }

    private var swipe: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                let (x, y) = (value.translation.width, value.translation.height)
                if y < -120 && abs(y) > abs(x) {
                    decide(.doIt)
                } else if x > 120 {
                    decide(.keep)
                } else if x < -120 {
                    decide(.toss)
                } else {
                    withAnimation(.snappy) { drag = .zero }
                }
            }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(role: .destructive) { decide(.toss) } label: {
                    Label("Toss", systemImage: "trash")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                Button { decide(.keep) } label: {
                    Label("Keep", systemImage: "tray.full")
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                Button { decide(.doIt) } label: {
                    Label("Do", systemImage: "checklist")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.upArrow, modifiers: [])
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if let lastTossed {
                Button("Undo Toss of “\(lastTossed.item.displayTitle)”") { undoToss(lastTossed) }
                    .font(.callout)
                    .buttonStyle(.borderless)
            }
            Text("Swipe up to do, right to keep, left to toss.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var finished: some View {
        ContentUnavailableView {
            if cards.isEmpty {
                Label("Nothing to Review", systemImage: "checkmark.circle")
            } else {
                Label("Review Done", systemImage: "checkmark.circle")
            }
        } description: {
            if cards.isEmpty {
                Text("New, upcoming and forgotten saves will show up here each week.")
            } else {
                Text("\(tally.done) to do · \(tally.kept) kept · \(tally.tossed) tossed")
            }
        } actions: {
            Button("Check Again") {
                Task { await load() }
            }
        }
    }

    private func decide(_ decision: Decision) {
        guard index < cards.count else { return }
        let card = cards[index]
        let (items, actions) = (services.items, services.actions)
        lastTossed = nil
        switch decision {
        case .doIt:
            tally.done += 1
            let suggestion = ActionSuggester.suggestions(for: card.item.digest).first
                ?? SuggestedAction(title: String(localized: "Follow up: \(card.item.displayTitle)"), itemID: card.item.id)
            performEdit {
                try await items.setStatus(.active, forItem: card.id)
                _ = try await actions.accept(suggestion)
            }
        case .keep:
            tally.kept += 1
            performEdit {
                try await items.setStatus(.active, forItem: card.id)
                try await items.markOpened(card.id)
            }
        case .toss:
            tally.tossed += 1
            lastTossed = card
            performEdit { try await items.setStatus(.trashed, forItem: card.id) }
        }
        withAnimation(.snappy) {
            drag = .zero
            index += 1
        }
    }

    private func undoToss(_ card: ReviewCard) {
        tally.tossed -= 1
        lastTossed = nil
        let (items, id, status) = (services.items, card.id, card.item.status)
        performEdit { try await items.setStatus(status, forItem: id) }
    }

    private func load() async {
        cards = (try? await services.items.reviewQueue()) ?? []
        index = 0
        tally = Tally()
        lastTossed = nil
        isLoaded = true
    }
}

private struct ReviewCardView: View {
    let card: ReviewCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            reasonLabel
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tint)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: card.item.kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(card.item.displayTitle)
                    .font(.title3.bold())
                    .lineLimit(3)
            }
            if let subtitle = card.item.subtitle, subtitle != card.item.summary {
                Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
            }
            if let summary = card.item.summary, !summary.isEmpty {
                Text(summary).lineLimit(5)
            }
            Spacer(minLength: 0)
            if let intent = card.item.intent ?? card.item.suggestedIntent {
                Label(intent.title, systemImage: intent.symbolName)
                    .font(.caption)
                    .foregroundStyle(intent.tint)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var reasonLabel: some View {
        switch card.reason {
        case .new:
            Label("New this week", systemImage: "sparkle")
        case .comingUp(let date):
            Label("Coming up \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))", systemImage: "calendar")
        case .hasActions(let count):
            Label("\(count) open actions", systemImage: "checklist")
        case .stale:
            Label("Not opened in a while", systemImage: "clock")
        }
    }
}
