import Core
import Observation

/// A deleted habit kept for its Undo, for about 10 seconds (spec-goals-list.md). After that the
/// deletion is final. One Undo at a time: a newer deletion makes the older one final.
@MainActor
@Observable
public final class PendingDeletion {
    public private(set) var deleted: DeletedHabit?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private let window: Duration

    public static let undoWindow = Duration.seconds(10)

    public init(window: Duration = PendingDeletion.undoWindow) { self.window = window }

    public func start(_ deleted: DeletedHabit) {
        expiry?.cancel()
        self.deleted = deleted
        expiry = Task { [weak self, window] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self?.deleted = nil
        }
    }

    /// Undo: `restore` puts the habit back. The deletion is cleared only once that succeeded, so
    /// a failed restore can be tried again while the toast is up (Phase 5 review). Returns the
    /// restored habit, or nil if there was nothing to undo.
    @discardableResult
    public func undo(_ restore: (DeletedHabit) throws -> Void) throws -> HabitID? {
        guard let deleted else { return nil }
        try restore(deleted)
        expiry?.cancel()
        self.deleted = nil
        return deleted.id
    }
}
