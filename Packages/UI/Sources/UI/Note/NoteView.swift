import Core
import SwiftUI

/// What the note can do. The app wires these to the repository; each one handles its own
/// failures (the UI rules already prevent the expected ones).
public struct NoteActions {
    /// Check off (true) or uncheck a habit on a day. `changeAnyway`: the user confirmed editing
    /// a day older than the 2-day window.
    public var setDone: (_ habit: HabitID, _ day: DayKey, _ done: Bool, _ changeAnyway: Bool) -> Void
    /// Rest, or undo it, on `day` (always today: the app rejects any other day, so a card that
    /// went stale across midnight can't rest the wrong day).
    public var setRested: (_ habit: HabitID, _ day: DayKey, _ rested: Bool) -> Void
    /// Save a day's note (blank removes it).
    public var setNote: (_ day: DayKey, _ text: String, _ changeAnyway: Bool) -> Void
    /// Add a habit that starts today. Throws if it couldn't be saved.
    public var addHabit: (_ request: HabitDraft.Request) throws -> Void
    /// Open the notebook.
    public var expand: () -> Void
    /// "Bring one back": the inactive habits in the Habits tab.
    public var showInactiveHabits: () -> Void
    /// Close the "Welcome back" note.
    public var dismissWelcomeBack: () -> Void
    /// The note opened something you type into or close with Esc: take keyboard input without
    /// activating the app (Phase 4 review).
    public var focusNote: () -> Void
    /// The note was used (a click that changes nothing stored, such as opening a day card): it
    /// counts as opening the app for "Welcome back".
    public var noteUsed: () -> Void
    /// "Open Stamp book" on the unlock card: the notebook at the Stamp book tab.
    public var openStampBook: () -> Void
    /// × on the unlock card (it shows once).
    public var dismissUnlockNotice: () -> Void
    /// The envelope: the notebook opens straight into that letter (spec-reports.md).
    public var openLetter: (UUID) -> Void = { _ in }
    /// × on a milestone card: these milestones never show again.
    public var dismissMilestone: (MilestoneNotice) -> Void = { _ in }

    public init(setDone: @escaping (HabitID, DayKey, Bool, Bool) -> Void,
                setRested: @escaping (HabitID, DayKey, Bool) -> Void,
                setNote: @escaping (DayKey, String, Bool) -> Void,
                addHabit: @escaping (HabitDraft.Request) throws -> Void,
                expand: @escaping () -> Void,
                showInactiveHabits: @escaping () -> Void,
                dismissWelcomeBack: @escaping () -> Void,
                focusNote: @escaping () -> Void = {},
                noteUsed: @escaping () -> Void = {},
                openStampBook: @escaping () -> Void = {},
                dismissUnlockNotice: @escaping () -> Void = {}) {
        self.setDone = setDone
        self.setRested = setRested
        self.setNote = setNote
        self.addHabit = addHabit
        self.expand = expand
        self.showInactiveHabits = showInactiveHabits
        self.dismissWelcomeBack = dismissWelcomeBack
        self.focusNote = focusNote
        self.noteUsed = noteUsed
        self.openStampBook = openStampBook
        self.dismissUnlockNotice = dismissUnlockNotice
    }

    /// What a day card can do.
    public var dayCard: DayCardActions {
        DayCardActions(setDone: setDone, setRested: setRested, setNote: setNote)
    }

    /// Does nothing (previews and snapshot tests).
    public static let none = NoteActions(setDone: { _, _, _, _ in }, setRested: { _, _, _ in }, setNote: { _, _, _ in },
                                         addHabit: { _ in }, expand: {}, showInactiveHabits: {}, dismissWelcomeBack: {})
}

/// What a day card can do (on the note and in the notebook's Calendar tab).
public struct DayCardActions {
    /// Check off (true) or uncheck a habit on a day; `changeAnyway` after "Change anyway".
    public var setDone: (_ habit: HabitID, _ day: DayKey, _ done: Bool, _ changeAnyway: Bool) -> Void
    /// Rest, or undo it (always today).
    public var setRested: (_ habit: HabitID, _ day: DayKey, _ rested: Bool) -> Void
    /// Save a day's note (blank removes it).
    public var setNote: (_ day: DayKey, _ text: String, _ changeAnyway: Bool) -> Void

    public init(setDone: @escaping (HabitID, DayKey, Bool, Bool) -> Void,
                setRested: @escaping (HabitID, DayKey, Bool) -> Void,
                setNote: @escaping (DayKey, String, Bool) -> Void) {
        self.setDone = setDone
        self.setRested = setRested
        self.setNote = setNote
    }
}

