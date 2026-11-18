import Core
import Foundation

/// The Science tab's content (spec-science.md, The Science page): entries grouped by idea, then
/// every source with its link. Plain values, so the page is tested without drawing it.
nonisolated public struct SciencePage: Hashable, Sendable {
    public struct Section: Hashable, Sendable, Identifiable {
        public let group: ScienceGroup
        public let entries: [ScienceEntry]
        public var id: ScienceGroup { group }
    }

    public let sections: [Section]
    /// Every cited source once, sorted by author.
    public let sources: [Source]

    public static let title = "The Science"
    public static let intro = "Everything here has a reason. Each part of 66 Days is based on research or a book about how habits form. Here’s why each one is there, and where the idea comes from."

    public init() {
        sections = ScienceGroup.allCases.map { Section(group: $0, entries: ScienceRegistry.entries(in: $0)) }
            .filter { !$0.entries.isEmpty }
        sources = ScienceRegistry.allSources
    }

    /// "Lally, van Jaarsveld, Potts & Wardle (2010)" then the title, then where it appeared:
    /// "How are habits formed: … · European Journal of Social Psychology". Books: the book's
    /// title only (it's shown in italics).
    public static func reference(_ source: Source) -> (lead: String, title: String, publication: String?) {
        let lead = "\(source.authors) (\(source.year))"
        if source.isBook { return (lead, source.work, nil) }
        return (lead, source.title ?? source.work, source.title == nil ? nil : source.work)
    }

    /// What VoiceOver reads for a source link, and its hint.
    public static func spokenReference(_ source: Source) -> String {
        let parts = reference(source)
        return [parts.lead, parts.title, parts.publication].compactMap { $0 }.joined(separator: ". ")
    }
}
