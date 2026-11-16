import SwiftUI

/// Builds a `Path` from SVG path data, so the artwork keeps the exact shapes drawn in the design
/// mockups (design/mockups/). Supports M, L, H, V, C, S, Q, A and Z, absolute and relative, with
/// implicit repeats. Nothing else is needed for the app's artwork.
nonisolated struct SVGPath: Sendable {
    /// The parsed path, in the SVG's own coordinates (its viewBox).
    let path: Path

    init(_ data: String) {
        var parser = Parser(data)
        path = parser.parse()
    }

    /// The path scaled from a square-or-rectangular `viewBox` into `rect`.
    func path(in rect: CGRect, viewBox: CGSize) -> Path {
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / viewBox.width, y: rect.height / viewBox.height)
        return path.applying(transform)
    }
}

nonisolated private struct Parser {
    private let scalars: [Character]
    private var index = 0
    private var path = Path()
    private var current = CGPoint.zero
    private var subpathStart = CGPoint.zero
    /// The last cubic control point (for S).
    private var lastControl: CGPoint?

    init(_ data: String) { scalars = Array(data) }

    mutating func parse() -> Path {
        while true {
            skipSeparators()
            guard index < scalars.count, scalars[index].isLetter else { break }
            var command = scalars[index]
            index += 1
            guard run(command) else { break }
            // Repeated arguments repeat the command; after a move they're line-tos.
            while hasNumberNext, command.uppercased() != "Z" {
                if command == "M" { command = "L" }
                if command == "m" { command = "l" }
                guard run(command) else { return path }
            }
        }
        return path
    }

    private var hasNumberNext: Bool {
        var probe = index
        while probe < scalars.count, Self.isSeparator(scalars[probe]) {
            probe += 1
        }
        guard probe < scalars.count else { return false }
        let c = scalars[probe]
        return (c.isNumber && c.isASCII) || c == "-" || c == "+" || c == "."
    }

    /// Runs one command (one set of arguments). Returns false on malformed data.
    private mutating func run(_ command: Character) -> Bool {
        let relative = command.isLowercase
        let base = relative ? current : .zero
        switch command.uppercased() {
        case "M":
            guard let p = point(relativeTo: base) else { return false }
            path.move(to: p)
            current = p
            subpathStart = p
            lastControl = nil
        case "L":
            guard let p = point(relativeTo: base) else { return false }
            path.addLine(to: p)
            current = p
            lastControl = nil
        case "H":
            guard let x = number() else { return false }
            current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
            path.addLine(to: current)
            lastControl = nil
        case "V":
            guard let y = number() else { return false }
            current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
            path.addLine(to: current)
            lastControl = nil
        case "C":
            guard let c1 = point(relativeTo: base), let c2 = point(relativeTo: base),
                  let p = point(relativeTo: base) else { return false }
            path.addCurve(to: p, control1: c1, control2: c2)
            current = p
            lastControl = c2
        case "S":
            guard let c2 = point(relativeTo: base), let p = point(relativeTo: base) else { return false }
            let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
            path.addCurve(to: p, control1: c1, control2: c2)
            current = p
            lastControl = c2
        case "Q":
            guard let c = point(relativeTo: base), let p = point(relativeTo: base) else { return false }
            path.addQuadCurve(to: p, control: c)
            current = p
            lastControl = nil
        case "A":
            guard let rx = number(), let ry = number(), let rotation = number(),
                  let largeArc = flag(), let sweep = flag(), let p = point(relativeTo: base) else { return false }
            addArc(to: p, rx: rx, ry: ry, rotation: rotation, largeArc: largeArc, sweep: sweep)
            current = p
            lastControl = nil
        case "Z":
            path.closeSubpath()
            current = subpathStart
            lastControl = nil
            return true
        default:
            return false
        }
        return true
    }

    // MARK: Arcs (SVG endpoint parameterization → center parameterization)

    private mutating func addArc(to end: CGPoint, rx: CGFloat, ry: CGFloat, rotation: CGFloat,
                                 largeArc: Bool, sweep: Bool) {
        let start = current
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0, start != end else {
            path.addLine(to: end)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x1 = cosPhi * dx + sinPhi * dy
        let y1 = -sinPhi * dx + cosPhi * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= lambda.squareRoot()
            ry *= lambda.squareRoot()
        }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var factor = (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep { factor = -factor }
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let center = CGPoint(x: cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2,
                             y: sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2)
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let sign: CGFloat = ux * vy - uy * vx < 0 ? -1 : 1
            let dot = ux * vx + uy * vy
            let length = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
            return sign * acos(min(1, max(-1, dot / length)))
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        // Approximate with line segments fine enough for 1–2pt artwork at any size used.
        let steps = max(8, Int(abs(delta) / (.pi / 32)))
        for step in 1...steps {
            let t = theta1 + delta * CGFloat(step) / CGFloat(steps)
            let x = rx * cos(t), y = ry * sin(t)
            path.addLine(to: CGPoint(x: center.x + cosPhi * x - sinPhi * y,
                                     y: center.y + sinPhi * x + cosPhi * y))
        }
    }

    // MARK: Tokens

    private mutating func point(relativeTo base: CGPoint) -> CGPoint? {
        guard let x = number(), let y = number() else { return nil }
        return CGPoint(x: base.x + x, y: base.y + y)
    }

    private mutating func flag() -> Bool? {
        skipSeparators()
        guard index < scalars.count, scalars[index] == "0" || scalars[index] == "1" else { return nil }
        defer { index += 1 }
        return scalars[index] == "1"
    }

    private mutating func number() -> CGFloat? {
        skipSeparators()
        let start = index
        if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
        var sawDot = false
        var sawDigit = false
        while index < scalars.count {
            let c = scalars[index]
            if c.isNumber, c.isASCII {
                sawDigit = true
            } else if c == ".", !sawDot {
                sawDot = true
            } else if c == "e" || c == "E" {
                index += 1
                if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
                continue
            } else {
                break
            }
            index += 1
        }
        guard sawDigit, let value = Double(String(scalars[start..<index])) else {
            index = start
            return nil
        }
        return CGFloat(value)
    }

    /// Spaces, tabs, newlines and commas (SVG's separators).
    private static func isSeparator(_ c: Character) -> Bool { c == "," || c.isWhitespace }

    private mutating func skipSeparators() {
        while index < scalars.count, Self.isSeparator(scalars[index]) {
            index += 1
        }
    }
}
