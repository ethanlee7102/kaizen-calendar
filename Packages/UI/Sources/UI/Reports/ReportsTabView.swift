import Core
import SwiftUI

/// The Reports tab (spec-reports.md, Reports tab): new letters at the top, then the archive
/// grouped by month, each with its seal, dates and an "unread" marker. Clicking one opens it.
struct ReportsTabView: View {
    let input: NotebookInput
    let actions: NotebookActions
    @Bindable var navigation: NotebookNavigation
    /// The notebook window is showing: only then does showing a letter count as opening it.
    let isOpen: Bool
    let request: (LetterRequest) -> Void

    var body: some View {
        if let id = navigation.openLetter, let page = input.letterPage(id) {
            LetterView(page: page, actions: actions, back: { navigation.openLetter = nil }, request: request)
                .id(id)
                .task(id: Visit(id: id, isOpen: isOpen, isUnread: input.letter(id)?.isUnread == true)) {
                    if isOpen, input.letter(id)?.isUnread == true { actions.letters.opened(id) }
                }
        } else {
            list
        }
    }

    private struct Visit: Hashable {
        let id: UUID
        let isOpen: Bool
        let isUnread: Bool
    }

    private var list: some View {
        let archive = input.letterArchive
        return VStack(alignment: .leading, spacing: 18) {
            Text("Reports")
                .font(.heading(26))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if archive.isEmpty {
                Text(LetterArchive.emptyLine)
                    .font(.handwriting(15))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityIdentifier("reports.empty")
            }
            if !archive.new.isEmpty {
                group("New", letters: archive.new)
            }
            ForEach(archive.months) { month in
                group(month.title, letters: month.letters)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Contain: an identifier on a plain stack would replace its rows' own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports")
    }

    private func group(_ title: String, letters: [LetterInput]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.text(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, 2)
            ForEach(letters) { letter in
                Button {
                    actions.used()
                    navigation.openLetter = letter.id
                } label: {
                    LetterRow(letter: letter)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(letter.isUnread ? "\(letter.title), \(letter.archiveLine), unread" : "\(letter.title), \(letter.archiveLine)")
                .accessibilityIdentifier("reports.letter")
            }
        }
    }
}

private struct LetterRow: View {
    let letter: LetterInput
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            LetterSeal(kind: letter.kind, unread: letter.isUnread)
                .frame(width: 24, height: 24)
                .opacity(letter.isUnread ? 1 : 0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(letter.title)
                    .font(.text(13.5, weight: letter.isUnread ? .bold : .medium))
                    .foregroundStyle(Palette.ink)
                Text(letter.archiveLine)
                    .font(.text(11.5))
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            if letter.isUnread {
                Text("unread")
                    .font(.text(10.5, weight: .bold))
                    .foregroundStyle(Palette.vermilion)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 520, alignment: .leading)
        .background(isHovered ? AnyShapeStyle(Palette.selectedName.opacity(0.6)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
