import AppKit
import AppShell
import Core
import os
import Persistence
import UI

/// Writes shared by the note and the notebook. The UI's rules already rule out the expected
/// failures, so one that still happens (a day change mid-click, a database error) only beeps and
/// is logged.
@MainActor
enum Writes {
    static let log = Logger(subsystem: "com.ethanlee7102.66days", category: "writes")

    /// Returns whether it worked.
    @discardableResult
    static func attempt(_ what: String, _ write: () throws -> Void) -> Bool {
        do {
            try write()
            return true
        } catch {
            NSSound.beep()
            log.error("The \(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// A form's write: logged, then rethrown so the form can say it failed.
    static func form<T>(_ what: String, _ write: () throws -> T) throws -> T {
        do {
            return try write()
        } catch {
            log.error("The \(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// A rest for a day that's no longer today.
    struct StaleDay: Error {}

    /// Check-offs, rests and notes from a day card (or the note's rows). `today` is read when
    /// the action runs, not when the view was drawn.
    static func dayCard(_ model: AppModel, used: @escaping () -> Void) -> DayCardActions {
        let repository = model.repository
        return DayCardActions(
            setDone: { habit, day, done, changeAnyway in
                used()
                attempt("check-off") {
                    try repository.setDone(done, habit: habit, on: day, today: model.today, changeAnyway: changeAnyway)
                }
            },
            setRested: { habit, day, rested in
                used()
                attempt("rest") {
                    // Rest is only ever for today: a card left open across midnight can't rest
                    // a day it isn't showing (Phase 4 review).
                    guard day == model.today else { throw StaleDay() }
                    try repository.setRested(rested, habit: habit, today: model.today)
                }
            },
            setNote: { day, text, changeAnyway in
                used()
                attempt("note") { try repository.setNote(text, on: day, today: model.today, changeAnyway: changeAnyway) }
            })
    }

    static func addHabit(_ request: HabitDraft.Request, model: AppModel) throws -> HabitID {
        try form("new habit") {
            try model.repository.addHabit(name: request.name, identity: request.identity, kind: request.kind,
                                          target: request.target, schedule: request.schedule, today: model.today)
        }
    }

    /// Every readable habit, active and inactive, in list order, as the note and notebook see it.
    static func noteHabits(_ model: AppModel) -> [NoteHabit] {
        let details = Dictionary(model.data.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return model.evaluations.compactMap { evaluation in
            details[evaluation.id].map { NoteHabit(name: $0.name, identity: $0.identity, evaluation: evaluation) }
        }
    }

    /// The unlock card on the note: the oldest unlock whose card wasn't dismissed yet.
    static func unlockNotice(_ model: AppModel) -> UnlockNotice? {
        model.data.unlocks.first { !$0.noticeDismissed }.map { UnlockNotice(unlock: $0.unlock) }
    }

    // MARK: Letters and suggestions

    /// Every letter, newest first, as the notebook sees it.
    static func letters(_ model: AppModel) -> [LetterInput] {
        model.reports.map(letter)
    }

    static func letter(_ report: StoredReport) -> LetterInput {
        let snapshot = try? report.snapshot.get()
        return LetterInput(id: report.id, kind: report.kind, deliveryDay: report.deliveryDay, period: report.period,
                           isUnread: report.isUnread, isFiled: !report.isNew, content: snapshot?.content,
                           habits: snapshot?.habits ?? [:], answers: report.answers)
    }

    /// The envelope on the note: the newest letter that's new and unopened.
    static func envelope(_ model: AppModel) -> NoteEnvelope? {
        model.envelope.map { NoteEnvelope(letter: letter($0)) }
    }

    /// Today's suggestion per active habit (spec-suggestions.md).
    static func suggestions(_ model: AppModel) -> [HabitID: Suggestion] {
        var suggestions: [HabitID: Suggestion] = [:]
        for evaluation in model.activeEvaluations {
            suggestions[evaluation.id] = Suggestions.suggestion(for: evaluation, dismissals: model.data.dismissals[evaluation.id] ?? [])
        }
        return suggestions
    }

    /// Delivers what's due now (launch, wake, the report time, any change). Safe to call often.
    /// It runs in the background of every change, so a failure is only logged: a beep would
    /// follow every check-off with no visible cause (Phase 6 review).
    static func deliverReports(_ model: AppModel) {
        do {
            try model.deliverDueReports()
        } catch {
            log.error("Report delivery failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Suggestion cards and letters, written through the repository.
    static func letterActions(_ model: AppModel) -> LetterActions {
        let repository = model.repository
        return LetterActions(
            accept: { suggestion in
                attempt("accept suggestion") { try repository.acceptSuggestion(suggestion, today: model.today) }
            },
            notNow: { suggestion in
                attempt("not now") { try repository.dismissSuggestion(suggestion.kind, habit: suggestion.habitID, today: model.today) }
            },
            opened: { id in attempt("open letter") { try repository.markReportOpened(id, at: Date()) } },
            file: { id in attempt("file letter") { try repository.fileReport(id, at: Date()) } },
            setAnswer: { id, question, text in
                attempt("letter answer") { try repository.setAnswer(text, to: question, report: id) }
            },
            answerAutomaticity: { id, answer in
                attempt("automaticity answer") { try repository.answerAutomaticity(answer, report: id, today: model.today) }
            },
            decide: { id, choice in
                do {
                    try form("letter decision") { try repository.decide(choice, report: id, today: model.today) }
                } catch {
                    NSSound.beep()
                    throw error
                }
            })
    }

    /// × on a milestone card: it never comes back.
    static func dismissMilestone(_ notice: MilestoneNotice, model: AppModel) {
        attempt("milestone card") {
            for milestone in notice.milestones { try model.repository.markMilestoneSeen(milestone, habit: notice.habitID) }
        }
    }

    /// The unlock card was acted on (dismissed, or the Stamp book was opened): it shows once.
    static func dismissUnlockNotices(_ model: AppModel) {
        attempt("unlock card") {
            for state in model.data.unlocks where !state.noticeDismissed {
                try model.repository.dismissUnlockNotice(state.unlock, at: Date())
            }
        }
    }
}

// MARK: - Settings

extension SettingsValues {
    /// The stored settings as the Settings tab shows them.
    init(_ settings: AppSettings, appearanceUnlocked: Bool, openAtLogin: LoginState, today: DayKey) {
        self.init()
        dayEndHour = settings.dayEnd.chosenHour
        dayEndStartsTomorrow = settings.dayEnd.startsLater(today: today)
        reportWeekday = settings.report.weekday
        reportHour = settings.report.hour
        reportMinute = settings.report.minute
        reminderEnabled = settings.reminderEnabled
        reminderHour = settings.reminderHour
        reminderMinute = settings.reminderMinute
        soundsEnabled = settings.soundsEnabled
        reduceMotion = switch settings.reduceMotion {
        case .matchSystem: .matchSystem
        case .on: .on
        case .off: .off
        }
        appearance = switch settings.appearance {
        case .light: .light
        case .dark: .dark
        case .matchSystem: .matchSystem
        }
        self.appearanceUnlocked = appearanceUnlocked
        self.openAtLogin = openAtLogin
    }

    /// Writes the editable values back. The day-end hour isn't one of them: it goes through
    /// `Repository.setDayEndHour`, which makes it start tomorrow.
    func apply(to settings: inout AppSettings) {
        settings.report = ReportSettings(weekday: reportWeekday, hour: reportHour, minute: reportMinute)
        settings.reminderEnabled = reminderEnabled
        settings.reminderHour = reminderHour
        settings.reminderMinute = reminderMinute
        settings.soundsEnabled = soundsEnabled
        settings.reduceMotion = switch reduceMotion {
        case .matchSystem: .matchSystem
        case .on: .on
        case .off: .off
        }
        settings.appearance = switch appearance {
        case .light: .light
        case .dark: .dark
        case .matchSystem: .matchSystem
        }
    }
}

extension AppModel {
    /// Dark mode was found in the Stamp book (the app is light only before that).
    var darkModeUnlocked: Bool { data.unlocks.contains { $0.unlock == .darkMode } }

    /// The appearance the app uses now: the setting once Dark mode is unlocked, else Light
    /// (spec-visual-identity.md, spec-stamp-book.md).
    var effectiveAppearance: AppSettings.Appearance { darkModeUnlocked ? data.settings.appearance : .light }
}

/// "Open at login" (SMAppService), or a stand-in for UI tests so they never register the app.
@MainActor
final class LoginItemSwitch {
    private let isFake: Bool
    private var fakeOn = false

    init(fake: Bool) { isFake = fake }

    var state: SettingsValues.LoginState {
        if isFake { return fakeOn ? .on : .off }
        return switch LoginItem.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        case .disabled: .off
        }
    }

    func set(_ on: Bool) {
        if isFake {
            fakeOn = on
            return
        }
        Writes.attempt("open at login") { try LoginItem.setEnabled(on) }
        if on, LoginItem.status == .requiresApproval { LoginItem.openSystemSettings() }
    }
}
