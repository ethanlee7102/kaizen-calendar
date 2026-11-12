import SwiftUI
import Testing
@testable import UI

#if canImport(AppKit)
import AppKit
#endif

@Suite struct FontTests {
    @Test func everyBundledFaceRegistersAndLoads() throws {
        try FontRegistry.registerAll()
        try FontRegistry.registerAll() // A second call is harmless.
        #if canImport(AppKit)
        for face in FontFace.allCases {
            let font = try #require(NSFont(name: face.rawValue, size: 14), "\(face.rawValue) didn't load")
            #expect(font.fontName == face.rawValue)
        }
        #endif
    }

    @Test func fontsCoverTheLatinTextTheAppShows() throws {
        try FontRegistry.registerAll()
        #if canImport(AppKit)
        let sample = "November 2026 · Day 41 of 66 — “Never miss twice.” 1% → café"
        for face in FontFace.allCases {
            let font = try #require(NSFont(name: face.rawValue, size: 14))
            let missing = sample.unicodeScalars.filter { scalar in
                var glyph = CGGlyph()
                var unit = UniChar(scalar.value)
                return !CTFontGetGlyphsForCharacters(font, &unit, &glyph, 1)
            }
            #expect(missing.isEmpty, "\(face.rawValue) is missing \(missing.map(String.init))")
        }
        #endif
    }
}

@Suite struct PaletteTests {
    @Test func hexIsDecodedAsSRGB() {
        let paper = RGBA(hex: 0xF7F2E8)
        #expect(paper.red == 0xF7 / 255.0)
        #expect(paper.green == 0xF2 / 255.0)
        #expect(paper.blue == 0xE8 / 255.0)
        #expect(paper.alpha == 1)
    }

    @Test func tokenFollowsTheColorScheme() {
        var environment = EnvironmentValues()
        environment.colorScheme = .light
        #expect(Palette.ink.resolve(in: environment) == RGBA(hex: 0x2B2A27).resolved)
        environment.colorScheme = .dark
        #expect(Palette.ink.resolve(in: environment) == RGBA(hex: 0xECE6DA).resolved)
    }

    /// spec-collapsed-note.md §1: text contrast is at least 4.5:1, in light and dark.
    @Test(arguments: [ColorScheme.light, .dark])
    func textColorsMeetContrastOnPaper(scheme: ColorScheme) {
        let textTokens: [(String, ColorToken)] = [
            ("ink", Palette.ink), ("inkSecondary", Palette.inkSecondary), ("inkFaint", Palette.inkFaint),
            ("goldText", Palette.goldText), ("indigo", Palette.indigo),
            ("dangerText", Palette.dangerText), ("mossText", Palette.mossText),
        ]
        for background in [Palette.paper, Palette.raisedPaper] {
            for (name, token) in textTokens {
                let ratio = token.value(for: scheme).contrastRatio(with: background.value(for: scheme))
                #expect(ratio >= 4.5, "\(name) is \(ratio):1 in \(scheme)")
            }
        }
    }
}
