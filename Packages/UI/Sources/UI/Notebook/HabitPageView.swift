import Charts
import Core
import SwiftUI

/// A habit's page (spec-calendar-and-goal-detail.md #6): header, journey, stats, this habit's
/// month, how far you've come, and the weekly consistency graph. Inactive habits show it
/// read-only with Reactivate (spec-goals-list.md).
struct HabitPageView: View {
    let page: HabitPage
    /// Level up / level down, when one applies today (spec-suggestions.md).
    let suggestion: SuggestionCard?
    let addHabitState: HabitRules.AddHabitState
    let actions: NotebookActions
    @Binding var trendSpan: TrendSpan
    let present: (NotebookSheet) -> Void
    /// Move up (-1) / down (+1) in the list.
    let move: (Int) -> Void

    @State private var expandedInfo: ScienceTopic?
    @State private var showsWhyFive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            journeyAndStats
            HStack(alignment: .top, spacing: 26) {
                monthSection.frame(maxWidth: .infinity, alignment: .topLeading)
                historySection.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            trendSection
            if let suggestion { suggestionCard(suggestion) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.name)
                    .font(.heading(32))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("habit.name")
                if let identity = page.identityLine {
                    Text(identity)
                        .font(.handwriting(17))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text(page.detailLine)
                    .font(.text(12.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityIdentifier("habit.detail")
                if let inactive = page.inactiveLine {
                    Text(inactive)
                        .font(.text(12.5, weight: .medium))
                        .foregroundStyle(inactive.hasPrefix("Graduated") ? Palette.goldText : Palette.inkSecondary)
                        .accessibilityIdentifier("habit.inactive")
                }
            }
            Spacer(minLength: 8)
            if page.isActive { activeButtons } else { inactiveButtons }
        }
    }

    private var activeButtons: some View {
        HStack(spacing: 6) {
            switch page.primaryChange {
            case .target:
                Button("Change target") { open(.changeTarget(page.id)) }
                    .buttonStyle(PaperButtonStyle())
                    .accessibilityIdentifier("habit.changeTarget")
            case .schedule:
                Button("Change schedule") { open(.changeSchedule(page.id)) }
                    .buttonStyle(PaperButtonStyle())
                    .accessibilityIdentifier("habit.changeSchedule")
            }
            Button("Edit") { open(.edit(page.id)) }
                .buttonStyle(PaperButtonStyle())
                .accessibilityIdentifier("habit.edit")
            Menu {
                Button("Move Up") { move(-1) }.disabled(!page.canMoveUp)
                Button("Move Down") { move(1) }.disabled(!page.canMoveDown)
                Divider()
                Button("Move to Inactive") {
                    actions.used()
                    actions.deactivate(page.id)
                }
                Button("Delete…") { open(.delete(page.id)) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(PaperButtonStyle())
            .fixedSize()
            .accessibilityLabel("More: move, move to inactive, delete")
            .accessibilityIdentifier("habit.more")
        }
    }

    private var inactiveButtons: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                if addHabitState != .atLimit {
                    Button("Reactivate") {
                        actions.used()
                        actions.reactivate(page.id)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("habit.reactivate")
                }
                Menu {
                    Button("Delete…") { open(.delete(page.id)) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(PaperButtonStyle())
                .fixedSize()
                .accessibilityLabel("More: delete")
                .accessibilityIdentifier("habit.more")
            }
            if addHabitState == .atLimit {
                HStack(alignment: .top, spacing: 4) {
                    Text("You’re at 5 habits. Graduate one that feels automatic to make room.")
                        .font(.text(11.5))
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    InfoButton(topic: .whyFive, isExpanded: $showsWhyFive)
                }
                .frame(maxWidth: 230, alignment: .trailing)
                if showsWhyFive { InfoBox(entry: ScienceTopic.whyFive.entry).frame(maxWidth: 260) }
            }
        }
    }

    /// Section 7 of the page: shown only while a suggestion applies.
    private func suggestionCard(_ card: SuggestionCard) -> some View {
        SuggestionCardView(card: card, accept: {
            actions.used()
            actions.letters.accept(card.suggestion)
        }, chooseOwn: {
            switch card.suggestion.change {
            case .target(_, let to): open(.changeTarget(page.id, prefill: to))
            case .schedule(_, let to): open(.changeSchedule(page.id, prefill: to))
            }
        }, notNow: {
            actions.used()
            actions.letters.notNow(card.suggestion)
        })
    }

    private func open(_ sheet: NotebookSheet) {
        actions.used()
        present(sheet)
    }

    // MARK: Journey and stats

    private var journeyAndStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 22) {
                BigJourneyCircle(journey: page.journey)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Journey")
                            .font(.text(15, weight: .bold))
                            .foregroundStyle(Palette.ink)
                        info(.why66)
                    }
                    Text(page.journeyLine)
                        .font(.text(12.5))
                        .lineSpacing(2)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("habit.journeyLine")
                    HStack(alignment: .top, spacing: 12) {
                        StatCard(title: "Streak", value: "\(page.streak)", unit: page.streakUnit,
                                 caption: page.savesLine, captionIsGold: true, topic: .neverMissTwice, expanded: $expandedInfo)
                            .accessibilityIdentifier("habit.streak")
                        StatCard(title: "Consistency", value: page.consistency, unit: nil, caption: page.consistencyCaption,
                                 captionIsGold: false, topic: .consistency, expanded: $expandedInfo)
                            .accessibilityIdentifier("habit.consistency")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let topic = expandedInfo, [.why66, .neverMissTwice, .consistency].contains(topic) {
                InfoBox(entry: topic.entry)
            }
        }
    }

    private func info(_ topic: ScienceTopic) -> some View {
        InfoButton(topic: topic, isExpanded: Binding(
            get: { expandedInfo == topic }, set: { expandedInfo = $0 ? topic : nil }))
    }

    // MARK: Month and history

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(page.monthTitle)
                .font(.heading(16))
                .foregroundStyle(Palette.ink)
            VStack(spacing: 2) {
                HStack(spacing: 0) {
                    ForEach(Weekday.allCases, id: \.self) { weekday in
                        Text(weekday.letter)
                            .font(.text(10))
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                ForEach(page.month.weeks.indices, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            if let day = page.month.weeks[week][column], let cell = page.monthCells[day] {
                                DayCellView(day: day.day, mark: cell.mark, isToday: cell.isToday, scale: 0.92, height: 30)
                                    .help(cell.tooltip ?? DayText.shortDate(day))
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(cell.accessibilityLabel)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This habit’s month")
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How far you’ve come")
                .font(.heading(16))
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(page.history.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .strokeBorder(Palette.ink, lineWidth: 1.6)
                                .background(Circle().fill(step.isCurrent ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(.clear)))
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)
                            if index < page.history.count - 1 {
                                Rectangle().fill(Palette.fieldLine).frame(width: 1.5).frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 12)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.value)
                                .font(.text(14, weight: .bold))
                                .foregroundStyle(Palette.ink)
                            Text(step.when)
                                .font(.text(11.5))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.bottom, 12)
                        .accessibilityElement(children: .combine)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 4)
        }
        .accessibilityIdentifier("habit.history")
    }

    // MARK: Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Weekly consistency")
                    .font(.heading(16))
                    .foregroundStyle(Palette.ink)
                info(.lookingBack)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(TrendSpan.allCases, id: \.self) { span in
                        Button(span.title) {
                            actions.used()
                            trendSpan = span
                        }
                        .buttonStyle(ChipStyle(isSelected: trendSpan == span))
                        .accessibilityAddTraits(trendSpan == span ? [.isSelected] : [])
                    }
                }
            }
            if expandedInfo == .lookingBack { InfoBox(entry: ScienceTopic.lookingBack.entry) }
            if let trend = page.trend {
                TrendChart(points: trend)
            } else {
                Text("Your weekly graph appears after 2 full weeks.")
                    .font(.handwriting(13))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityIdentifier("habit.trendWaiting")
            }
        }
    }
}

