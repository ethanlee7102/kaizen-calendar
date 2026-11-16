import AppShell
import Core
import Observation
import Persistence
import SwiftUI
import UI

// Placeholder content for the notebook (Phase 3). Phase 5 replaces it with the real notebook.

struct PlaceholderNotebook: View {
    let model: Result<AppModel, DatabaseOpenError>
    @Environment(NoteWindowController.self) private var note

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("66 Days")
                    .font(.heading(28))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("Collapse", systemImage: "arrow.down.right.and.arrow.up.left") { note.collapse() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.inkSecondary)
                    .help("Collapse")
            }
            Text("The notebook opens here: Calendar, Habits, Reports, Stamp book, The Science and Settings.")
                .font(.text(14))
                .foregroundStyle(Palette.inkSecondary)
            DatabaseStatus(model: model)
            Spacer()
        }
        .padding(Metrics.notePadding * 2)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: Metrics.noteCornerRadius))
    }
}

private struct DatabaseStatus: View {
    let model: Result<AppModel, DatabaseOpenError>

    var body: some View {
        switch model {
        case .success(let model):
            Text("\(model.data.habits.count) habits stored · today is \(model.today.description)")
                .font(.text(11))
                .foregroundStyle(Palette.inkFaint)
        case .failure(let error):
            Text("The database couldn't be opened: \(error.message)")
                .font(.text(11))
                .foregroundStyle(Palette.dangerText)
        }
    }
}
