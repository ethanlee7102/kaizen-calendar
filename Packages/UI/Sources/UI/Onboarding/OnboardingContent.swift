import Core
import Foundation
import Observation

/// Where onboarding is (spec-onboarding.md): three pages in the notebook window. It lives for the
/// app's run, so collapsing and reopening comes back to the same page.
///
/// Decided in the Phase 7 build (user's choice): until it's finished, opening the notebook
/// returns to onboarding. If habits already exist (onboarding was left after adding one), it
/// resumes on page 2 with them listed.
@Observable
public final class OnboardingFlow {
    public enum Page: Int, CaseIterable, Hashable, Sendable {
        case welcome, firstHabit, yourNote

        /// "1 of 3"
        public var position: String { "\(rawValue + 1) of \(Self.allCases.count)" }
    }

    /// The page the user moved to; nil until they move (then it depends on the habits).
    public private(set) var chosen: Page?

    public init(page: Page? = nil) { chosen = page }

    /// The page to show: the one chosen, else page 2 if habits exist, else the welcome.
    public func page(hasHabits: Bool) -> Page { chosen ?? (hasHabits ? .firstHabit : .welcome) }

    public func go(to page: Page) { chosen = page }
}

/// Everything onboarding shows, as plain values.
nonisolated public struct OnboardingInput: Sendable {
    /// The note's input: the habits added so far and whether more can be added.
    public var note: NoteInput
    /// The current "My day ends at" hour (page 3 starts there).
    public var dayEndHour: Int

    public init(note: NoteInput, dayEndHour: Int = 0) {
        self.note = note
        self.dayEndHour = dayEndHour
    }

    /// The habits added so far, as on the habit page ("10 pages · every day").
    public var habits: [OnboardingHabit] {
        note.activeHabits.map { habit in
            OnboardingHabit(id: habit.id, name: habit.name, detail: NoteInput.detailLine(habit.history, on: note.today))
        }
    }

    public var hasHabits: Bool { !note.activeHabits.isEmpty }

    /// Page 2's Next needs at least one habit.
    public var canContinue: Bool { hasHabits }

    /// "Add another" after the first habit, until three (Fogg's start-with-three).
    public var offersAnother: Bool { (1..<Self.plenty).contains(note.activeHabits.count) }

    /// "That's plenty to start." at three or more; the link is gone.
    public var hasPlenty: Bool { note.activeHabits.count >= Self.plenty }

    public static let plenty = 3

    // MARK: Copy (spec-onboarding.md; draft-final)

    public static let welcomeLead = "This isn’t a to-do list or a goal tracker. It’s a place to build **habits**: small things you do on the same days, until they happen on their own."
    public static let welcomeResearch = "Research found new habits take about 66 days to feel automatic. So start small, show up, and if you miss a day, never miss twice."
    public static let welcomeReason = "**Everything here has a reason.** Each part of 66 Days is based on research about how habits form. Tap the small **i** anywhere to see why it’s there and where the idea comes from."

    public static let habitTitle = "A habit, not a goal."
    public static let habitBody = "Habits form by repeating the same thing on the same days. That’s why there’s no “3 times a week”: pick your days and commit to them. When you do it on those days is up to you."
    public static let startWithOne = "Start with one. You can add more later."
    public static let plentyLine = "That’s plenty to start. Add more once these feel easy."

    public static let noteTitle = "Your note"
    public static let noteBody = "Your note lives on your desktop, behind your windows. Drag it anywhere."
    public static let openAtLogin = "Open 66 Days when I log in"
    public static let dayEndLabel = "My day ends at"
    public static let dayEndHelp = "Check-offs before this time count for the day before."

    /// The info button on page 2 opens both reasons: commit to days, and any time of day
    /// (the spec's combined text, split into its two registry entries).
    public static let habitTopics: [ScienceTopic] = [.fixedDays, .flexibleTime]
}

nonisolated public struct OnboardingHabit: Hashable, Sendable, Identifiable {
    public let id: HabitID
    public let name: String
    /// "10 pages · every day"
    public let detail: String
}

/// What onboarding can do. The app wires these to the repository, the login item and the window.
public struct OnboardingActions {
    /// Adds a habit that starts today. Throws if it couldn't be saved (the form says so).
    public var addHabit: (HabitDraft.Request) throws -> Void
    /// Finish on page 3: turn on open-at-login if chosen, set the day end, fold into the note.
    public var finish: (_ openAtLogin: Bool, _ dayEndHour: Int) -> Void
    /// Skip on page 3: done, with nothing changed (open-at-login stays off).
    public var skip: () -> Void
    public var collapse: () -> Void

    public init(addHabit: @escaping (HabitDraft.Request) throws -> Void,
                finish: @escaping (Bool, Int) -> Void,
                skip: @escaping () -> Void,
                collapse: @escaping () -> Void) {
        self.addHabit = addHabit
        self.finish = finish
        self.skip = skip
        self.collapse = collapse
    }

    /// Does nothing (snapshot tests).
    public static let none = OnboardingActions(addHabit: { _ in }, finish: { _, _ in }, skip: {}, collapse: {})
}
