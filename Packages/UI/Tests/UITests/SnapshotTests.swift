#if os(macOS)
import AppKit
import Core
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Pictures of the note and its marks in light and dark (build plan Phase 4). A failure means
/// the drawing changed: look at the diff, and if the change is intended, delete the reference
/// image and run again to record the new one.
///
/// Rendered at 2× in an offscreen window that always reports a 2× backing scale, so the result
/// doesn't depend on the screen the window lands on (CI's is 1×; a Retina laptop's is 2×). The
/// Phase 4 review found a plain window rasterizes at its screen's scale; a probe on 1× and 2×
/// screens gave identical bytes with `FixedScaleWindow`. A small tolerance absorbs font-smoothing
/// differences between Macs.
@Suite(.serialized) struct SnapshotTests {
    init() throws { try FontRegistry.registerAll() }

    // MARK: Marks

    @Test(arguments: [ColorScheme.light, .dark])
    func dayMarks(scheme: ColorScheme) {
        let marks: [(DayCellMark, Bool)] = [
            (.fullSeal, false), (.slicedSeal(inked: [true, false, true]), false), (.slicedSeal(inked: [false, false]), true),
            (.pencilCircle, false), (.restDash, false), (.goldSeam, false), (.todayPending, true), (.faint, false),
            (.future, false),
        ]
        let view = HStack(spacing: 0) {
            ForEach(marks.indices, id: \.self) { index in
                DayCellView(day: index + 3, mark: marks[index].0, isToday: marks[index].1).frame(width: 38)
            }
        }
        .padding(6)
        .background(PaperBackground(cornerRadius: 0))
        assertImage(view, width: 38 * 9 + 12, scheme: scheme, named: "marks")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func leavesAndJourney(scheme: ColorScheme) {
        let view = HStack(spacing: 10) {
            LeafMark(state: .checked)
            LeafMark(state: .unchecked)
            LeafMark(state: .rested)
            LeafMark(state: .dimmed)
            JourneyBadge(journey: Journey(doneDays: []))
            JourneyBadge(journey: Journey(doneDays: (0..<20).map { d("2026-01-01").adding(days: $0) }))
            JourneyBadge(journey: Journey(doneDays: (0..<70).map { d("2026-01-01").adding(days: $0) }))
        }
        .padding(8)
        .background(PaperBackground(cornerRadius: 0))
        assertImage(view, width: 340, scheme: scheme, named: "leaves")
    }

    // MARK: The note

    @Test(arguments: [ColorScheme.light, .dark])
    func note(scheme: ColorScheme) {
        assertImage(NoteView(input: Fixture.month(), actions: .none), scheme: scheme, named: "note")
    }

    @Test func notScheduledTodayUnfolded() {
        assertImage(NoteView(input: Fixture.month(), actions: .none, showsUnscheduled: true), scheme: .light, named: "unscheduledOpen")
    }

    @Test func noteFilteredToOneHabit() {
        let input = Fixture.month()
        assertImage(NoteView(input: input, actions: .none, filter: input.habits[0].id), scheme: .light, named: "filtered")
    }

    @Test func noteWhenAllDoneShowsTheDailyNoteLine() {
        let floss = noteHabit("Floss", created: "2026-11-02", done: days("2026-11-02", "2026-11-14", skipping: ["2026-11-06"]),
                              today: Fixture.today)
        let walk = noteHabit("Walk", kind: .amount(unit: "minutes"), target: 20, created: "2026-11-09",
                             done: days("2026-11-09", "2026-11-13"), rested: [Fixture.today], today: Fixture.today)
        let input = NoteInput(today: Fixture.today, habits: [floss, walk], showsWelcomeBack: true)
        assertImage(NoteView(input: input, actions: .none), scheme: .light, named: "allDone")
    }

    @Test func noteEdgeStates() {
        let gym = noteHabit("Gym", schedule: Schedule([.monday, .thursday])!, created: "2026-11-02", today: Fixture.today)
        assertImage(NoteView(input: NoteInput(today: Fixture.today, habits: [gym]), actions: .none),
                    scheme: .light, named: "nothingScheduled")
        let paused = noteHabit("Run", created: "2026-11-01", done: days("2026-11-01", "2026-11-05"), deactivated: "2026-11-06",
                               today: Fixture.today)
        assertImage(NoteView(input: NoteInput(today: Fixture.today, habits: [paused]), actions: .none),
                    scheme: .light, named: "noHabits")
    }

    @Test func noteAtFiveHabits() {
        let names = ["Read", "Walk", "Floss", "Stretch", "Journal"]
        let habits = names.map { noteHabit($0, created: "2026-11-10", done: days("2026-11-10", "2026-11-13"), today: Fixture.today) }
        assertImage(NoteView(input: NoteInput(today: Fixture.today, habits: habits), actions: .none),
                    scheme: .light, named: "fiveHabits")
    }

    // MARK: Cards

    @Test(arguments: [ColorScheme.light, .dark])
    func dayCardToday(scheme: ColorScheme) {
        assertImage(NoteView(input: Fixture.month(), actions: .none, openDay: Fixture.today), scheme: scheme, named: "dayCardToday")
    }

    @Test func dayCardReadOnly() {
        assertImage(NoteView(input: Fixture.month(), actions: .none, openDay: d("2026-11-04")), scheme: .light,
                    named: "dayCardReadOnly")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func newHabitForm(scheme: ColorScheme) {
        // Three active habits: adding a 4th shows Fogg's nudge.
        assertImage(NoteView(input: Fixture.month(), actions: .none, isFormOpen: true), scheme: scheme, named: "form")
    }

    @Test func noteWithTheUnlockCard() {
        var input = Fixture.month()
        input.unlockNotice = UnlockNotice(unlock: .darkMode)
        assertImage(NoteView(input: input, actions: .none), scheme: .light, named: "unlockNotice")
    }

    // MARK: The notebook (Phase 5)

    private func notebook(_ tab: NotebookTab, input: NotebookInput = NotebookInput(note: Fixture.month()),
                          sheet: NotebookSheet? = nil, configure: (NotebookNavigation) -> Void = { _ in }) -> some View {
        let navigation = NotebookNavigation(defaults: nil, tab: tab)
        configure(navigation)
        return NotebookView(input: input, actions: .none, navigation: navigation, isOpen: false, sheet: sheet)
    }

    private func assertNotebook(_ view: some View, scheme: ColorScheme = .light, named name: String,
                                line: UInt = #line) {
        assertImage(view, width: Metrics.expandedSize.width, height: Metrics.expandedSize.height, scheme: scheme,
                    named: name, line: line)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func notebookCalendarMonth(scheme: ColorScheme) {
        assertNotebook(notebook(.calendar), scheme: scheme, named: "notebookCalendar")
    }

    @Test func notebookCalendarFilteredAndYear() {
        let input = NotebookInput(note: Fixture.month())
        assertNotebook(notebook(.calendar, input: input) { $0.calendarFilter = input.note.habits[0].id },
                       named: "notebookCalendarFiltered")
        assertNotebook(notebook(.calendar) { $0.calendarMode = .year }, named: "notebookYear")
    }

    @Test func notebookDayCard() {
        assertNotebook(notebook(.calendar, sheet: .dayCard(Fixture.today)), named: "notebookDayCard")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func notebookHabitPage(scheme: ColorScheme) {
        assertNotebook(notebook(.habits), scheme: scheme, named: "notebookHabit")
    }

    @Test func notebookInactiveHabitAndDelete() {
        let run = noteHabit("Run", created: "2026-10-20", done: days("2026-10-20", "2026-11-05"), deactivated: "2026-11-06",
                            today: Fixture.today)
        var note = Fixture.month()
        note.habits.append(run)
        let input = NotebookInput(note: note, pendingDeletion: "Stretch")
        assertNotebook(notebook(.habits, input: input) { $0.selectedHabit = run.id }, named: "notebookInactive")
        assertNotebook(notebook(.habits, input: NotebookInput(note: Fixture.month()), sheet: .delete(Fixture.month().habits[0].id)),
                       named: "notebookDelete")
    }

    @Test func notebookStampBook() {
        assertNotebook(notebook(.stampBook), named: "notebookStampBookEmpty")
        var settings = SettingsValues()
        settings.appearanceUnlocked = true
        let input = NotebookInput(note: Fixture.month(), stampDays: 12, unlocks: [UnlockInfo(unlock: .darkMode, isNew: true)],
                                  settings: settings)
        assertNotebook(notebook(.stampBook, input: input), named: "notebookStampBook")
    }

    @Test func notebookSettings() {
        assertNotebook(notebook(.settings), named: "notebookSettings")
    }

    // MARK: Rendering

    private func assertImage(_ view: some View, width: CGFloat = Metrics.noteWidth, height: CGFloat? = nil,
                             scheme: ColorScheme, named name: String,
                             fileID: StaticString = #fileID, file: StaticString = #filePath, testName: String = #function,
                             line: UInt = #line, column: UInt = #column) {
        let image = render(view, width: width, height: height, scheme: scheme)
        assertSnapshot(of: image, as: .image(precision: 0.995, perceptualPrecision: 0.98),
                       named: "\(name)-\(scheme == .dark ? "dark" : "light")",
                       fileID: fileID, file: file, testName: "snapshot", line: line, column: column)
    }

    /// `height`: a fixed size (the notebook); otherwise the view's own height (the note).
    private func render(_ view: some View, width: CGFloat, height: CGFloat? = nil, scheme: ColorScheme) -> NSImage {
        let host = NSHostingView(rootView: Group {
            if let height {
                view.frame(width: width, height: height)
            } else {
                view.frame(width: width).fixedSize(horizontal: false, vertical: true)
            }
        }
        .environment(\.colorScheme, scheme))
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let window = FixedScaleWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 100),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        // Lay out until the size settles: some heights come from onGeometryChange, which needs
        // another update pass (a fixed wait could be too short on a busy CI machine).
        var size = CGSize.zero
        for _ in 0..<50 {
            let fitting = host.fittingSize
            if fitting == size { break }
            size = fitting
            window.setContentSize(size)
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }

        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                   pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                   bitsPerPixel: 0)!
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}

/// Always reports a 2× backing scale, whatever screen it's on.
private final class FixedScaleWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
}
#endif