/// The journey's big brush circle: "41 / of 66", or "N / ✓66" after day 66.
private struct BigJourneyCircle: View {
    let journey: Journey

    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 6)
            BrushArc(progress: journey.progress)
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            VStack(spacing: 0) {
                Text("\(journey.count)")
                    .font(.heading(30))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                Text(journey.hasReached66 ? "✓66" : "of 66")
                    .font(.text(11, weight: journey.hasReached66 ? .bold : .regular))
                    .foregroundStyle(journey.hasReached66 ? Palette.vermilion : Palette.inkSecondary)
            }
        }
        .padding(5)
        .frame(width: 110, height: 110)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JourneyBadge.accessibilityText(journey))
        .accessibilityIdentifier("habit.journey")
    }
}

/// Streak / Consistency.
private struct StatCard: View {
    let title: String
    let value: String
    let unit: String?
    let caption: String?
    let captionIsGold: Bool
    let topic: ScienceTopic
    @Binding var expanded: ScienceTopic?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.text(12))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 0)
                InfoButton(topic: topic, isExpanded: Binding(
                    get: { expanded == topic }, set: { expanded = $0 ? topic : nil }))
                    .padding(.vertical, -4)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.heading(26))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                if let unit {
                    Text(unit)
                        .font(.heading(13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                }
            }
            Text(caption ?? " ")
                .font(.text(11))
                .foregroundStyle(captionIsGold ? Palette.goldText : Palette.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 132, alignment: .leading)
        .background(Palette.raisedPaper.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.track))
        .accessibilityElement(children: .contain)
    }
}

