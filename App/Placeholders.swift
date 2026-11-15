import AppShell
import Core
import Observation
import Persistence
import SwiftUI
import UI

// Placeholder content for the window shell (Phase 3). Phase 4 replaces the note and Phase 5 the
// notebook. They show that the fonts, colors, packages, database and window modes are wired up.

@Observable
final class PlaceholderState {
    /// Extra fake habit rows, to check that the note grows with its content (Debug menu).
    var rows = 0
    var checked: Set<Int> = []
}

struct PlaceholderNote: View {
    let model: Result<AppModel, DatabaseOpenError>
    let state: PlaceholderState
    @Environment(NoteWindowController.self) private var note

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("66 Days")
                    .font(.heading(22))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("Expand", systemImage: "arrow.up.left.and.arrow.down.right") { note.expand() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.inkSecondary)
                    .help("Expand")
            }
            Text("Never miss twice. Today counts.")
                .font(.handwriting(13))
                .foregroundStyle(Palette.dangerText)
            ForEach(0..<state.rows, id: \.self) { index in
                // A stand-in check-off, to test first clicks while another app is in front.
                Toggle("Habit \(index + 1)", isOn: Binding(
                    get: { state.checked.contains(index) },
                    set: { if $0 { state.checked.insert(index) } else { state.checked.remove(index) } }))
                    .toggleStyle(.checkbox)
                    .font(.text(14, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: Metrics.habitRowMinHeight, alignment: .leading)
            }
            DatabaseStatus(model: model)
        }
        .padding(Metrics.notePadding)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: Metrics.noteCornerRadius))
    }
}

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
