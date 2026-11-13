import Core
import Persistence
import SwiftUI
import UI

@main
struct SixtySixDaysApp: App {
    /// The app's data, or why the database couldn't be opened.
    @State private var model: Result<AppModel, DatabaseOpenError>

    init() {
        do {
            try FontRegistry.registerAll()
        } catch {
            assertionFailure("Couldn't register the bundled fonts: \(error)")
        }
        _model = State(initialValue: Result {
            AppModel(repository: Repository(database: try AppDatabase.open(at: AppDatabase.defaultURL())))
        }.mapError { DatabaseOpenError(message: "\($0)") })
    }

    var body: some Scene {
        // Placeholder window for Phases 0–2. Phase 3 replaces it with the desktop sticky-note panel.
        WindowGroup("66 Days") {
            PlaceholderView(model: model)
                .preferredColorScheme(.light) // Appearance setting defaults to Light (spec-settings.md).
        }
        .windowResizability(.contentSize)
    }
}

struct DatabaseOpenError: Error {
    let message: String
}

/// Shows that the fonts, colors, packages and database are wired up. Removed in Phase 3.
private struct PlaceholderView: View {
    let model: Result<AppModel, DatabaseOpenError>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("66 Days")
                .font(.heading(22))
                .foregroundStyle(Palette.ink)
            Text("Day 1 of \(HabitRules.journeyLength)")
                .font(.text(14, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            Text("Never miss twice. Today counts.")
                .font(.handwriting(12))
                .foregroundStyle(Palette.dangerText)
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
        .padding(Metrics.notePadding)
        .frame(width: Metrics.noteWidth, alignment: .leading)
        .background(Palette.paper)
    }
}

#Preview {
    PlaceholderView(model: Result { AppModel(repository: Repository(database: try AppDatabase.inMemory())) }
        .mapError { DatabaseOpenError(message: "\($0)") })
}
