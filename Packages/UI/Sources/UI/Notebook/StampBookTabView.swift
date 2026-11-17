import Core
import SwiftUI

/// The Stamp book tab (spec-stamp-book.md): the stamp-day count on a big seal, and the unlocks
/// found so far. Never says what unlocks next.
struct StampBookTabView: View {
    let input: NotebookInput
    let actions: NotebookActions

    @State private var showsWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Stamp book")
                .font(.heading(28))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 24) {
                StampSeal(count: input.stampDays)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("stamp days")
                            .font(.text(15, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        InfoButton(topic: .stampBook, isExpanded: $showsWhy)
                    }
                    Text("A stamp is a day you did every habit you had planned.")
                        .font(.text(12.5))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsWhy { InfoBox(entry: ScienceTopic.stampBook.entry).frame(maxWidth: 420) }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Unlocks")
                    .font(.heading(16))
                    .foregroundStyle(Palette.ink)
                if input.unlocks.isEmpty {
                    Text("Keep stamping. Something small is waiting.")
                        .font(.handwriting(14))
                        .foregroundStyle(Palette.inkSecondary)
                        .accessibilityIdentifier("stampBook.waiting")
                } else {
                    ForEach(input.unlocks, id: \.unlock) { info in
                        UnlockCard(unlock: info.unlock, settings: input.settings, actions: actions)
                    }
                }
            }
        }
    }
}

/// The count on a vermilion seal; zero is a pencil-outlined empty seal.
private struct StampSeal: View {
    let count: Int

    var body: some View {
        ZStack {
            if count == 0 {
                SealShape()
                    .stroke(Palette.pencil, style: StrokeStyle(lineWidth: 1.6, dash: [3, 2.5]))
            } else {
                SealShape().fill(Palette.vermilion)
                Circle()
                    .inset(by: 120 * (18 - 11.5) / 36)
                    .stroke(Palette.paper, lineWidth: 2)
                    .opacity(0.55)
            }
            Text("\(count)")
                .font(.heading(count >= 1000 ? 30 : 40))
                .monospacedDigit()
                .foregroundStyle(count == 0 ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.onSeal))
        }
        .frame(width: 120, height: 120)
        .rotationEffect(.degrees(-6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) stamp \(count == 1 ? "day" : "days")")
        .accessibilityIdentifier("stampBook.count")
    }
}

/// A found unlock: what it is, and its choice (Dark mode: Light / Dark / Match system). Choices
/// apply instantly and save like settings.
private struct UnlockCard: View {
    let unlock: Unlock
    let settings: SettingsValues
    let actions: NotebookActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(unlock.title)
                .font(.heading(15))
                .foregroundStyle(Palette.ink)
            Text(unlock.summary)
                .font(.text(12))
                .foregroundStyle(Palette.inkSecondary)
            switch unlock {
            case .darkMode:
                AppearanceChips(selection: settings.appearance) { choice in
                    actions.used()
                    actions.updateSettings { $0.appearance = choice }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 360, alignment: .leading)
        .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).strokeBorder(Palette.track))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stampBook.unlock.\(unlock.rawValue)")
    }
}

/// Light / Dark / Match system (the Dark mode card and Settings' Appearance row).
struct AppearanceChips: View {
    let selection: SettingsValues.Appearance
    let choose: (SettingsValues.Appearance) -> Void

    var body: some View {
        ChoiceChips(options: SettingsValues.Appearance.allCases, selection: selection, title: \.title,
                    identifier: "appearance", choose: choose)
    }
}

/// A row of single-choice chips.
struct ChoiceChips<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let identifier: String
    let choose: (Option) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                Button(title(option)) { if option != selection { choose(option) } }
                    .buttonStyle(ChipStyle(isSelected: option == selection))
                    .accessibilityAddTraits(option == selection ? [.isSelected] : [])
                    .accessibilityIdentifier("\(identifier).\(title(option))")
            }
        }
    }
}
