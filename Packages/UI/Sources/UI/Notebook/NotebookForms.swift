import Core
import SwiftUI

/// "Edit": name, identity and schedule (the unit is shown, not editable). Saves on "Save" (a form, unlike
/// settings, so half-typed names never land).
struct HabitEditForm: View {
    @State var draft: HabitEditDraft
    let close: () -> Void
    let save: (HabitEditDraft.Changes) throws -> Void

    @State private var failed = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Edit habit", close: close)
                labeled("Name") {
                    UnderlinedField(placeholder: "e.g. Read", text: $draft.name, accessibilityLabel: "Name",
                                    identifier: "editForm.name")
                        .focused($nameFocused)
                }
                if let unitNote = draft.unitNote {
                    Text(unitNote)
                        .font(.text(11))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("editForm.unitNote")
                }
                VStack(alignment: .leading, spacing: 4) {
                    ScheduleFields(choice: $draft.scheduleChoice, weekdays: $draft.weekdays, identifierPrefix: "editForm")
                    if let note = draft.scheduleNote {
                        Text(note)
                            .font(.text(11))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                labeled("Identity (optional)") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("I’m")
                            .font(.handwriting(14))
                            .foregroundStyle(Palette.ink)
                        UnderlinedField(placeholder: "a reader", text: $draft.identity, font: .handwriting(14),
                                        accessibilityLabel: "Identity: I’m", identifier: "editForm.identity")
                    }
                }
                FormButtons(failed: failed, canSave: draft.changes != nil, saveTitle: "Save", close: close) {
                    guard let changes = draft.changes else { return }
                    attempt { try save(changes) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit habit")
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("editForm")
        .task {
            await Task.yield()
            nameFocused = true
        }
    }

    private func attempt(_ write: () throws -> Void) {
        do {
            try write()
            close()
        } catch {
            failed = true
        }
    }
}

/// "Change target": the new amount from today on.
struct TargetForm: View {
    @State var draft: TargetDraft
    let close: () -> Void
    let save: (Int) throws -> Void

    @State private var failed = false
    @State private var expandedInfo = false
    @FocusState private var focused: Bool

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Change target", close: close)
                Text("Now \(draft.current) \(draft.unit). The new target starts today; past days keep theirs.")
                    .font(.text(12))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    UnderlinedField(placeholder: String(draft.current), text: Binding(
                        get: { draft.text }, set: { draft.text = HabitDraft.filteredTarget($0) }),
                        accessibilityLabel: "New target", identifier: "targetForm.amount")
                        .focused($focused)
                        .frame(width: 72)
                    Text(draft.unit)
                        .font(.text(14))
                        .foregroundStyle(Palette.ink)
                }
                if let hint = draft.hint {
                    Text(hint).font(.text(11)).foregroundStyle(Palette.inkSecondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Start smaller than you think.")
                            .font(.handwriting(12.5))
                            .foregroundStyle(Palette.inkSecondary)
                        InfoButton(topic: .startSmall, isExpanded: $expandedInfo)
                    }
                    if expandedInfo { InfoBox(entry: ScienceTopic.startSmall.entry) }
                }
                FormButtons(failed: failed, canSave: draft.newAmount != nil, saveTitle: "Change target", close: close) {
                    guard let amount = draft.newAmount else { return }
                    do {
                        try save(amount)
                        close()
                    } catch {
                        failed = true
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Change target")
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("targetForm")
        .task {
            await Task.yield()
            focused = true
        }
    }
}

/// "Change schedule" (yes/no habits): the new days from today on.
struct ScheduleForm: View {
    @State var draft: ScheduleDraft
    let close: () -> Void
    let save: (Schedule) throws -> Void

    @State private var failed = false

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Change schedule", close: close)
                Text("The new schedule starts today. Past days keep theirs.")
                    .font(.text(12))
                    .foregroundStyle(Palette.inkSecondary)
                ScheduleFields(choice: $draft.choice, weekdays: $draft.weekdays, identifierPrefix: "scheduleForm")
                FormButtons(failed: failed, canSave: draft.newSchedule != nil, saveTitle: "Change schedule", close: close) {
                    guard let schedule = draft.newSchedule else { return }
                    do {
                        try save(schedule)
                        close()
                    } catch {
                        failed = true
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Change schedule")
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("scheduleForm")
    }
}

/// "Delete Read and all 41 days of history?" (spec-goals-list.md). Undo stays available for
/// about 10 seconds afterwards, so there's no typing the name to confirm.
struct DeleteConfirmationCard: View {
    let confirmation: DeleteConfirmation
    let close: () -> Void
    let moveToInactive: () -> Void
    let delete: () -> Void

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: confirmation.title, close: close)
                Text(confirmation.message)
                    .font(.text(12.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if confirmation.offersMoveToInactive {
                        Button("Move to inactive", action: moveToInactive)
                            .buttonStyle(PaperButtonStyle())
                            .accessibilityIdentifier("deleteCard.moveToInactive")
                    } else {
                        Button("Keep it", action: close)
                            .buttonStyle(PaperButtonStyle())
                    }
                    Spacer()
                    Button("Delete forever", action: delete)
                        .buttonStyle(DangerButtonStyle())
                        .accessibilityIdentifier("deleteCard.delete")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(confirmation.title)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("deleteCard")
    }
}

/// Cancel · [Save], and the failure line.
private struct FormButtons: View {
    let failed: Bool
    let canSave: Bool
    let saveTitle: String
    let close: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if failed {
                Text("Couldn’t save this. Please try again.")
                    .font(.text(11.5))
                    .foregroundStyle(Palette.dangerText)
            }
            HStack {
                Button("Cancel", action: close)
                    .buttonStyle(LinkButtonStyle(color: Palette.inkSecondary))
                Spacer()
                Button(saveTitle, action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("form.save")
            }
        }
    }
}

private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.text(11.5))
            .foregroundStyle(Palette.inkSecondary)
        content()
    }
}

/// "Delete forever": the filled danger button.
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.text(13, weight: .bold))
            .foregroundStyle(Palette.raisedPaper)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Palette.dangerText, in: RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
