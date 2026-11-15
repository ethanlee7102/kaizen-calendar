import Foundation

/// Keeps the note's positions in UserDefaults. They're device-local (each Mac has its own
/// displays), so they're never synced or exported (build plan, Phase 2).
public final class PositionStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "note.positions") {
        self.defaults = defaults
        self.key = key
    }

    /// The saved positions. Unreadable data counts as none, so the note starts at its initial
    /// spot instead of failing.
    public var positions: NotePositions {
        get {
            guard let data = defaults.data(forKey: key) else { return NotePositions() }
            return (try? JSONDecoder().decode(NotePositions.self, from: data)) ?? NotePositions()
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }

    /// Forgets every saved position ("Reset note position" in Settings).
    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
