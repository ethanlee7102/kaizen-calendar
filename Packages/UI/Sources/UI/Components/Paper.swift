import Core
import SwiftUI

/// The note's paper: the paper color with a subtle 14-point dot grid (spec-collapsed-note.md §1).
public struct PaperBackground: View {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = Metrics.noteCornerRadius) { self.cornerRadius = cornerRadius }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Palette.paper)
            .overlay {
                DotGrid(spacing: Metrics.dotGridSpacing)
                    .fill(Palette.dotGrid)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
    }
}

nonisolated struct DotGrid: Shape {
    let spacing: CGFloat
    var dotSize: CGFloat = 1.4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var y = rect.minY + spacing / 2
        while y < rect.maxY {
            var x = rect.minX + spacing / 2
            while x < rect.maxX {
                path.addEllipse(in: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
                x += spacing
            }
            y += spacing
        }
        return path
    }
}

/// A raised paper card over the note (day card, new-habit form): 12-point corners, soft shadow.
struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).strokeBorder(Palette.ink.opacity(0.08)))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
    }
}

/// A card's title row: the title in Shippori and a close (×) button.
struct CardHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.heading(17))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.inkSecondary)
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
        }
    }
}

// MARK: - Info buttons

/// The small circled **i** (spec-collapsed-note.md §8, info buttons). It toggles an inline
/// `InfoBox`; the text comes from `ScienceRegistry` so every "why" is written once.
struct InfoButton: View {
    let topic: ScienceTopic
    @Binding var isExpanded: Bool

    var body: some View {
        Button { isExpanded.toggle() } label: {
            Text("i")
                .font(.text(10.5, weight: .bold))
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Palette.inkSecondary, lineWidth: 1.2))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(topic.entry.title)
        .accessibilityHint(isExpanded ? "Hides the explanation" : "Shows why")
        .accessibilityValue(isExpanded ? "expanded" : "collapsed")
    }
}

public extension EnvironmentValues {
    /// "More on The Science page →" under an info box: opens The Science tab at that entry.
    /// Nil hides the link (onboarding, where leaving the page would lose your place).
    @Entry var openScience: ((ScienceTopic) -> Void)?
}

/// The explanation an info button opens: title, a few plain sentences, the sources, and a link
/// to the entry on The Science page (spec-science.md, Info button).
struct InfoBox: View {
    let entry: ScienceEntry
    @Environment(\.openScience) private var openScience

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.heading(13.5))
                .foregroundStyle(Palette.ink)
            Text(entry.body)
                .font(.text(11.5))
                .lineSpacing(2)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            SourceLine(sources: entry.sources)
                .font(.text(10.5))
                .foregroundStyle(Palette.inkSecondary)
            if let openScience {
                Button("More on The Science page →") { openScience(entry.topic) }
                    .buttonStyle(LinkButtonStyle(size: 11))
                    .accessibilityIdentifier("info.more.\(entry.topic.rawValue)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raisedPaper, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.track))
        // `.contain`, not `.combine`: the link inside must stay a button for VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("info.\(entry.topic.rawValue)")
    }
}

/// "Lally, van Jaarsveld, Potts & Wardle, European Journal of Social Psychology (2010) · James
/// Clear, *Atomic Habits* (2018)": book titles in italics.
struct SourceLine: View {
    let sources: [Source]

    var body: some View {
        sources.enumerated().reduce(Text(verbatim: "")) { line, item in
            let (index, source) = item
            let work = source.isBook ? Text(verbatim: source.work).italic() : Text(verbatim: source.work)
            return Text("\(line)\(index == 0 ? "" : " · ")\(source.authors), \(work) (\(String(source.year)))")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons and fields

/// An indigo text link ("+ Add habit", "Show all habits").
struct LinkButtonStyle: ButtonStyle {
    var color: ColorToken = Palette.indigo
    var size: CGFloat = 12.5

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.text(size, weight: .medium))
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
    }
}

/// The filled indigo button ("Add habit", "Yes, edit this day").
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.text(13, weight: .bold))
            .foregroundStyle(Palette.raisedPaper)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Palette.indigo, in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// A choice chip ("Track an amount", "Every day", weekday toggles).
struct ChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.text(12, weight: isSelected ? .bold : .regular))
            .foregroundStyle(isSelected ? Palette.indigo : Palette.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? AnyShapeStyle(Palette.indigo.opacity(0.10)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Palette.indigo : Palette.fieldLine, lineWidth: isSelected ? 1.4 : 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// A plain text field whose placeholder is drawn in pencil behind it. (The system field draws its
/// prompt in the field's text color once one is set, so placeholders looked like typed values.)
struct PromptedTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var font: Font
    var accessibilityLabel: String
    var identifier: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(Palette.pencil)
                    .lineLimit(axis == .vertical ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextField(text: $text, prompt: Text(""), axis: axis) { Text(accessibilityLabel) }
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(Palette.ink)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier)
        }
    }
}

/// A text field drawn as a line on the paper: no box, an underline that turns indigo on focus.
struct UnderlinedField: View {
    let placeholder: String
    @Binding var text: String
    var font: Font = .text(14)
    var accessibilityLabel: String
    var identifier: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        PromptedTextField(placeholder: placeholder, text: $text, font: font, accessibilityLabel: accessibilityLabel,
                          identifier: identifier)
            .focused($isFocused)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isFocused ? AnyShapeStyle(Palette.indigo) : AnyShapeStyle(Palette.fieldLine))
                    .frame(height: 1)
            }
    }
}

/// The dashed handwritten line for a day's note.
struct DashedUnderline: View {
    var body: some View {
        Line()
            .stroke(Palette.fieldLine, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}
