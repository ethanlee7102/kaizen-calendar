import Core
import SwiftUI

/// The paper card for one day (spec-collapsed-note.md §6): check off or backfill habits, rest
/// today, and the day's note. Today and the 2 days before are editable; older days are
/// read-only until "Change anyway" is confirmed, which unlocks the whole card.
struct DayCardView: View {
    let card: DayCard
    let actions: DayCardActions
    let close: () -> Void

    @State private var editing: DayCardEditing
    @State private var isConfirming = false

    init(card: DayCard, actions: DayCardActions, close: @escaping () -> Void) {
        self.card = card
        self.actions = actions
        self.close = close
        _editing = State(initialValue: DayCardEditing(openedAs: card.access))
    }

    private var isEditable: Bool { editing.isEditable(now: card.access) }
    private var changeAnyway: Bool { editing.needsChangeAnyway(now: card.access) }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: card.title, close: close)
                if card.rows.isEmpty {
                    Text("No habits were scheduled this day.")
                        .font(.text(12))
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    VStack(spacing: 2) {
                        ForEach(card.rows) { row in rowView(row) }
                    }
                }
                if editing.showsReadOnlyNotice(now: card.access) { readOnlyNotice }
                noteSection
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(card.title)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("dayCard")
    }

    private func rowView(_ row: DayCard.Row) -> some View {
        let canToggle = isEditable && row.isChangeable
        return HStack(spacing: 8) {
            Button {
                actions.setDone(row.id, card.day, !row.isDone, changeAnyway)
            } label: {
                LeafMark(state: row.leaf, size: 30)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                    .animation(.easeInOut(duration: 0.25), value: row.leaf)
            }
            .buttonStyle(.plain)
            .disabled(!canToggle)
            .accessibilityLabel(row.name)
            .accessibilityValue(row.status)
            .accessibilityHint(canToggle ? (row.isDone ? "Unchecks it" : "Checks it off") : "")
            .accessibilityIdentifier("dayCard.leaf.\(row.name)")
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.text(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(row.status)
                    .font(.text(11))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .accessibilityHidden(true) // the leaf button says it
            Spacer(minLength: 4)
            if let rest = row.restAction {
                Button(rest == .rest ? "Rest today" : "Undo rest") {
                    actions.setRested(row.id, card.day, rest == .rest)
                }
                .buttonStyle(LinkButtonStyle(color: Palette.mossText, size: 11.5))
                .accessibilityIdentifier("dayCard.rest.\(row.name)")
            }
        }
        .frame(minHeight: 40)
    }

    @ViewBuilder private var readOnlyNotice: some View {
        if isConfirming {
            VStack(alignment: .leading, spacing: 8) {
                Text("Changing older days rewrites your history. Only do it if you really forgot to log.")
                    .font(.text(11.5))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Yes, edit this day") {
                        editing.unlocked = true
                        isConfirming = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("dayCard.confirmChange")
                    Button("Cancel") { isConfirming = false }
                        .buttonStyle(LinkButtonStyle(color: Palette.inkSecondary))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 6) {
                Text("Older than 2 days, so it’s read-only.")
                    .font(.text(11.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Change anyway") { isConfirming = true }
                    .buttonStyle(LinkButtonStyle(size: 11.5))
                    .accessibilityIdentifier("dayCard.changeAnyway")
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Note")
                .font(.text(11.5))
                .foregroundStyle(Palette.inkSecondary)
            if isEditable {
                NoteTextField(stored: card.note, save: { actions.setNote(card.day, $0, changeAnyway) }) { text, focus in
                    PromptedTextField(placeholder: "One thing to do 1% better tomorrow…", text: text, axis: .vertical,
                                      font: .handwriting(13.5), accessibilityLabel: "Note for \(card.title)",
                                      identifier: "dayCard.note")
                    .lineLimit(1...4)
                    .focused(focus)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 2)
                    .overlay(alignment: .bottom) { DashedUnderline() }
                }
            } else {
                Text(card.note.isEmpty ? "No note." : card.note)
                    .font(card.note.isEmpty ? .text(12) : .handwriting(13.5))
                    .foregroundStyle(card.note.isEmpty ? Palette.inkSecondary : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dayCard.noteText")
            }
        }
    }
}
