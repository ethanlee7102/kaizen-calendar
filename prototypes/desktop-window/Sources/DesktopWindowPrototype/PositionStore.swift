import AppKit

extension NSScreen {
    /// Stable identifier that survives unplug/replug (CGDirectDisplayID can change; the display UUID doesn't).
    var stableID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Remembers the note's position per display, anchored to the nearest corner of that display.
@MainActor
final class PositionStore {
    enum Corner: String, Codable { case topLeft, topRight, bottomLeft, bottomRight }

    struct Saved: Codable {
        var corner: Corner
        var dx: Double
        var dy: Double
    }

    private let defaults = UserDefaults.standard
    private let homeKey = "prototype.homeDisplay"
    private let positionsKey = "prototype.positions"

    private var homeDisplay: String? {
        get { defaults.string(forKey: homeKey) }
        set { defaults.set(newValue, forKey: homeKey) }
    }

    private var positions: [String: Saved] {
        get {
            guard let data = defaults.data(forKey: positionsKey) else { return [:] }
            return (try? JSONDecoder().decode([String: Saved].self, from: data)) ?? [:]
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: positionsKey) }
    }

    /// Saves where the user put the window. Returns a description for the log.
    func save(_ window: NSWindow) -> String {
        guard let screen = window.screen, let id = screen.stableID else { return "not saved (no screen)" }
        let vf = screen.visibleFrame
        let f = window.frame
        let left = f.midX < vf.midX
        let bottom = f.midY < vf.midY
        let corner: Corner = switch (left, bottom) {
        case (true, true): .bottomLeft
        case (true, false): .topLeft
        case (false, true): .bottomRight
        case (false, false): .topRight
        }
        let dx = left ? f.minX - vf.minX : vf.maxX - f.maxX
        let dy = bottom ? f.minY - vf.minY : vf.maxY - f.maxY
        var all = positions
        all[id] = Saved(corner: corner, dx: dx, dy: dy)
        positions = all
        homeDisplay = id
        return "saved on \(screen.localizedName) @ \(corner.rawValue) (\(Int(dx)), \(Int(dy)))"
    }

    /// Where the collapsed note should be. Falls back to the primary display if the home display is gone,
    /// without forgetting the home display (so replugging returns it).
    func frame(for size: NSSize) -> (NSRect, String) {
        let screens = NSScreen.screens
        if let home = homeDisplay,
           let screen = screens.first(where: { $0.stableID == home }),
           let saved = positions[home] {
            return (place(saved, size, in: screen.visibleFrame),
                    "home display \(screen.localizedName) @ \(saved.corner.rawValue)")
        }
        guard let fallback = screens.first else {
            return (NSRect(origin: .zero, size: size), "no screens")
        }
        let saved = homeDisplay.flatMap { positions[$0] } ?? Saved(corner: .topRight, dx: 24, dy: 24)
        let why = homeDisplay == nil ? "no saved position" : "home display missing"
        return (place(saved, size, in: fallback.visibleFrame),
                "fallback to \(fallback.localizedName) @ \(saved.corner.rawValue) (\(why))")
    }

    func reset() {
        defaults.removeObject(forKey: homeKey)
        defaults.removeObject(forKey: positionsKey)
    }

    private func place(_ saved: Saved, _ size: NSSize, in vf: NSRect) -> NSRect {
        let isLeft = saved.corner == .topLeft || saved.corner == .bottomLeft
        let isBottom = saved.corner == .bottomLeft || saved.corner == .bottomRight
        let x = isLeft ? vf.minX + saved.dx : vf.maxX - saved.dx - size.width
        let y = isBottom ? vf.minY + saved.dy : vf.maxY - saved.dy - size.height
        return clamp(NSRect(x: x, y: y, width: size.width, height: size.height), to: vf)
    }
}

func clamp(_ rect: NSRect, to bounds: NSRect) -> NSRect {
    var r = rect
    r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
    r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
    return r
}
