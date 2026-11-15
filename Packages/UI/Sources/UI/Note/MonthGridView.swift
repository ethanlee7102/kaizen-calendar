import Core
import SwiftUI

/// Weekday letters and the month's days (spec-collapsed-note.md §2–§3). Past days and today open
/// the day card; hovering a day shows what happened on it.
struct MonthGridView: View {
    let input: NoteInput
    let filter: HabitID?
    let open: (DayKey) -> Void

    /// The day under the pointer, once it has rested there briefly.
    @State private var tooltipDay: DayKey?
    /// The day whose tooltip is about to show, and its timer.
    @State private var pendingDay: DayKey?
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        let grid = input.grid
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Weekday.allCases, id: \.self) { weekday in
                    Text(weekday.letter)
                        .font(.text(10.5, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
            }
            .padding(.bottom, 2)
            ForEach(grid.weeks.indices, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = grid.weeks[week][column] {
                            cell(input.cell(for: day, filter: filter))
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: Metrics.gridRowHeight,
                                              maxHeight: Metrics.gridRowHeight)
                        }
                    }
                }
            }
        }
        .overlayPreferenceValue(CellBoundsKey.self) { bounds in
            GeometryReader { proxy in
                if let day = tooltipDay, let anchor = bounds[day],
                   let text = input.cell(for: day, filter: filter).tooltip {
                    Tooltip(text: text, cell: proxy[anchor], width: proxy.size.width)
                }
            }
            .allowsHitTesting(false)
        }
        .onDisappear { hoverTask?.cancel() }
    }

    private func cell(_ cell: NoteCell) -> some View {
        Button {
            // A card opens over the grid, so no exit event will come: clear the tooltip now.
            clearHover()
            open(cell.day)
        } label: {
            DayCellView(day: cell.day.day, mark: cell.mark, isToday: cell.isToday)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!cell.opensDayCard)
        .anchorPreference(key: CellBoundsKey.self, value: .bounds) { [cell.day: $0] }
        .onHover { hovering in hover(cell.day, hovering) }
        .accessibilityLabel(cell.accessibilityLabel)
        .accessibilityHint(cell.opensDayCard ? "Opens the day" : "")
        .accessibilityIdentifier("day.\(cell.day)")
    }

    /// Moving between neighboring days can deliver the new day's enter before the old day's
    /// exit, so an exit only affects its own day (Phase 4 review).
    private func hover(_ day: DayKey, _ hovering: Bool) {
        if hovering {
            hoverTask?.cancel()
            pendingDay = day
            if tooltipDay != day { tooltipDay = nil }
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                tooltipDay = day
            }
        } else {
            if pendingDay == day {
                hoverTask?.cancel()
                pendingDay = nil
            }
            if tooltipDay == day { tooltipDay = nil }
        }
    }

    private func clearHover() {
        hoverTask?.cancel()
        pendingDay = nil
        tooltipDay = nil
    }
}

private struct CellBoundsKey: PreferenceKey {
    static let defaultValue: [DayKey: Anchor<CGRect>] = [:]
    static func reduce(value: inout [DayKey: Anchor<CGRect>], nextValue: () -> [DayKey: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A small paper label above the hovered day, kept inside the grid's width. Drawn by the note
/// itself (not a system tooltip), so it matches the paper and shows even while another app is
/// active.
private struct Tooltip: View {
    let text: String
    let cell: CGRect
    let width: CGFloat

    @State private var size: CGSize = .zero

    var body: some View {
        Text(text)
            .font(.text(11))
            .foregroundStyle(Palette.ink)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: min(240, width), alignment: .leading)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.track))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .position(x: min(max(cell.midX, size.width / 2), width - size.width / 2),
                      y: cell.minY - 4 - size.height / 2)
            .opacity(size == .zero ? 0 : 1)
            .accessibilityHidden(true) // the cell's label says the same
    }
}
