import Core
import Foundation
import Observation
import UI

/// Keeps the "Drag me anywhere." hint (`DragHint`) on this Mac, in UserDefaults, like the note's
/// position: dragging is about this Mac's desktop.
@MainActor
@Observable
final class DragHintStore {
    private(set) var hint: DragHint

    @ObservationIgnored private let defaults: UserDefaults?
    static let key = "note.dragHint"

    /// No `defaults`: kept in memory only (UI tests, sample data).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        hint = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(DragHint.self, from: $0) } ?? DragHint()
    }

    func isShowing(today: DayKey) -> Bool { hint.isShowing(today: today) }

    func start(today: DayKey) { update { $0.start(today: today) } }

    func finish() { update { $0.finish() } }

    private func update(_ change: (inout DragHint) -> Void) {
        var updated = hint
        change(&updated)
        guard updated != hint else { return }
        hint = updated
        if let data = try? JSONEncoder().encode(updated) { defaults?.set(data, forKey: Self.key) }
    }
}
