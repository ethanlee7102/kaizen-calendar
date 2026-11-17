import Core
import Foundation
import Observation

/// Where the notebook is: its tab, the habit shown in the Habits tab, and the Calendar's month,
/// view and filter. Shared by the app so other places can open a tab ("Bring one back", the app
/// menu's Settings…, the note's "Open Stamp book").
///
/// It reopens to the last tab used (spec-expanded-structure.md), kept on this Mac. (A waiting
/// report opens Reports instead: Phase 6.)
@Observable
public final class NotebookNavigation {
    public var tab: NotebookTab {
        didSet { if tab != oldValue { defaults?.set(tab.rawValue, forKey: Self.tabKey) } }
    }
    /// The habit shown in the Habits tab; nil picks the first one.
    public var selectedHabit: HabitID?

    /// Nil: today's month (and year).
    public var calendarMonth: DayKey?
    public var calendarYear: Int?
    public var calendarMode: CalendarMode = .month
    /// The habit the Calendar is filtered to (nil: all habits).
    public var calendarFilter: HabitID?
    public var trendSpan: TrendSpan = .twelveWeeks

    @ObservationIgnored private let defaults: UserDefaults?
    public static let tabKey = "notebook.lastTab"

    /// No `defaults`: nothing is remembered (UI tests, sample data).
    public init(defaults: UserDefaults?, tab: NotebookTab? = nil) {
        self.defaults = defaults
        self.tab = tab ?? defaults?.string(forKey: Self.tabKey).flatMap(NotebookTab.init(rawValue:)) ?? .calendar
    }

    /// The notebook opened: the Calendar starts at today's month again (decided in the Phase 5
    /// build); the tab, filter and selected habit stay.
    public func opened() {
        calendarMonth = nil
        calendarYear = nil
    }

    public func show(_ tab: NotebookTab) { self.tab = tab }

    /// The Habits tab at `habit`'s page ("Bring one back" shows the newest inactive habit).
    public func showHabit(_ habit: HabitID?) {
        tab = .habits
        if let habit { selectedHabit = habit }
    }
}

/// What the notebook can do. The app wires these to the repository and the window. Throwing
/// actions belong to forms, which show a message when saving fails; the others handle their own
/// failures (the UI's rules already prevent the expected ones).
public struct NotebookActions {
    public var dayCard: DayCardActions
    /// Adds a habit that starts today; returns its ID so the page can show it.
    public var addHabit: (HabitDraft.Request) throws -> HabitID
    public var editHabit: (HabitID, HabitEditDraft.Changes) throws -> Void
    public var changeTarget: (HabitID, Int) throws -> Void
    public var changeSchedule: (HabitID, Schedule) throws -> Void
    /// The active habits in their new order.
    public var reorder: ([HabitID]) -> Void
    /// Move to inactive (Paused).
    public var deactivate: (HabitID) -> Void
    public var reactivate: (HabitID) -> Void
    /// Delete forever (with about 10 seconds of Undo).
    public var delete: (HabitID) -> Void
    public var undoDelete: () -> Void
    public var collapse: () -> Void
    /// The Stamp book tab was opened: clears its "new" marker and the note's unlock card.
    public var visitStampBook: () -> Void
    /// Changes settings; they save instantly.
    public var updateSettings: (_ change: (inout SettingsValues) -> Void) -> Void
    public var setOpenAtLogin: (Bool) -> Void
    /// "Open Login Items" when macOS needs the user's approval.
    public var openLoginItemsSettings: () -> Void
    /// Opens a save panel for the JSON export; returns what to say afterwards ("Saved …", or why
    /// it failed), or nil if it was cancelled.
    public var exportData: () -> String?
    public var resetNotePosition: () -> Void
    /// The notebook was used (any click): counts for "Welcome back" (spec-edge-states.md).
    public var used: () -> Void

    public init(dayCard: DayCardActions,
                addHabit: @escaping (HabitDraft.Request) throws -> HabitID,
                editHabit: @escaping (HabitID, HabitEditDraft.Changes) throws -> Void,
                changeTarget: @escaping (HabitID, Int) throws -> Void,
                changeSchedule: @escaping (HabitID, Schedule) throws -> Void,
                reorder: @escaping ([HabitID]) -> Void,
                deactivate: @escaping (HabitID) -> Void,
                reactivate: @escaping (HabitID) -> Void,
                delete: @escaping (HabitID) -> Void,
                undoDelete: @escaping () -> Void,
                collapse: @escaping () -> Void,
                visitStampBook: @escaping () -> Void,
                updateSettings: @escaping ((inout SettingsValues) -> Void) -> Void,
                setOpenAtLogin: @escaping (Bool) -> Void,
                openLoginItemsSettings: @escaping () -> Void,
                exportData: @escaping () -> String?,
                resetNotePosition: @escaping () -> Void,
                used: @escaping () -> Void) {
        self.dayCard = dayCard
        self.addHabit = addHabit
        self.editHabit = editHabit
        self.changeTarget = changeTarget
        self.changeSchedule = changeSchedule
        self.reorder = reorder
        self.deactivate = deactivate
        self.reactivate = reactivate
        self.delete = delete
        self.undoDelete = undoDelete
        self.collapse = collapse
        self.visitStampBook = visitStampBook
        self.updateSettings = updateSettings
        self.setOpenAtLogin = setOpenAtLogin
        self.openLoginItemsSettings = openLoginItemsSettings
        self.exportData = exportData
        self.resetNotePosition = resetNotePosition
        self.used = used
    }

    /// Does nothing (previews and snapshot tests).
    public static let none = NotebookActions(
        dayCard: NoteActions.none.dayCard, addHabit: { _ in HabitID() }, editHabit: { _, _ in }, changeTarget: { _, _ in },
        changeSchedule: { _, _ in }, reorder: { _ in }, deactivate: { _ in }, reactivate: { _ in }, delete: { _ in },
        undoDelete: {}, collapse: {}, visitStampBook: {}, updateSettings: { _ in }, setOpenAtLogin: { _ in },
        openLoginItemsSettings: {}, exportData: { nil }, resetNotePosition: {}, used: {})
}
