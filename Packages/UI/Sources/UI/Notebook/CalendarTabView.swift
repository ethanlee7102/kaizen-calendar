import Core
import SwiftUI

/// The Calendar tab (spec-calendar-and-goal-detail.md #5): a big month with the note's marks,
/// or the year as a heatmap, filtered by habit chips. Clicking a day opens its day card.
struct CalendarTabView: View {
    let input: NoteInput
    @Bindable var navigation: NotebookNavigation
    let used: () -> Void
    let open: (DayKey) -> Void

    @State private var hover = DayHover()

    static let cellHeight: CGFloat = 58

    private var month: DayKey { input.clampedCalendarMonth(navigation.calendarMonth ?? input.today) }
    private var year: Int {
        let years = input.calendarYears
        return min(max(navigation.calendarYear ?? input.today.year, years.lowerBound), years.upperBound)
    }
    /// The filter, unless its habit is gone.
    private var filter: HabitID? { navigation.calendarFilter.flatMap { input.habit($0) == nil ? nil : $0 } }
    private var isMonth: Bool { navigation.calendarMode == .month }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chips
            if isMonth { monthView } else { yearView }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(isMonth ? DayText.monthName(month.month) : String(year))
                .font(.heading(28))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("calendar.title")
            Text(isMonth ? String(month.year) : "Year")
                .font(.heading(14, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            HStack(spacing: 2) {
                arrow("‹", label: isMonth ? "Previous month" : "Previous year", enabled: canStep(-1)) { step(-1) }
                arrow("›", label: isMonth ? "Next month" : "Next year", enabled: canStep(1)) { step(1) }
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            Spacer()
            ModeToggle(isMonth: isMonth) { month in
                used()
                navigation.calendarMode = month ? .month : .year
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        }
    }

    private func arrow(_ text: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.text(18))
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityIdentifier(label.hasPrefix("Previous") ? "calendar.previous" : "calendar.next")
    }

    private func canStep(_ offset: Int) -> Bool {
        if isMonth {
            let target = CalendarMath.month(month, adding: offset)
            return target >= input.firstCalendarMonth && target <= input.lastCalendarMonth
        }
        return input.calendarYears.contains(year + offset)
    }

    private func step(_ offset: Int) {
        used()
        hover.clear()
        if isMonth {
            navigation.calendarMonth = input.clampedCalendarMonth(CalendarMath.month(month, adding: offset))
        } else {
            navigation.calendarYear = year + offset
        }
    }

    // MARK: Chips

    private var chips: some View {
        HStack(spacing: 6) {
            chip("All", selected: filter == nil) { navigation.calendarFilter = nil }
            ForEach(input.chipHabits) { habit in
                chip(habit.name, selected: filter == habit.id) { navigation.calendarFilter = habit.id }
            }
            let inactive = input.inactiveHabits
            if !inactive.isEmpty {
                let selected = inactive.first { $0.id == filter }
                Menu {
                    ForEach(inactive) { habit in
                        Button(habit.name) {
                            used()
                            navigation.calendarFilter = habit.id
                        }
                    }
                } label: {
                    Text("\(selected?.name ?? "Inactive") ▾")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(FilterChipStyle(isSelected: selected != nil))
                .fixedSize()
                .accessibilityLabel(selected.map { "Inactive: \($0.name)" } ?? "Inactive habits")
                .accessibilityIdentifier("calendar.inactive")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by habit")
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title) {
            used()
            hover.clear()
            action()
        }
        .buttonStyle(FilterChipStyle(isSelected: selected))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("calendar.chip.\(title)")
    }

    // MARK: Month

    private var monthView: some View {
        let grid = MonthGrid(containing: month)
        return VStack(alignment: .leading, spacing: 8) {
            if let summary = input.monthSummary(for: month, filter: filter) {
                Text(summary)
                    .font(.text(13))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityIdentifier("calendar.summary")
            }
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(Weekday.allCases, id: \.self) { weekday in
                        Text(weekday.shortName.uppercased())
                            .font(.text(10.5, weight: .medium))
                            .tracking(0.8)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(grid.weeks.indices, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { column in
                                if let day = grid.weeks[week][column] {
                                    bigCell(input.calendarCell(for: day, filter: filter))
                                } else {
                                    Color.clear.frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
                                        .overlay(alignment: .trailing) { verticalRule }
                                        .overlay(alignment: .bottom) { horizontalRule }
                                }
                            }
                        }
                    }
                }
                .overlay(alignment: .top) { horizontalRule }
                .overlay(alignment: .leading) { verticalRule }
                .dayTooltips(hover) { input.cell(for: $0, filter: filter).tooltip }
            }
            Text("Click a day to open its card · the pencil mark means you wrote a note")
                .font(.handwriting(12.5))
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private var horizontalRule: some View { Rectangle().fill(Palette.rule).frame(height: 1) }
    private var verticalRule: some View { Rectangle().fill(Palette.rule).frame(width: 1) }

    private func bigCell(_ calendarCell: CalendarCell) -> some View {
        let cell = calendarCell.cell
        return Button {
            hover.clear()
            open(cell.day)
        } label: {
            DayCellView(day: cell.day.day, mark: cell.mark, isToday: cell.isToday, scale: 1.45, height: Self.cellHeight)
                .overlay(alignment: .topTrailing) {
                    if calendarCell.hasNote {
                        NoteTick()
                            .stroke(Palette.pencil, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)
                            .padding(.trailing, 8)
                    }
                }
                .overlay(alignment: .trailing) { verticalRule }
                .overlay(alignment: .bottom) { horizontalRule }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!cell.opensDayCard)
        .dayTooltipCell(cell.day, hover: hover)
        .accessibilityLabel(calendarCell.hasNote ? "\(cell.accessibilityLabel). Has a note." : cell.accessibilityLabel)
        .accessibilityHint(cell.opensDayCard ? "Opens the day" : "")
        .accessibilityIdentifier("calendar.day.\(cell.day)")
    }

    // MARK: Year

    private var yearView: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22, alignment: .topLeading), count: 4),
                      alignment: .leading, spacing: 18) {
                ForEach(1...12, id: \.self) { monthNumber in
                    miniMonth(MonthGrid(year: year, month: monthNumber))
                }
            }
            HStack(spacing: 14) {
                ForEach(HeatSquare.legend(filtered: filter != nil), id: \.self) { square in
                    HStack(spacing: 5) {
                        HeatSquareView(square: square, isToday: false, size: 11)
                        Text(square.legendText)
                            .font(.text(11.5))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func miniMonth(_ grid: MonthGrid) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(DayText.monthName(grid.month))
                .font(.heading(13))
                .foregroundStyle(Palette.ink)
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(grid.weeks.indices, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            if let day = grid.weeks[week][column] {
                                square(day)
                            } else {
                                Color.clear.frame(width: 12, height: 12)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(DayText.monthName(grid.month)) \(grid.year)")
    }

    private func square(_ day: DayKey) -> some View {
        let tooltip = input.heatTooltip(for: day, filter: filter)
        return Button {
            open(day)
        } label: {
            HeatSquareView(square: input.heatSquare(for: day, filter: filter), isToday: day == input.today, size: 12)
        }
        .buttonStyle(.plain)
        .disabled(day > input.today)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .accessibilityIdentifier("calendar.square.\(day)")
    }
}

/// Month | Year.
private struct ModeToggle: View {
    let isMonth: Bool
    let choose: (_ month: Bool) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment("Month", selected: isMonth) { choose(true) }
            segment("Year", selected: !isMonth) { choose(false) }
        }
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.fieldLine))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.text(12.5, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(Palette.paper) : AnyShapeStyle(Palette.ink))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? AnyShapeStyle(Palette.indigo) : AnyShapeStyle(.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("calendar.mode.\(title)")
    }
}

/// A habit filter chip: indigo when selected (the mockup's pill chips).
struct FilterChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.text(12.5, weight: isSelected ? .bold : .regular))
            .foregroundStyle(isSelected ? AnyShapeStyle(Palette.paper) : AnyShapeStyle(Palette.ink))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isSelected ? AnyShapeStyle(Palette.indigo) : AnyShapeStyle(.clear), in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Palette.indigo : Palette.fieldLine))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// One day square of the year heatmap.
struct HeatSquareView: View {
    let square: HeatSquare
    let isToday: Bool
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fill)
            .overlay {
                if square == .missed {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.pencil, lineWidth: 1.3)
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.indigo, lineWidth: 1.5).padding(-2)
                }
            }
            .frame(width: size, height: size)
    }

    private var fill: AnyShapeStyle {
        switch square {
        case .allDone: AnyShapeStyle(Palette.vermilion)
        case .someDone: AnyShapeStyle(Palette.vermilion.opacity(0.42))
        case .missed: AnyShapeStyle(.clear)
        case .rest: AnyShapeStyle(Palette.moss.opacity(0.6))
        case .recovered: AnyShapeStyle(Palette.gold)
        case .nothing: AnyShapeStyle(Palette.track.opacity(0.75))
        case .future: AnyShapeStyle(Palette.ink.opacity(0.035))
        }
    }
}

/// The small slanted pencil mark on a day with a note.
nonisolated struct NoteTick: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY - rect.height * 0.1))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.2))
        }
    }
}
