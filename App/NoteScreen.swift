import AppShell
import Core
import Persistence
import SwiftUI
import UI

/// The collapsed note on real data: `NoteView` (UI package) fed from `AppModel`, with its
/// actions written through the repository.
struct NoteScreen: View {
    let model: Result<AppModel, DatabaseOpenError>
    let welcomeBack: WelcomeBackStore
    let navigation: NotebookNavigation
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
        NoteInput(today: model.today, habits: Writes.noteHabits(model), notes: model.data.notes,
                  showsWelcomeBack: welcomeBack.isPending, unlockNotice: Writes.unlockNotice(model))
    }

    private func actions(_ model: AppModel) -> NoteActions {
        // Every action is a use of the note ("Welcome back" counts days the note was used).
        let used = { welcomeBack.used(model.today) }
        let card = Writes.dayCard(model, used: used)
        return NoteActions(
            setDone: card.setDone,
            setRested: card.setRested,
            setNote: card.setNote,
            addHabit: { request in
                used()
                _ = try Writes.addHabit(request, model: model)
            },
            expand: {
                used()
                note.expand()
            },
            // "Bring one back": the Habits tab at the newest inactive habit.
            showInactiveHabits: {
                used()
                navigation.showHabit(input(model).inactiveHabits.first?.id)
                note.expand()
            },
            dismissWelcomeBack: {
                used()
                welcomeBack.dismiss()
            },
            focusNote: { note.focusNote() },
            noteUsed: used,
            openStampBook: {
                used()
                Writes.dismissUnlockNotices(model)
                navigation.show(.stampBook)
                note.expand()
            },
            dismissUnlockNotice: {
                used()
                Writes.dismissUnlockNotices(model)
            })
    }
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
