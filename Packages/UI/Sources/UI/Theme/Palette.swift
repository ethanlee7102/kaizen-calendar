import SwiftUI

/// An sRGB color with alpha, written as hex. Plain data, so tokens can be tested without a renderer.
nonisolated public struct RGBA: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public init(red: Int, green: Int, blue: Int, alpha: Double = 1) {
        self.red = Double(red) / 255
        self.green = Double(green) / 255
        self.blue = Double(blue) / 255
        self.alpha = alpha
    }

    /// WCAG relative luminance (ignores alpha).
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two opaque colors (1...21).
    public func contrastRatio(with other: RGBA) -> Double {
        let (a, b) = (relativeLuminance, other.relativeLuminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    var resolved: Color.Resolved {
        Color.Resolved(colorSpace: .sRGB, red: Float(red), green: Float(green), blue: Float(blue),
                       opacity: Float(alpha))
    }
}

/// A light/dark color pair. Use it directly as a style: `.foregroundStyle(Palette.ink)`.
/// It follows the view's color scheme, so the Appearance setting (Light / Dark / Match system)
/// only needs to set `preferredColorScheme` at the root.
nonisolated public struct ColorToken: ShapeStyle, Hashable, Sendable {
    public let light: RGBA
    public let dark: RGBA

    public init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    public init(light: UInt32, dark: UInt32) {
        self.init(light: RGBA(hex: light), dark: RGBA(hex: dark))
    }

    public func value(for scheme: ColorScheme) -> RGBA {
        scheme == .dark ? dark : light
    }

    public func color(for scheme: ColorScheme) -> Color {
        Color(value(for: scheme).resolved)
    }

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        value(for: environment.colorScheme).resolved
    }
}

/// Color tokens from spec-collapsed-note.md §1 (light / dark). The spec is the source of truth.
nonisolated public enum Palette {
    /// Note background.
    public static let paper = ColorToken(light: 0xF7F2E8, dark: 0x23211E)
    /// Day card, form, info boxes.
    public static let raisedPaper = ColorToken(light: 0xFBF7EF, dark: 0x2C2925)
    /// The note's subtle dot grid (14px spacing).
    public static let dotGrid = ColorToken(light: RGBA(red: 120, green: 100, blue: 70, alpha: 0.20),
                                           dark: RGBA(red: 236, green: 230, blue: 218, alpha: 0.08))
    /// Primary text, brush-circle arc.
    public static let ink = ColorToken(light: 0x2B2A27, dark: 0xECE6DA)
    /// Secondary text, labels.
    public static let inkSecondary = ColorToken(light: 0x6B6458, dark: 0xB3AA9A)
    /// Future day numbers, rest numbers.
    public static let inkFaint = ColorToken(light: 0x716A5D, dark: 0xA69E8F)
    /// Dashed outlines, pencil circle.
    public static let pencil = ColorToken(light: 0x8C8476, dark: 0x9A9385)
    /// Dividers.
    public static let rule = ColorToken(light: 0xDCD2C1, dark: 0x3A3631)
    /// Brush-circle track.
    public static let track = ColorToken(light: 0xE2D8C7, dark: 0x3A3631)
    /// Input underlines, unselected chip borders.
    public static let fieldLine = ColorToken(light: 0xCFC4B1, dark: 0x4A453E)
    /// Seals and stamps.
    public static let vermilion = ColorToken(light: 0xC8402F, dark: 0xC9483A)
    /// Gold seam (recovered day).
    public static let gold = ColorToken(light: 0xB8862B, dark: 0xD9AE52)
    /// "Recovered" line, gold labels.
    public static let goldText = ColorToken(light: 0x8A6417, dark: 0xE0B866)
    /// Today frame, links, focus, selected filter, primary button.
    public static let indigo = ColorToken(light: 0x2F4A6D, dark: 0x8FA9CC)
    /// "Never miss twice" line.
    public static let dangerText = ColorToken(light: 0xA3392A, dark: 0xEC9A86)
    /// Leaf, rest dash.
    public static let moss = ColorToken(light: 0x6E8B6A, dark: 0x8FAE8A)
    /// "Rest day" text, "Rest today" link.
    public static let mossText = ColorToken(light: 0x4E6B4A, dark: 0xA9C79E)
    /// Pools and ripples. The spec gives only the base color; each use sets its own opacity.
    public static let water = ColorToken(light: 0x6E9BC3, dark: 0x6E9BC3)
    /// Habit name background while filtering.
    public static let selectedName = ColorToken(light: 0xE6DCC9, dark: 0x34302B)
}