/// The weekly consistency line: one point per week, a gold ring on weeks with a recovered miss
/// and a dashed pencil ring on weeks with a miss that broke the streak. Hovering a week lists
/// its misses under the graph.
struct TrendChart: View {
    let points: [TrendPoint]
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    if let percent = point.percent {
                        LineMark(x: .value("Week", index), y: .value("Done", percent))
                            .foregroundStyle(Palette.ink)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        PointMark(x: .value("Week", index), y: .value("Done", percent))
                            .symbol {
                                ZStack {
                                    Circle().fill(Palette.ink).frame(width: 7, height: 7)
                                    if !point.recoveredMisses.isEmpty {
                                        Circle().stroke(Palette.gold, lineWidth: 1.8).frame(width: 15, height: 15)
                                    }
                                    if !point.breakingMisses.isEmpty {
                                        Circle().stroke(Palette.pencil, style: StrokeStyle(lineWidth: 1.4, dash: [2.4, 2]))
                                            .frame(width: 21, height: 21)
                                    }
                                }
                            }
                    }
                    if hovered == index {
                        RuleMark(x: .value("Week", index))
                            .foregroundStyle(Palette.fieldLine)
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: -0.5...(Double(max(points.count, 2)) - 0.5))
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(Palette.track)
                    AxisValueLabel {
                        if let percent = value.as(Int.self) {
                            Text("\(percent)%").font(.text(10)).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: labelIndices) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self), points.indices.contains(index) {
                            Text(points[index].label).font(.text(10)).foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plot = proxy.plotFrame else { return }
                                let x = location.x - geometry[plot].origin.x
                                if let value: Double = proxy.value(atX: x) {
                                    let index = Int(value.rounded())
                                    hovered = points.indices.contains(index) ? index : nil
                                }
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }
            .frame(height: 150)
            .frame(maxWidth: 560)
            .onChange(of: points.count) { hovered = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly consistency: " + points.map { $0.percent.map { "\($0)%" } ?? "nothing scheduled" }
                .joined(separator: ", "))
            .accessibilityIdentifier("habit.trend")
            let caption = TrendPoint.caption(hovered: hovered, in: points)
            Text(caption)
                .font(.text(11.5))
                .foregroundStyle(caption == TrendPoint.legend ? Palette.inkSecondary : Palette.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// At most about 7 labels, always including the latest week.
    private var labelIndices: [Int] {
        let count = points.count
        guard count > 7 else { return Array(0..<count) }
        let stride = Int((Double(count) / 6).rounded(.up))
        return Array(Swift.stride(from: (count - 1) % stride, to: count, by: stride))
    }
}

/// An outlined paper button ("Change target", "Edit", ⋯).
struct PaperButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.text(12.5))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? AnyShapeStyle(Palette.ink.opacity(0.06)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.fieldLine))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