public extension EnvironmentValues {
    /// The tallest the note can be on its screen; taller cards scroll inside themselves.
    @Entry var noteMaxHeight: CGFloat = .infinity
}

/// The collapsed sticky note (spec-collapsed-note.md §2): month grid, today's habits, and the
/// day card and new-habit form over it.
public struct NoteView: View {
    public let input: NoteInput
    public let actions: NoteActions

    /// The habit the grid is filtered to (tap a habit's name).
    @State private var filter: HabitID?
    @State private var openDay: DayKey?
    @State private var isFormOpen = false
    @State private var showsWhyFive = false
    /// The "Not scheduled today" section is open. Folded by default and again each new day.
    @State private var showsUnscheduled = false

    public init(input: NoteInput, actions: NoteActions) {
        self.input = input
        self.actions = actions
    }

    /// Initial UI state, for snapshot tests and UI-test launches.
    init(input: NoteInput, actions: NoteActions, filter: HabitID? = nil, openDay: DayKey? = nil, isFormOpen: Bool = false,
         showsUnscheduled: Bool = false) {
        self.input = input
        self.actions = actions
        _filter = State(initialValue: filter)
        _openDay = State(initialValue: openDay)
        _isFormOpen = State(initialValue: isFormOpen)
        _showsUnscheduled = State(initialValue: showsUnscheduled)
    }

    /// The filter, unless its habit is gone or no longer on the note.
    private var activeFilter: HabitID? {
        guard let filter, input.activeHabits.contains(where: { $0.id == filter }) else { return nil }
        return filter
    }

    private var hasCard: Bool { openDay != nil || isFormOpen }

    public var body: some View {
        ZStack(alignment: .top) {
            content
                // Disabled, not only unclickable: a field behind the card loses focus, so typing
                // and Tab can't reach it (Phase 4 review).
                .disabled(hasCard)
                .allowsHitTesting(!hasCard)
                .accessibilityHidden(hasCard)
                .overlay {
                    if hasCard {
                        RoundedRectangle(cornerRadius: Metrics.noteCornerRadius)
                            .fill(Palette.paper.opacity(0.55))
                            .transition(.opacity)
                    }
                }
            if let day = openDay {
                DayCardView(card: input.dayCard(for: day), actions: actions.dayCard) { openDay = nil }
                    .padding(10)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .id(day)
            } else if isFormOpen {
                HabitFormView(addHabitState: input.addHabitState, add: actions.addHabit) { isFormOpen = false }
                    .padding(10)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: hasCard)
        .background(PaperBackground())
        .onChange(of: input.today) {
            openDay = openDay.flatMap { $0 > input.today ? nil : $0 }
            showsUnscheduled = false // a new day: its own unscheduled habits, folded again
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            FilterLine(filteredName: activeFilter.flatMap { input.habit($0)?.name }) {
                actions.noteUsed()
                filter = nil
            }
            MonthGridView(input: input, filter: activeFilter, open: openCard)
            Rectangle().fill(Palette.rule).frame(height: 1).padding(.horizontal, -2)
            todaySection
            if input.showsWelcomeBack { WelcomeBackNote(dismiss: actions.dismissWelcomeBack) }
            if let notice = input.unlockNotice {
                UnlockNoticeCard(notice: notice, open: actions.openStampBook, dismiss: actions.dismissUnlockNotice)
            }
            if let milestone = input.milestoneNotice {
                MilestoneCard(notice: milestone) { actions.dismissMilestone(milestone) }
            }
            if input.activeHabits.isEmpty {
                noHabits
            } else {
                VStack(spacing: 2) {
                    ForEach(input.scheduledRows) { row in habitRow(row) }
                }
                let unscheduled = input.unscheduledRows
                if !unscheduled.isEmpty {
                    UnscheduledSection(count: unscheduled.count, isOpen: Binding(get: { showsUnscheduled }, set: {
                        actions.noteUsed()
                        showsUnscheduled = $0
                    })) {
                        ForEach(unscheduled) { row in habitRow(row) }
                    }
                }
                if input.showsDailyNoteLine {
                    DailyNoteLine(day: input.today, stored: input.notes[input.today] ?? "") {
                        actions.setNote(input.today, $0, false)
                    }
                    .transition(.opacity.animation(.easeIn(duration: 0.4).delay(0.5)))
                }
                addHabit
            }
        }
        .padding(Metrics.notePadding)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(input.monthTitle)
                .font(.heading(22))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("note.month")
            Text(input.yearTitle)
                .font(.text(11))
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: 0)
            if let envelope = input.envelope {
                Button { actions.openLetter(envelope.letterID) } label: {
                    EnvelopeIcon()
                        .frame(width: 22, height: 16)
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(envelope.accessibilityLabel)
                .accessibilityIdentifier("note.envelope")
                .help(envelope.title)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                .transition(.opacity)
            }
            Button(action: actions.expand) {
                ExpandIcon()
                    .stroke(Palette.inkSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Expand")
            .accessibilityIdentifier("note.expand")
            .help("Expand")
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        }
    }

    private var todaySection: some View {
        let line = input.todayLine
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.heading(15))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                Text(line.summary)
                    .font(.text(11))
                    .foregroundStyle(Palette.inkSecondary)
            }
            // An explicit label: a merged (.combine) one reads as empty to XCUITest on macOS.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today, \(line.summary)")
            .accessibilityIdentifier("note.today")
            if line.nothingScheduled {
                Text("Nothing scheduled today.")
                    .font(.handwriting(12.5))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private var noHabits: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No habits yet. Start with one small thing.")
                .font(.handwriting(13))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                addLink
                if input.hasInactiveHabits {
                    Button("Bring one back", action: actions.showInactiveHabits)
                        .buttonStyle(LinkButtonStyle())
                }
            }
        }
    }

    @ViewBuilder private var addHabit: some View {
        if input.addHabitState == .atLimit {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text("You’re at 5 habits. Graduate one that feels automatic to make room.")
                        .font(.text(11.5))
                        .lineSpacing(2)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    InfoButton(topic: .whyFive, isExpanded: Binding(get: { showsWhyFive }, set: {
                        actions.noteUsed()
                        showsWhyFive = $0
                    }))
                }
                if showsWhyFive { InfoBox(entry: ScienceTopic.whyFive.entry) }
            }
        } else {
            addLink
        }
    }

    private func habitRow(_ row: NoteRow) -> some View {
        HabitRowView(row: row, isSelected: activeFilter == row.id,
                     toggle: { actions.setDone(row.id, input.today, !row.isDone, false) },
                     select: {
                         actions.noteUsed()
                         filter = activeFilter == row.id ? nil : row.id
                     })
    }

    private func openCard(_ day: DayKey) {
        actions.noteUsed()
        actions.focusNote()
        openDay = day
    }

    private var addLink: some View {
        Button("+ Add habit") {
            actions.noteUsed()
            actions.focusNote()
            isFormOpen = true
        }
            .buttonStyle(LinkButtonStyle())
            .accessibilityIdentifier("note.addHabit")
    }
}

