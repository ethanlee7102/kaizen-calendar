import SwiftUI

// The note's artwork as shapes, from the design mockups (design/mockups/Main.dc.html). The specs
// describe them (spec-collapsed-note.md §3, §5); the SVG data here is the drawn shape.

/// The irregular, hand-pressed vermilion seal (full seal, stamps). 36×36 artwork.
nonisolated public struct SealShape: Shape {
    static let svg = SVGPath("M18 3.5c4.2.1 8.3 1.9 10.9 5.1 2.6 3.1 3.9 7.4 3.4 11.4-.5 4.1-2.8 7.9-6.2 10.1-3.3 2.3-7.7 3-11.6 2-4-1-7.5-3.8-9.3-7.5C3.4 21 3.3 16.5 5 12.8 6.6 9.1 9.9 6.1 13.8 4.6c1.3-.5 2.8-1 4.2-1.1z")

    public init() {}

    public func path(in rect: CGRect) -> Path {
        Self.svg.path(in: rect, viewBox: CGSize(width: 36, height: 36))
    }
}

/// One slice of a sliced seal: a wedge of the circle, starting at 12 o'clock and going clockwise
/// in habit order. One slice of one is the whole circle.
nonisolated public struct SealSliceShape: Shape {
    public let index: Int
    public let count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        guard count > 1 else { return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                            width: 2 * radius, height: 2 * radius)) }
        let sweep = 360.0 / Double(count)
        let start = -90 + sweep * Double(index)
        var path = Path()
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(start),
                    endAngle: .degrees(start + sweep), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The lines between a sliced seal's slices, so the number of habits shows even before any is
/// done.
nonisolated public struct SealDividers: Shape {
    public let count: Int

    public init(count: Int) { self.count = count }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count > 1 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<count {
            let angle = (-90 + 360 * Double(i) / Double(count)) * .pi / 180
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle)))
        }
        return path
    }
}

/// The gold seam across a recovered day: a thin jagged line, like a kintsugi repair. 36×32 artwork.
nonisolated public struct GoldSeamShape: Shape {
    static let svg = SVGPath("M5 8.5 11.5 13 9.5 17.5 18.5 19.5 22.5 15 31 23.5")

    public init() {}

    public func path(in rect: CGRect) -> Path {
        Self.svg.path(in: rect, viewBox: CGSize(width: 36, height: 32))
    }
}

/// The leaf: flat, symmetric, pointed tip and rounded base (spec-collapsed-note.md §5). Drawn
/// upright in a 36×36 box; `LeafMark` rotates it 40°.
nonisolated public struct LeafShape: Shape {
    static let blade = SVGPath("M18 4C23 9 24.5 15 23.5 19.5 22.5 23.5 20.5 26 18 27 15.5 26 13.5 23.5 12.5 19.5 11.5 15 13 9 18 4Z")

    public init() {}

    public func path(in rect: CGRect) -> Path {
        Self.blade.path(in: rect, viewBox: CGSize(width: 36, height: 36))
    }
}

/// The leaf's single center vein.
nonisolated public struct LeafVeinShape: Shape {
    static let vein = SVGPath("M18 7V25.5")
    public init() {}
    public func path(in rect: CGRect) -> Path {
        Self.vein.path(in: rect, viewBox: CGSize(width: 36, height: 36))
    }
}

/// The leaf's short straight stem.
nonisolated public struct LeafStemShape: Shape {
    static let stem = SVGPath("M18 27V31")
    public init() {}
    public func path(in rect: CGRect) -> Path {
        Self.stem.path(in: rect, viewBox: CGSize(width: 36, height: 36))
    }
}

/// An arc of a circle from 12 o'clock-ish, for the journey's brush circle. `progress` is 0...1.
nonisolated public struct BrushArc: Shape {
    public var progress: Double

    public init(progress: Double) { self.progress = progress }

    public var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let progress = min(1, max(0, progress))
        guard progress > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // Starts a little left of the top, like a brush stroke begun by a right hand (mockup:
        // rotate(-100°)).
        let start = -100.0
        path.addArc(center: center, radius: radius, startAngle: .degrees(start),
                    endAngle: .degrees(start + 360 * progress), clockwise: false)
        return path
    }
}
