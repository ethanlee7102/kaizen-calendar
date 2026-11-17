import Core
import SwiftUI

/// Weekday letters and the month's days (spec-collapsed-note.md §2–§3). Past days and today open
/// the day card; hovering a day shows what happened on it.
struct MonthGridView: View {
    let input: NoteInput
    let filter: HabitID?
    let open: (DayKey) -> Void

    @State private var hover = DayHover()

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
        .dayTooltips(hover) { input.cell(for: $0, filter: filter).tooltip }
    }

    private func cell(_ cell: NoteCell) -> some View {
        Button {
            hover.clear()
            open(cell.day)
        } label: {
            DayCellView(day: cell.day.day, mark: cell.mark, isToday: cell.isToday)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!cell.opensDayCard)
        .dayTooltipCell(cell.day, hover: hover)
        .accessibilityLabel(cell.accessibilityLabel)
        .accessibilityHint(cell.opensDayCard ? "Opens the day" : "")
        .accessibilityIdentifier("day.\(cell.day)")
    }
}
