import Core
import SwiftUI

/// A level-up or level-down suggestion (spec-suggestions.md): Accept / Choose my own / Not now,
/// with an info button. Once it no longer applies, it says so instead of offering buttons.
struct SuggestionCardView: View {
    let card: SuggestionCard
    /// Letters name the habit; the habit's own page doesn't need to.
    var showsHabitName = false
    let accept: () -> Void
    let chooseOwn: () -> Void
    let notNow: () -> Void

    @State private var showsInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    if showsHabitName {
                        Text(card.habitName)
                            .font(.text(11.5, weight: .bold))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Text(card.title)
                        .font(.handwriting(15, weight: .semiBold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.change)
                        .font(.text(12.5))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("suggestion.change")
                }
                Spacer(minLength: 4)
                InfoButton(topic: card.topic, isExpanded: $showsInfo)
            }
            if showsInfo { InfoBox(entry: card.topic.entry) }
            if let line = card.stateLine {
                Text(line)
                    .font(.text(12, weight: .medium))
                    .foregroundStyle(card.state == .accepted ? Palette.mossText : Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("suggestion.state")
            } else {
                HStack(spacing: 8) {
                    Button("Accept", action: accept)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("suggestion.accept")
                    Button("Choose my own", action: chooseOwn)
                        .buttonStyle(PaperButtonStyle())
                        .accessibilityIdentifier("suggestion.chooseOwn")
                    Button("Not now", action: notNow)
                        .buttonStyle(LinkButtonStyle(color: Palette.inkSecondary))
                        .accessibilityIdentifier("suggestion.notNow")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Palette.raisedPaper.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.track))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.suggestion.kind == .levelUp ? "Level-up suggestion" : "Level-down suggestion")
        .accessibilityIdentifier("suggestion")
    }
}
