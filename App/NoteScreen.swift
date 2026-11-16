import AppKit
import AppShell
import Core
import os
import Persistence
import SwiftUI
import UI

/// The collapsed note on real data: `NoteView` (UI package) fed from `AppModel`, with its
/// actions written through the repository.
struct NoteScreen: View {
    let model: Result<AppModel, DatabaseOpenError>
    let welcomeBack: WelcomeBackStore
    @Environment(NoteWindowController.self) private var note

    var body: some View {
        switch model {
        case .success(let model):
            NoteView(input: input(model), actions: actions(model))
                .environment(\.noteMaxHeight, note.availableCollapsedHeight)
        case .failure(let error):
            DatabaseErrorNote(message: error.message)
        }
    }

    private func input(_ model: AppModel) -> NoteInput {
        let details = Dictionary(model.data.habits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let habits = model.evaluations.compactMap { evaluation -> NoteHabit? in
            guard let habit = details[evaluation.id] else { return nil }
            return NoteHabit(name: habit.name, identity: habit.identity, evaluation: evaluation)
        }
        return NoteInput(today: model.today, habits: habits, notes: model.data.notes,
                         showsWelcomeBack: welcomeBack.isPending)
    }

    private func actions(_ model: AppModel) -> NoteActions {
        let repository = model.repository
        // Every action is a use of the note ("Welcome back" counts days the note was used).
        let used = { welcomeBack.used(model.today) }
        // Read `today` when the action runs, not when the view was drawn.
        return NoteActions(
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
            },
            addHabit: { request in
                used()
                do {
                    try repository.addHabit(name: request.name, identity: request.identity, kind: request.kind,
                                            target: request.target, schedule: request.schedule, today: model.today)
                } catch {
                    Self.log.error("Adding a habit failed: \(String(describing: error), privacy: .public)")
                    throw error
                }
            },
            expand: {
                used()
                note.expand()
            },
            // Phase 5 opens the Habits tab at its inactive list.
            showInactiveHabits: {
                used()
                note.expand()
            },
            dismissWelcomeBack: {
                used()
                welcomeBack.dismiss()
            },
            focusNote: { note.focusNote() },
            noteUsed: used)
    }

    /// Runs a write. The note's rules already rule out the expected failures, so one that still
    /// happens (a day change mid-click, a database error) only beeps and is logged.
    private func attempt(_ what: String, _ write: () throws -> Void) {
        do {
            try write()
        } catch {
            NSSound.beep()
            Self.log.error("The \(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// A rest for a day that's no longer today.
    struct StaleDay: Error {}

    static let log = Logger(subsystem: "com.ethanlee7102.66days", category: "note")
}

/// Shown instead of the note when the database can't be opened.
private struct DatabaseErrorNote: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("66 Days")
                .font(.heading(22))
                .foregroundStyle(Palette.ink)
            Text("Your habits couldn’t be opened. Try quitting 66 Days and opening it again. Nothing has been deleted.")
                .font(.text(12))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.text(10))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(Metrics.notePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaperBackground())
    }
}
