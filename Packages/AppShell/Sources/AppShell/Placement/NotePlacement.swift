import CoreGraphics

// Where the note goes on screen. Pure geometry, no AppKit, so every rule here is unit-tested.
// All rectangles use AppKit's screen coordinates (origin bottom-left, y grows upwards), and the
// bounds are a display's *visible* frame (without the menu bar and Dock).

/// A corner of a display.
nonisolated public enum Corner: String, Codable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }

    /// The corner of `bounds` nearest to the center of `rect`.
    static func nearest(to rect: CGRect, in bounds: CGRect) -> Corner {
        switch (rect.midX < bounds.midX, rect.midY < bounds.midY) {
        case (true, true): .bottomLeft
        case (true, false): .topLeft
        case (false, true): .bottomRight
        case (false, false): .topRight
        }
    }
}

/// A spot on a display, stored as the distance from the display's nearest corner to the same
/// corner of the note. Anchoring to a corner keeps the note in "its" corner when the resolution
/// or arrangement changes, and lets the note grow away from that corner when its content grows.
nonisolated public struct AnchoredPosition: Codable, Equatable, Sendable {
    public var corner: Corner
    /// Horizontal distance from the corner's vertical edge, in points.
    public var dx: Double
    /// Vertical distance from the corner's horizontal edge, in points.
    public var dy: Double

    public init(corner: Corner, dx: Double, dy: Double) {
        self.corner = corner
        self.dx = dx
        self.dy = dy
    }

    /// The position of `frame` within `visibleFrame`, anchored to its nearest corner.
    public init(frame: CGRect, in visibleFrame: CGRect) {
        let corner = Corner.nearest(to: frame, in: visibleFrame)
        self.init(
            corner: corner,
            dx: corner.isLeft ? frame.minX - visibleFrame.minX : visibleFrame.maxX - frame.maxX,
            dy: corner.isBottom ? frame.minY - visibleFrame.minY : visibleFrame.maxY - frame.maxY)
    }

    /// Where a note of `size` goes at this position, kept fully inside `visibleFrame`.
    public func frame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let x = corner.isLeft ? visibleFrame.minX + dx : visibleFrame.maxX - dx - size.width
        let y = corner.isBottom ? visibleFrame.minY + dy : visibleFrame.maxY - dy - size.height
        return NoteGeometry.clamp(CGRect(origin: CGPoint(x: x, y: y), size: size), to: visibleFrame)
    }

    /// Where the note starts, and where "Reset note position" puts it: the top-right of the
    /// main display (spec-settings.md).
    public static let initial = AnchoredPosition(corner: .topRight, dx: 24, dy: 24)
}

/// A connected display.
nonisolated public struct Display: Equatable, Sendable {
    /// Stable across unplug/replug and restarts (the display's UUID).
    public var id: String
    public var visibleFrame: CGRect

    public init(id: String, visibleFrame: CGRect) {
        self.id = id
        self.visibleFrame = visibleFrame
    }
}

/// The note's saved positions: one per display it was ever dragged on, and the display it was
/// last dragged to (its "home").
///
/// Locked behavior (memory/desktop-window-findings.md): only the user's drags save a position.
/// When the home display is unplugged the note falls back to the main display without forgetting
/// home, so it returns when the display is plugged back in.
nonisolated public struct NotePositions: Codable, Equatable, Sendable {
    /// The display the user last dragged the note on.
    public var home: String?
    /// The last position the user chose on each display, by display ID.
    public var byDisplay: [String: AnchoredPosition]

    public init(home: String? = nil, byDisplay: [String: AnchoredPosition] = [:]) {
        self.home = home
        self.byDisplay = byDisplay
    }

    /// Records where the user dragged the note; `display` becomes home.
    public mutating func save(frame: CGRect, on display: Display) {
        byDisplay[display.id] = AnchoredPosition(frame: frame, in: display.visibleFrame)
        home = display.id
    }

    /// Where the collapsed note goes. `displays` lists the connected displays, the main display
    /// first (as `NSScreen.screens` does). Nil when there are no displays.
    ///
    /// - On the home display: its saved position.
    /// - Home missing (unplugged) or never set: the main display, at the position last chosen
    ///   there; otherwise the home position's corner and offsets; otherwise the initial spot.
    public func frame(size: CGSize, displays: [Display]) -> CGRect? {
        if let home, let display = displays.first(where: { $0.id == home }), let saved = byDisplay[home] {
            return saved.frame(size: size, in: display.visibleFrame)
        }
        guard let main = displays.first else { return nil }
        let position = byDisplay[main.id] ?? home.flatMap { byDisplay[$0] } ?? .initial
        return position.frame(size: size, in: main.visibleFrame)
    }
}

nonisolated public enum NoteGeometry {
    /// Where the collapsed note goes when its content's height changes.
    ///
    /// Normally that's where the saved positions put it, so it grows away from the corner it was
    /// anchored to when the user dragged it, and growing then shrinking returns it exactly
    /// (decided in the Phase 3 review, with the user). Mid-drag nothing is saved yet, so it
    /// keeps the current frame's nearest corner.
    public static func collapsedFrame(afterHeightChangeTo size: CGSize, current: CGRect, currentDisplay: Display?,
                                      positions: NotePositions, displays: [Display],
                                      isDragging: Bool) -> CGRect? {
        if isDragging, let currentDisplay {
            return AnchoredPosition(frame: current, in: currentDisplay.visibleFrame)
                .frame(size: size, in: currentDisplay.visibleFrame)
        }
        return positions.frame(size: size, displays: displays)
    }

    /// Moves `rect` so it lies inside `bounds`. If it's larger than `bounds`, its top-left stays
    /// visible (that's where the header and controls are).
    public static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var result = rect
        result.origin.x = max(min(rect.minX, bounds.maxX - rect.width), bounds.minX)
        result.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
        return result
    }

    /// The expanded notebook's frame: it grows out of the note, keeping the note's nearest corner
    /// in place, and is moved so it stays fully on screen (spec-expanded-structure.md).
    public static func expandedFrame(from note: CGRect, size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let corner = Corner.nearest(to: note, in: visibleFrame)
        let x = corner.isLeft ? note.minX : note.maxX - size.width
        let y = corner.isBottom ? note.minY : note.maxY - size.height
        return clamp(CGRect(origin: CGPoint(x: x, y: y), size: size), to: visibleFrame)
    }
}
