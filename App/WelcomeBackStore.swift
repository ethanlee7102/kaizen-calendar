import Core
import Foundation
import Observation

/// Keeps the welcome-back state (`WelcomeBackTracker`) on this Mac, in UserDefaults. It's
/// device-local like the note position: "not opened for days" is about this Mac.
@MainActor
@Observable
final class WelcomeBackStore {
    private(set) var tracker: WelcomeBackTracker

    @ObservationIgnored private let defaults: UserDefaults?
    static let key = "note.welcomeBack"

    /// No `defaults`: kept in memory only (UI tests, sample data).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        tracker = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(WelcomeBackTracker.self, from: $0) } ?? WelcomeBackTracker()
    }

    var isPending: Bool { tracker.isPending }

    /// Launch, day change, wake: shows the note if it's due.
    func check(_ today: DayKey, evaluations: [HabitEvaluation]) {
        var updated = tracker
        updated.check(today, evaluations: evaluations)
        save(updated)
    }

    /// The note was used today (any click on it).
    func used(_ today: DayKey) {
        var updated = tracker
        updated.used(today)
        save(updated)
    }

    func dismiss() {
        var updated = tracker
        updated.dismiss()
        save(updated)
    }

    private func save(_ updated: WelcomeBackTracker) {
        guard updated != tracker else { return }
        tracker = updated
        if let data = try? JSONEncoder().encode(updated) { defaults?.set(data, forKey: Self.key) }
    }
}
