import Core
import SwiftUI

/// One habit on the note (spec-collapsed-note.md §2.7): leaf check-off, name (tap to filter),
/// subtitle, the handwritten line (with its info button), and the journey's brush circle.
struct HabitRowView: View {
    let row: NoteRow
    let isSelected: Bool
    let toggle: () -> Void
    let select: () -> Void
    /// A click that changes nothing stored (the info button): counts as using the note.
    var used: () -> Void = {}

    @State private var showsInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            mainRow
            if showsInfo, let topic = row.line?.topic {
                InfoBox(entry: topic.entry)
                    .transition(.opacity)
            }
        }
        // The line changed (danger → recovered) or went away: its explanation closes.
        .onChange(of: row.line) { showsInfo = false }
    }

    private var mainRow: some View {
        HStack(alignment: .center, spacing: 8) {
            check
            VStack(alignment: .leading, spacing: 1) {
                Button(action: select) {
                    VStack(alignment: .leading, spacing: 1) {
                    // Lines wrap rather than cut off: the column is narrow (about 150 points).
                    Text(row.name)
                        .font(.text(14, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(row.subtitle)
                            .font(.text(11))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 5)
                    .padding(.bottom, row.line == nil ? 5 : 0)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The line sits outside the button (for its info button) but is still part of
                // what VoiceOver says for the habit, as before Phase 7.
                .accessibilityLabel([row.name, row.subtitle, row.line?.text].compactMap { $0 }.joined(separator: ", "))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityHint(isSelected ? "Shows all habits" : "Shows just this habit's days")
                .accessibilityIdentifier("row.\(row.name).name")
                // Outside the name's button, so its info button gets its own clicks.
                if let line = row.line { lineView(line) }
            }
            .background(isSelected ? AnyShapeStyle(Palette.selectedName) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .padding(.leading, -4)
            JourneyBadge(journey: row.journey)
        }
        .frame(minHeight: Metrics.habitRowMinHeight)
        .animation(.easeInOut(duration: 0.2), value: row.line)
    }

    private func lineView(_ line: RowLine) -> some View {
        HStack(alignment: .center, spacing: 2) {
            Text(line.text)
                .font(.handwriting(12))
                .foregroundStyle(line.color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture(perform: select)
                .accessibilityHidden(true) // read with the name (above)
            if let topic = line.topic {
                InfoButton(topic: topic, isExpanded: Binding(get: { showsInfo }, set: {
                    used()
                    showsInfo = $0
                }))
                .accessibilityIdentifier("row.\(row.name).info")
            }
        }
        .padding(.leading, 8)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    @ViewBuilder private var check: some View {
        switch row.check {
        case .leaf(let state):
            Button(action: toggle) {
                LeafMark(state: state)
                    .frame(width: Metrics.leafButtonSize, height: Metrics.leafButtonSize)
                    .contentShape(Circle())
                    .animation(.easeInOut(duration: 0.25), value: state)
            }
            .buttonStyle(.plain)
            .disabled(!row.canToggle)
            .accessibilityLabel(row.name)
            .accessibilityValue(Self.spokenState(state))
            .accessibilityHint(row.canToggle ? (row.isDone ? "Unchecks it" : "Checks it off") : "")
            .accessibilityIdentifier("leaf.\(row.name)")
        case .next(let text):
            Text(text ?? "")
                .font(.text(10.5))
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: Metrics.leafButtonSize, height: Metrics.leafButtonSize)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier("row.\(row.name).next")
        }
    }

    nonisolated static func spokenState(_ state: LeafState) -> String {
        switch state {
        case .checked: "done"
        case .unchecked: "not done"
        case .rested: "rest day"
        case .dimmed: "not scheduled today"
        }
    }
}

extension RowLine {
    var color: ColorToken {
        switch self {
        case .danger: Palette.dangerText
        case .recovered: Palette.goldText
        case .resting: Palette.mossText
        }
    }
}
