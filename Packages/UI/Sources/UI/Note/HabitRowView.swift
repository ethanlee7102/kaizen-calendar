import Core
import SwiftUI

/// One habit on the note (spec-collapsed-note.md §2.7): leaf check-off, name (tap to filter),
/// subtitle, the handwritten line, and the journey's brush circle.
struct HabitRowView: View {
    let row: NoteRow
    let isSelected: Bool
    let toggle: () -> Void
    let select: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            check
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
                    if let line = row.line {
                        Text(line.text)
                            .font(.handwriting(12))
                            .foregroundStyle(line.color)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? AnyShapeStyle(Palette.selectedName) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.leading, -4)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityHint(isSelected ? "Shows all habits" : "Shows just this habit's days")
            .accessibilityIdentifier("row.\(row.name).name")
            JourneyBadge(journey: row.journey)
        }
        .frame(minHeight: Metrics.habitRowMinHeight)
        .animation(.easeInOut(duration: 0.2), value: row.line)
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
