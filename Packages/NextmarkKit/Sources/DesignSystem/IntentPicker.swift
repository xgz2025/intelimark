import SwiftUI
import Model

/// One-tap "Why are you saving this?" chips (PRD C1). Tapping the selected chip clears it.
public struct IntentPicker: View {
    @Binding private var selection: Intent?

    public init(selection: Binding<Intent?>) {
        _selection = selection
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Intent.allCases) { intent in
                    IntentChip(intent: intent, isSelected: selection == intent) {
                        selection = selection == intent ? nil : intent
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

public struct IntentChip: View {
    let intent: Intent
    let isSelected: Bool
    let action: () -> Void

    public init(intent: Intent, isSelected: Bool, action: @escaping () -> Void) {
        self.intent = intent
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(intent.title, systemImage: intent.symbolName)
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? intent.tint.opacity(0.22) : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? intent.tint : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
