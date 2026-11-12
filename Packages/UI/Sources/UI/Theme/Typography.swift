import CoreText
import Foundation
import SwiftUI

/// The bundled font faces (spec-collapsed-note.md §1). Raw values are PostScript names.
nonisolated public enum FontFace: String, CaseIterable, Sendable {
    // Headings, month name, big numbers.
    case shipporiMedium = "ShipporiMincho-Medium"
    case shipporiBold = "ShipporiMincho-Bold"
    // UI text, labels, numbers.
    case zenRegular = "ZenKakuGothicNew-Regular"
    case zenMedium = "ZenKakuGothicNew-Medium"
    case zenBold = "ZenKakuGothicNew-Bold"
    // Handwritten accents only.
    case kleeRegular = "KleeOne-Regular"
    case kleeSemiBold = "KleeOne-SemiBold"

    /// The font file in Resources/Fonts. File names match PostScript names.
    var fileName: String { rawValue + ".ttf" }
}

nonisolated public extension Font {
    enum HeadingWeight: Sendable { case medium, bold }
    enum TextWeight: Sendable { case regular, medium, bold }
    enum HandWeight: Sendable { case regular, semiBold }

    /// Shippori Mincho: headings, the month name, big numbers.
    static func heading(_ size: CGFloat, weight: HeadingWeight = .bold) -> Font {
        .custom((weight == .bold ? FontFace.shipporiBold : .shipporiMedium).rawValue, fixedSize: size)
    }

    /// Zen Kaku Gothic New: UI text, labels and numbers.
    static func text(_ size: CGFloat, weight: TextWeight = .regular) -> Font {
        let face: FontFace = switch weight {
        case .regular: .zenRegular
        case .medium: .zenMedium
        case .bold: .zenBold
        }
        return .custom(face.rawValue, fixedSize: size)
    }

    /// Klee One: only for personal or encouraging lines (danger/recovered/rest lines, hints,
    /// the daily note, report greetings, the identity line). See spec-visual-identity.md.
    static func handwriting(_ size: CGFloat, weight: HandWeight = .regular) -> Font {
        .custom((weight == .semiBold ? FontFace.kleeSemiBold : .kleeRegular).rawValue, fixedSize: size)
    }
}

/// Registers the bundled fonts for this process. Call once at launch, before any view draws.
public enum FontRegistry {
    public enum Failure: Error, Equatable {
        case missingFile(String)
        case registrationFailed(String)
    }

    /// Registers every face in `FontFace`. Safe to call more than once.
    public static func registerAll() throws {
        for face in FontFace.allCases {
            guard let url = Bundle.module.url(forResource: face.rawValue, withExtension: "ttf",
                                              subdirectory: "Fonts")
            else { throw Failure.missingFile(face.fileName) }

            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let cfError = error?.takeRetainedValue()
                let code = cfError.map { CFErrorGetCode($0) } ?? 0
                if code != CTFontManagerError.alreadyRegistered.rawValue {
                    throw Failure.registrationFailed(face.rawValue)
                }
            }
        }
    }
}