/// The ↗↙ expand arrows (from the mockup, 16×16).
nonisolated struct ExpandIcon: Shape {
    static let svg = SVGPath("M9.5 2.5h4v4M13.5 2.5 9 7M6.5 13.5h-4v-4M2.5 13.5 7 9")
    func path(in rect: CGRect) -> Path { Self.svg.path(in: rect, viewBox: CGSize(width: 16, height: 16)) }
}

/// "All habits · tap a habit's name…" or "Showing Read only · Show all habits" (22 points tall).
private struct FilterLine: View {
    let filteredName: String?
    let showAll: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let filteredName {
                Text("Showing \(Text(filteredName).bold()) only")
                    .font(.text(11.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Button("Show all habits", action: showAll)
                    .buttonStyle(LinkButtonStyle(size: 11.5))
            } else {
                Text("All habits · tap a habit’s name to see just its days")
                    .font(.handwriting(11.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(height: Metrics.filterLineHeight)
    }
}

/// Habits not scheduled today, under today's: one folded line, "Not scheduled today (2) ▸",
/// that opens to their rows (user's request, 2026-11-15).
private struct UnscheduledSection<Rows: View>: View {
    let count: Int
    @Binding var isOpen: Bool
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text("Not scheduled today (\(count))")
                        .font(.text(11.5, weight: .medium))
                }
                .foregroundStyle(Palette.inkSecondary)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not scheduled today, \(count) \(count == 1 ? "habit" : "habits")")
            .accessibilityValue(isOpen ? "expanded" : "collapsed")
            .accessibilityHint(isOpen ? "Hides them" : "Shows them")
            .accessibilityIdentifier("note.unscheduled")
            if isOpen {
                rows.transition(.opacity)
            }
        }
    }
}

/// "Welcome back. Streaks start over; your journey doesn't." (spec-edge-states.md), once.
private struct WelcomeBackNote: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("Welcome back. Streaks start over; your journey doesn’t.")
                .font(.handwriting(12.5))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.inkSecondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// "You found something: Dark mode." with Open Stamp book and ×, once (spec-stamp-book.md).
private struct UnlockNoticeCard: View {
    let notice: UnlockNotice
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.text(12.5, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(notice.message)
                    .font(.text(11.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Stamp book", action: open)
                    .buttonStyle(LinkButtonStyle(size: 11.5))
                    .accessibilityIdentifier("note.openStampBook")
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.inkSecondary)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("note.dismissUnlock")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.vermilion.opacity(0.35)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note.unlockNotice")
    }
}

/// "Day 100 · Read. Triple digits." (spec-celebrations.md): a small paper card with an info
/// button; × dismisses it for good.
private struct MilestoneCard: View {
    let notice: MilestoneNotice
    let dismiss: () -> Void
    @State private var showsInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.title)
                        .font(.heading(14))
                        .foregroundStyle(Palette.ink)
                    Text(notice.line)
                        .font(.handwriting(12.5))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                InfoButton(topic: notice.topic, isExpanded: $showsInfo)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier("note.dismissMilestone")
            }
            if showsInfo { InfoBox(entry: notice.topic.entry) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.gold.opacity(0.5)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note.milestone")
    }
}

