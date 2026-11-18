import Core
import SwiftUI

/// The Science tab (spec-science.md): every feature's reason grouped by idea, each with its
/// sources, and the full Sources list with links that open in the browser. "More on The Science
/// page →" in an info box opens it at that entry (`NotebookNavigation.scienceTopic`).
struct ScienceTabView: View {
    let navigation: NotebookNavigation
    let used: () -> Void

    private let page = SciencePage()
    /// The entry an info box's link pointed to: briefly highlighted after scrolling to it.
    @State private var highlighted: ScienceTopic?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(SciencePage.title)
                        .font(.heading(28))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(SciencePage.intro)
                        .font(.text(13))
                        .lineSpacing(3)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 560, alignment: .leading)
                }
                ForEach(page.sections) { section in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(section.group.title)
                            .font(.heading(19))
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.entries, id: \.topic) { entry in
                            EntryView(entry: entry, isHighlighted: highlighted == entry.topic)
                                .id(entry.topic)
                        }
                    }
                }
                sourcesList
            }
            // Take the request, then scroll and highlight in a task keyed by the highlight, so
            // clearing the request doesn't cancel the highlight's timer (Phase 7 review).
            .onChange(of: navigation.scienceTopic, initial: true) {
                guard let topic = navigation.scienceTopic else { return }
                navigation.scienceTopic = nil
                highlighted = topic
            }
            .task(id: highlighted) {
                guard let topic = highlighted else { return }
                // After the page has laid out (it's new when the tab opens).
                await Task.yield()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo(topic, anchor: .top) }
                try? await Task.sleep(for: Self.highlightTime)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.6)) { highlighted = nil }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("science")
    }

    static let highlightTime = Duration.seconds(2.5)

    private var sourcesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Palette.rule).frame(height: 1)
            Text("Sources")
                .font(.heading(19))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 6)
            ForEach(page.sources, id: \.self) { source in
                SourceRow(source: source, used: used)
            }
        }
    }
}

/// One feature: its name, why it's there, and its sources.
private struct EntryView: View {
    let entry: ScienceEntry
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.feature)
                .font(.text(14, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text(entry.body)
                .font(.text(13))
                .lineSpacing(3)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            SourceLine(sources: entry.sources)
                .font(.text(11.5))
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: 600, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHighlighted ? AnyShapeStyle(Palette.selectedName) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, -12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHighlighted ? "highlighted" : "")
        .accessibilityIdentifier("science.\(entry.topic.rawValue)")
    }
}

/// "Lally, van Jaarsveld, Potts & Wardle (2010). How are habits formed: … European Journal of
/// Social Psychology." as a link to the DOI or publisher page.
private struct SourceRow: View {
    let source: Source
    let used: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        let parts = SciencePage.reference(source)
        Button {
            used()
            openURL(source.url)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.lead)
                    .font(.text(12.5, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Group {
                    if source.isBook {
                        Text(verbatim: parts.title).italic()
                    } else {
                        Text(verbatim: parts.title)
                    }
                }
                .font(.text(12.5))
                .foregroundStyle(Palette.ink)
                if let publication = parts.publication {
                    Text(verbatim: publication)
                        .font(.text(12))
                        .italic()
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text(verbatim: source.url.absoluteString)
                    .font(.text(11))
                    .foregroundStyle(Palette.indigo)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 600, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(source.url.absoluteString)
        .accessibilityLabel(SciencePage.spokenReference(source))
        .accessibilityHint("Opens in your browser")
        .accessibilityAddTraits(.isLink)
    }
}
