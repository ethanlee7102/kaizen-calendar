import AppKit
import AppShell
import Core
import Observation
import Persistence
import SwiftUI
import UI
import UniformTypeIdentifiers

/// The notebook on real data: `NotebookView` (UI package) fed from `AppModel`, with its actions
/// written through the repository.
struct NotebookScreen: View {
    let model: Result<AppModel, DatabaseOpenError>
    let welcomeBack: WelcomeBackStore
    let navigation: NotebookNavigation
    let deletion: PendingDeletion
    let loginItem: LoginItemSwitch
    @Environment(NoteWindowController.self) private var note

    /// Read again whenever the notebook opens or the toggle changes: the user can also change
    /// it in System Settings.
    @State private var loginState: SettingsValues.LoginState?

    var body: some View {
        switch model {
        case .success(let model):
            NotebookView(input: input(model), actions: actions(model), navigation: navigation, isOpen: note.isExpanded)
                .environment(\.shortcutRecorder, AnyView(NoteShortcut.recorder()))
                .onChange(of: note.isExpanded, initial: true) { if note.isExpanded { loginState = loginItem.state } }
                // Back from System Settings (e.g. after approving the login item): show the real
                // state (Phase 5 review).
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    if note.isExpanded { loginState = loginItem.state }
                }
        case .failure(let error):
            DatabaseErrorNotebook(message: error.message) { note.collapse() }
        }
    }

    private func input(_ model: AppModel) -> NotebookInput {
        NotebookInput(
            note: NoteInput(today: model.today, habits: Writes.noteHabits(model), notes: model.data.notes),
            stampDays: model.stampBook.count,
            unlocks: model.data.unlocks.map { UnlockInfo(unlock: $0.unlock, isNew: !$0.seen) },
            settings: SettingsValues(model.data.settings, appearanceUnlocked: model.darkModeUnlocked,
                                     openAtLogin: loginState ?? .off, today: model.today),
            unreadableHabits: model.data.habits.compactMap { habit in
                if case .failure = habit.history { UnreadableHabit(id: habit.id, name: habit.name) } else { nil }
            },
            pendingDeletion: deletion.deleted?.name)
    }

    private func actions(_ model: AppModel) -> NotebookActions {
        let repository = model.repository
        let used = { welcomeBack.used(model.today) }
        return NotebookActions(
            dayCard: Writes.dayCard(model, used: used),
            addHabit: { try Writes.addHabit($0, model: model) },
            editHabit: { id, changes in
                try Writes.form("edit") {
                    try repository.updateDetails(of: id, name: changes.name, identity: changes.identity,
                                                 schedule: changes.schedule, today: model.today)
                }
            },
            changeTarget: { id, amount in
                try Writes.form("target change") { try repository.changeTarget(of: id, to: amount, today: model.today) }
            },
            changeSchedule: { id, schedule in
                try Writes.form("schedule change") { try repository.changeSchedule(of: id, to: schedule, today: model.today) }
            },
            reorder: { ids in Writes.attempt("reorder") { try repository.reorder(ids) } },
            deactivate: { id in Writes.attempt("move to inactive") { try repository.deactivate(id, today: model.today) } },
            reactivate: { id in Writes.attempt("reactivate") { try repository.reactivate(id, today: model.today) } },
            delete: { id in
                Writes.attempt("delete") { deletion.start(try repository.deleteHabit(id)) }
            },
            undoDelete: {
                var restored: HabitID?
                Writes.attempt("undo delete") {
                    restored = try deletion.undo { try repository.restore($0, today: model.today) }
                }
                if let restored { navigation.showHabit(restored) }
            },
            collapse: { note.collapse() },
            visitStampBook: {
                Writes.attempt("stamp book visit") { try repository.markUnlocksSeen(at: Date()) }
                Writes.dismissUnlockNotices(model)
            },
            updateSettings: { change in
                let unlocked = model.darkModeUnlocked
                let login = loginState ?? .off
                Writes.attempt("settings") {
                    var chosenDayEnd: Int?
                    try repository.updateSettings { settings in
                        var values = SettingsValues(settings, appearanceUnlocked: unlocked, openAtLogin: login,
                                                    today: model.today)
                        let before = values.dayEndHour
                        change(&values)
                        values.apply(to: &settings)
                        if values.dayEndHour != before { chosenDayEnd = values.dayEndHour }
                    }
                    // Starts tomorrow, never moving today backwards (`DayEnd`).
                    if let chosenDayEnd { try repository.setDayEndHour(chosenDayEnd, now: model.currentDate) }
                }
            },
            setOpenAtLogin: { on in
                loginItem.set(on)
                loginState = loginItem.state
            },
            openLoginItemsSettings: { LoginItem.openSystemSettings() },
            exportData: { Self.export(repository) },
            resetNotePosition: { note.resetPosition() },
            used: used)
    }

    /// "Export my data": a save panel, then the JSON file (spec-settings.md).
    private static func export(_ repository: Repository) -> String? {
        let now = Date()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "66 Days export \(DayClock().day(for: now)).json"
        panel.message = "Everything you’ve logged, as a readable JSON file."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try repository.export(at: now).write(to: url, options: .atomic)
            return "Saved “\(url.lastPathComponent)”."
        } catch {
            Writes.log.error("Export failed: \(String(describing: error), privacy: .public)")
            return "Couldn’t save the export. Please try again."
        }
    }
}

/// Shown instead of the notebook when the database can't be opened.
private struct DatabaseErrorNotebook: View {
    let message: String
    let collapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("66 Days")
                    .font(.heading(28))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("Collapse", action: collapse)
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityIdentifier("notebook.collapse")
            }
            Text("Your habits couldn’t be opened. Try quitting 66 Days and opening it again. Nothing has been deleted.")
                .font(.text(14))
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.text(11))
                .foregroundStyle(Palette.inkSecondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(Metrics.notePadding * 2)
        .frame(width: Metrics.notebookPageWidth)
        .frame(maxHeight: .infinity)
        .background(PaperBackground())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