/// The sealed envelope in the note's header: paper with a flap and a vermilion seal.
struct EnvelopeIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Palette.raisedPaper)
            RoundedRectangle(cornerRadius: 2.5)
                .strokeBorder(Palette.inkSecondary, lineWidth: 1.2)
            Flap()
                .stroke(Palette.inkSecondary, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            Circle()
                .fill(Palette.vermilion)
                .frame(width: 7, height: 7)
                .offset(y: 1)
        }
        .accessibilityHidden(true)
    }

    private struct Flap: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX + 1, y: rect.minY + 1))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + 1))
                path.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + 1))
            }
        }
    }
}

/// The optional daily note under the habits, once everything today is done (§7). Saves as you
/// type (after a short pause) and when you press Return or leave the field.
struct DailyNoteLine: View {
    let day: DayKey
    let stored: String
    let save: (String) -> Void

    var body: some View {
        NoteTextField(stored: stored, save: save) { text, focus in
            PromptedTextField(placeholder: "One thing to do 1% better tomorrow…", text: text, font: .handwriting(13.5),
                              accessibilityLabel: "Daily note: one thing to do 1% better tomorrow",
                              identifier: "note.dailyNote")
                .focused(focus)
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) { DashedUnderline() }
        }
        .id(day)
    }
}

/// The text a note field shows and when it saves (pure, unit-tested). Only text typed since the
/// last save is ever saved, and while nothing is waiting to be saved the field follows the stored
/// note, even if it's focused. Before the Phase 4 review, a field that kept focus after a save
/// could later write its old text over a newer note from elsewhere.
nonisolated struct NoteDraft: Hashable, Sendable {
    /// Local text while editing; nil shows the stored note.
    private(set) var text: String?
    /// Typed since the last save.
    private(set) var isDirty = false

    func display(stored: String) -> String { text ?? stored }

    mutating func typed(_ newText: String) {
        text = newText
        isDirty = true
    }

    /// The text to save now, if any. Clears the dirty flag.
    mutating func commit(stored: String) -> String? {
        guard isDirty, let text else { return nil }
        isDirty = false
        return text == stored ? nil : text
    }

    /// The stored note changed (a save landed, or another place edited it).
    mutating func storedChanged() {
        if !isDirty { text = nil }
    }
}

/// Edits a stored note: keeps its own text while you type (so saves never move the cursor),
/// saves after a pause, on Return and when focus leaves (`NoteDraft` decides what).
struct NoteTextField<Field: View>: View {
    let stored: String
    let save: (String) -> Void
    /// Save every change at once instead of after a pause (letters: Done can be clicked right
    /// after typing, and a button click doesn't end the field's editing: Phase 6 review).
    var savesEachChange = false
    @ViewBuilder let field: (Binding<String>, FocusState<Bool>.Binding) -> Field

    @State private var draft = NoteDraft()
    @FocusState private var isFocused: Bool
    @State private var pending: Task<Void, Never>?

    var body: some View {
        field(Binding(get: { draft.display(stored: stored) }, set: { newValue in
            draft.typed(newValue)
            if savesEachChange { commit() } else { scheduleSave() }
        }), $isFocused)
        .onSubmit(commit)
        .onChange(of: isFocused) { if !isFocused { commit() } }
        .onDisappear(perform: commit)
        .onChange(of: stored) { draft.storedChanged() }
    }

    private func scheduleSave() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        pending?.cancel()
        pending = nil
        if let text = draft.commit(stored: stored) { save(text) }
    }
}
