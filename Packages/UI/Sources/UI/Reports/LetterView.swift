import Core
import SwiftUI

/// What a letter page can ask of the notebook: open a form over the page (Choose my own, a
/// day-66 target or schedule change).
enum LetterRequest {
    case chooseTarget(Suggestion)
    case chooseSchedule(Suggestion)
    case decideTarget(letter: UUID, habit: HabitID)
    case decideSchedule(letter: UUID, habit: HabitID)
}

/// A report letter on paper (spec-reports.md): the handwritten greeting, then its sections down
/// the page, ending with its question(s) and Done. Filed letters are read-only, with the answers
/// you gave; their suggestion and Reactivate buttons still act on today's data.
struct LetterView: View {
    let page: LetterPage
    let actions: NotebookActions
    let back: () -> Void
    let request: (LetterRequest) -> Void

    @State private var expandedInfo: ScienceTopic?

    private var letters: LetterActions { actions.letters }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("‹ All letters") {
                actions.used()
                back()
            }
            .buttonStyle(LinkButtonStyle())
            .accessibilityIdentifier("letter.back")

            VStack(alignment: .leading, spacing: 20) {
                greeting
                if page.isUnreadable {
                    Text("This letter couldn’t be read. It may have been written by a newer version of 66 Days.")
                        .font(.text(13))
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    sections
                }
                footer
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.track))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("letter")
    }

    // MARK: Greeting

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.handwriting(28, weight: .semiBold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("letter.title")
                Text(page.arrivedLine)
                    .font(.text(12))
                    .foregroundStyle(Palette.inkSecondary)
                if let line = page.firstWeekLine {
                    Text(line)
                        .font(.handwriting(14))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, 4)
                }
                if let line = page.checkInLine {
                    Text(line)
                        .font(.handwriting(15))
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 4)
                }
            }
            Spacer()
            LetterSeal(kind: page.kind)
                .frame(width: 38, height: 38)
        }
    }

    // MARK: Sections

    @ViewBuilder private var sections: some View {
        if !page.glance.isEmpty { glance }
        if let line = page.savesLine {
            Text(line)
                .font(.text(13, weight: .medium))
                .foregroundStyle(line.contains("recovered") ? Palette.goldText : Palette.ink)
                .accessibilityIdentifier("letter.saves")
        }
        if !page.journeys.isEmpty {
            section("Journey") {
                ForEach(page.journeys, id: \.self) { line in
                    HStack(spacing: 10) {
                        Text(line.label).font(.text(13, weight: .medium)).foregroundStyle(Palette.ink)
                        Text(line.text).font(.text(13)).foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
        }
        if !page.weakestWeekdays.isEmpty {
            section("A pattern", topic: .lookingBack) {
                ForEach(page.weakestWeekdays, id: \.self) { line in
                    Text(line).font(.text(13)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !page.suggestions.isEmpty {
            section("Suggestions") {
                ForEach(page.suggestions, id: \.self) { card in
                    SuggestionCardView(card: card, showsHabitName: true, accept: {
                        actions.used()
                        letters.accept(card.suggestion)
                    }, chooseOwn: {
                        actions.used()
                        switch card.suggestion.change {
                        case .target: request(.chooseTarget(card.suggestion))
                        case .schedule: request(.chooseSchedule(card.suggestion))
                        }
                    }, notNow: {
                        actions.used()
                        letters.notNow(card.suggestion)
                    })
                }
            }
        }
        if !page.notes.isEmpty {
            section(page.notesTitle) {
                ForEach(page.notes, id: \.self) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(note.label).font(.text(11.5)).foregroundStyle(Palette.inkSecondary).frame(width: 82, alignment: .leading)
                        Text(note.text).font(.handwriting(14)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        if page.kind == .monthly {
            section("Weekly consistency", topic: .lookingBack) {
                if let trend = page.trend {
                    TrendChart(points: trend)
                } else {
                    Text("Your weekly graph appears after 2 full weeks.")
                        .font(.handwriting(13))
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        if let reactivate = page.reactivate { reactivateSection(reactivate) }
        if let recap = page.recap { recapSection(recap) }
        if let obstacle = page.obstacle { obstacleSection(obstacle) }
        ForEach(page.questions, id: \.question) { question in
            questionField(question)
        }
        if let check = page.automaticity { automaticitySection(check) }
    }

    private func section<Content: View>(_ title: String, topic: ScienceTopic? = nil,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.heading(16))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let topic { info(topic) }
            }
            if let topic, expandedInfo == topic { InfoBox(entry: topic.entry).frame(maxWidth: 520) }
            content()
        }
    }

    private func info(_ topic: ScienceTopic) -> some View {
        InfoButton(topic: topic, isExpanded: Binding(
            get: { expandedInfo == topic }, set: { expandedInfo = $0 ? topic : nil }))
    }

    private var glance: some View {
        section("The \(page.kind == .monthly ? "month" : "week") at a glance") {
            VStack(alignment: .leading, spacing: 6) {
                if page.showsWeekdayLetters, let first = page.glance.first {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 120, height: 1)
                        ForEach(first.dots, id: \.day) { dot in
                            Text(dot.day.weekday.letter)
                                .font(.text(10))
                                .foregroundStyle(Palette.inkSecondary)
                                .frame(width: GlanceDotView.width)
                        }
                    }
                    .accessibilityHidden(true)
                }
                ForEach(page.glance) { row in
                    HStack(spacing: 0) {
                        Text(row.name)
                            .font(.text(13, weight: .medium))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .frame(width: 120, alignment: .leading)
                        if page.kind == .monthly {
                            // A column per week, so any number of weeks fits the page.
                            GlanceWeeks(dots: row.dots)
                        } else {
                            HStack(spacing: 0) {
                                ForEach(row.dots, id: \.day) { dot in GlanceDotView(kind: dot.kind) }
                            }
                        }
                        Text(row.percent)
                            .font(.text(12.5, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.vertical, page.kind == .monthly ? 4 : 0)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.accessibilityLabel)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("letter.glance")
        }
    }

    private func reactivateSection(_ section: ReactivateSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ReactivateSection.statement)
                .font(.handwriting(14))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(section.items) { item in
                HStack(spacing: 12) {
                    Text(item.name).font(.text(13, weight: .medium)).foregroundStyle(Palette.ink)
                    if item.state == .canReactivate {
                        Button("Reactivate") {
                            actions.used()
                            actions.reactivate(item.id)
                        }
                        .buttonStyle(PaperButtonStyle())
                        .accessibilityIdentifier("letter.reactivate")
                    } else if let line = item.stateLine {
                        Text(line).font(.text(12)).foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
            if section.atLimit {
                Text(ReactivateSection.atLimitLine)
                    .font(.text(11.5))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("letter.reactivateSection")
    }

    private func recapSection(_ recap: Day66Recap) -> some View {
        section("Your journey") {
            VStack(alignment: .leading, spacing: 8) {
                Text(recap.doneLine).font(.heading(18)).foregroundStyle(Palette.ink)
                JourneyHeatmap(weeks: recap.weeks)
                Text(recap.streakLine).font(.text(12.5)).foregroundStyle(Palette.inkSecondary)
                Text(recap.historyLine).font(.text(12.5)).foregroundStyle(Palette.ink)
                ForEach([recap.firstNote, recap.latestNote].compactMap { $0 }, id: \.self) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.label).font(.text(11.5)).foregroundStyle(Palette.inkSecondary)
                        Text("“\(note.text)”").font(.handwriting(14)).foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("letter.recap")
        }
    }

    // MARK: Questions

    private func obstacleSection(_ obstacle: ObstacleSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let previous = obstacle.previous {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ObstacleSection.previousLabel).font(.text(11.5)).foregroundStyle(Palette.inkSecondary)
                    Text("“\(previous)”").font(.handwriting(14)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ObstacleSection.howDidItGo).font(.handwriting(14, weight: .semiBold)).foregroundStyle(Palette.inkSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("letter.previousObstacle")
            }
            questionField(obstacle.question, topic: .obstacle)
            if obstacle.canKeepSame, let previous = obstacle.previous {
                Button("Keep the same") {
                    actions.used()
                    letters.setAnswer(page.id, .obstacle, previous)
                }
                .buttonStyle(LinkButtonStyle())
                .accessibilityIdentifier("letter.keepSame")
            }
        }
    }

    private func questionField(_ question: LetterQuestion, topic: ScienceTopic? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Text(question.prompt)
                    .font(.heading(15))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let topic { info(topic) }
            }
            if let topic, expandedInfo == topic { InfoBox(entry: topic.entry).frame(maxWidth: 520) }
            if page.isFiled {
                Text(question.answer.isEmpty ? "No answer." : question.answer)
                    .font(question.answer.isEmpty ? .text(12.5) : .handwriting(14.5))
                    .foregroundStyle(question.answer.isEmpty ? Palette.inkSecondary : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("letter.answer.\(question.question.rawValue)")
            } else {
                NoteTextField(stored: question.answer, save: { letters.setAnswer(page.id, question.question, $0) },
                              savesEachChange: true) { text, focus in
                    PromptedTextField(placeholder: "Optional", text: text, axis: .vertical, font: .handwriting(14.5),
                                      accessibilityLabel: question.prompt,
                                      identifier: "letter.field.\(question.question.rawValue)")
                        .lineLimit(1...5)
                        .focused(focus)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 2)
                        .overlay(alignment: .bottom) { DashedUnderline() }
                }
                .frame(maxWidth: 560)
            }
        }
    }

    private func automaticitySection(_ check: AutomaticitySection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(AutomaticitySection.question)
                        .font(.heading(17))
                        .foregroundStyle(Palette.ink)
                    info(.day66Check)
                }
                if expandedInfo == .day66Check { InfoBox(entry: ScienceTopic.day66Check.entry).frame(maxWidth: 520) }
                HStack(spacing: 6) {
                    ForEach(Automaticity.Answer.allCases, id: \.self) { answer in
                        Button(answer.label) {
                            actions.used()
                            letters.answerAutomaticity(page.id, answer)
                        }
                        .buttonStyle(ChipStyle(isSelected: check.answer == answer))
                        .disabled(!check.canAnswer)
                        .accessibilityAddTraits(check.answer == answer ? [.isSelected] : [])
                        .accessibilityIdentifier("letter.automaticity.\(answer.rawValue)")
                    }
                }
                HStack(alignment: .top, spacing: 4) {
                    Text(AutomaticitySection.hint)
                        .font(.handwriting(12.5))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    info(.automaticityQuestion)
                }
                .frame(maxWidth: 520, alignment: .leading)
                if expandedInfo == .automaticityQuestion {
                    InfoBox(entry: ScienceTopic.automaticityQuestion.entry).frame(maxWidth: 520)
                }
                if let line = check.recommendationLine {
                    Text(line)
                        .font(.text(12.5))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("letter.recommendation")
                }
            }
            if let line = check.unavailableLine {
                Text(line).font(.text(12.5)).foregroundStyle(Palette.inkSecondary)
            } else if let line = check.decisionLine {
                Text(line)
                    .font(.text(13, weight: .bold))
                    .foregroundStyle(check.decision == .graduate ? Palette.goldText : Palette.ink)
                    .accessibilityIdentifier("letter.decision")
            }
            if check.canDecide, let habit = check.habitID {
                decisionButtons(check, habit: habit)
            }
        }
    }

    private func decisionButtons(_ check: AutomaticitySection, habit: HabitID) -> some View {
        let graduateFirst = check.recommendation == .graduate
        return HStack(spacing: 8) {
            decisionButton("Graduate", primary: graduateFirst, id: "graduate") { decide(.graduate) }
            decisionButton("Keep going", primary: check.recommendation == .keepGoing, id: "keepGoing") { decide(.keepGoing) }
            switch check.primaryChange {
            case .target?:
                decisionButton("Change target", primary: false, id: "changeTarget") {
                    request(.decideTarget(letter: page.id, habit: habit))
                }
            case .schedule?:
                decisionButton("Change schedule", primary: false, id: "changeSchedule") {
                    request(.decideSchedule(letter: page.id, habit: habit))
                }
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func decisionButton(_ title: String, primary: Bool, id: String, action: @escaping () -> Void) -> some View {
        let button = Button(title) {
            actions.used()
            action()
        }
        .accessibilityIdentifier("letter.decide.\(id)")
        if primary { button.buttonStyle(PrimaryButtonStyle()) } else { button.buttonStyle(PaperButtonStyle()) }
    }

    /// A failure is the app's to report (it beeps and logs); the buttons stay.
    private func decide(_ choice: LetterChoice) {
        try? letters.decide(page.id, choice)
    }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        if page.isFiled {
            Text("Filed in your letters.")
                .font(.text(11.5))
                .foregroundStyle(Palette.inkSecondary)
        } else {
            HStack {
                Text(page.automaticity == nil ? "Answers save as you type. All of them are optional."
                                              : "Your answer saves right away. Done files this letter.")
                    .font(.text(11.5))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
                Button("Done") {
                    actions.used()
                    letters.file(page.id)
                    back()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("letter.done")
            }
        }
    }
}

/// One day in "The week at a glance": done (vermilion), recovered (gold), missed (pencil ring),
/// rest (moss dash), not scheduled (a faint dot).
struct GlanceDotView: View {
    let kind: GlanceDot.Kind
    /// The mark's diameter: 11 in a weekly letter's row, 8 in a monthly letter's grid.
    var size: CGFloat = 11
    static let width: CGFloat = 20

    var body: some View {
        ZStack {
            switch kind {
            case .done: Circle().fill(Palette.vermilion).frame(width: size, height: size)
            case .recovered: Circle().fill(Palette.gold).frame(width: size, height: size)
            case .missed: Circle().strokeBorder(Palette.pencil, lineWidth: size > 9 ? 1.4 : 1.1).frame(width: size, height: size)
            case .rest: Capsule().fill(Palette.moss).frame(width: size - 1, height: 2.5)
            case .none: Circle().fill(Palette.fieldLine).frame(width: size * 0.36, height: size * 0.36)
            }
        }
        .frame(width: size == 11 ? Self.width : size + 2, height: size == 11 ? 16 : size + 2)
    }
}

/// A monthly letter's days for one habit: a column per Sunday–Saturday week (the period is
/// always whole weeks), the same marks as the weekly dots, smaller.
struct GlanceWeeks: View {
    let dots: [GlanceDot]

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(Array(stride(from: 0, to: dots.count, by: 7)), id: \.self) { start in
                VStack(spacing: 2) {
                    ForEach(dots[start..<min(start + 7, dots.count)], id: \.day) { dot in
                        GlanceDotView(kind: dot.kind, size: 8)
                    }
                }
            }
        }
    }
}

/// The day-66 letter's mini heatmap: every day from the start to day 66, done days in
/// vermilion, a column per week.
struct JourneyHeatmap: View {
    let weeks: [[Bool?]]

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fill(week[day]))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(_ cell: Bool?) -> AnyShapeStyle {
        switch cell {
        case true?: AnyShapeStyle(Palette.vermilion)
        case false?: AnyShapeStyle(Palette.track)
        case nil: AnyShapeStyle(.clear)
        }
    }
}

/// A letter's small seal: weekly (one ring), monthly (two rings), day 66 and re-checks (the
/// brush circle).
struct LetterSeal: View {
    let kind: ReportKind
    var unread = false

    var body: some View {
        ZStack {
            Circle().fill(Palette.vermilion.opacity(unread ? 1 : 0.85))
            switch kind {
            case .weekly:
                Circle().strokeBorder(Palette.onSeal.opacity(0.85), lineWidth: 1.2).padding(5)
            case .monthly:
                Circle().strokeBorder(Palette.onSeal.opacity(0.85), lineWidth: 1.2).padding(4)
                Circle().strokeBorder(Palette.onSeal.opacity(0.85), lineWidth: 1).padding(8)
            case .day66, .recheck:
                BrushArc(progress: kind == .day66 ? 1 : 0.8)
                    .stroke(Palette.onSeal, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .padding(7)
            }
        }
        .accessibilityHidden(true)
    }
}
