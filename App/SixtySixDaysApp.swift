import Core
import Persistence
import SwiftUI
import UI

@main
struct SixtySixDaysApp: App {
    init() {
        do {
            try FontRegistry.registerAll()
        } catch {
            assertionFailure("Couldn't register the bundled fonts: \(error)")
        }
    }

    var body: some Scene {
        // Placeholder window for Phase 0. Phase 3 replaces it with the desktop sticky-note panel.
        WindowGroup("66 Days") {
            PlaceholderView()
                .preferredColorScheme(.light) // Appearance setting defaults to Light (spec-settings.md).
        }
        .windowResizability(.contentSize)
    }
}

/// Shows that the fonts, colors and packages are wired up. Removed in Phase 3.
private struct PlaceholderView: View {
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
        }
        .padding(Metrics.notePadding)
        .frame(width: Metrics.noteWidth, alignment: .leading)
        .background(Palette.paper)
    }
}

#Preview {
    PlaceholderView()
}
