import Core
import SwiftUI

/// The new-habit form (spec-collapsed-note.md §8): name, type, target, schedule, identity, the
/// hints with their info buttons, and a live preview of the row. It scrolls inside itself when
/// it's taller than the screen allows (the note itself never scrolls).
struct HabitFormView: View {
    let addHabitState: HabitRules.AddHabitState
    /// Adds the habit; throws if it couldn't be saved.
    let add: (HabitDraft.Request) throws -> Void
    let close: () -> Void
    /// On a page (onboarding) rather than a card over the note: no shadow, not modal.
    var isInline = false

    @State private var draft = HabitDraft()
    @State private var showsNudge = true
    @State private var expandedInfo: ScienceTopic?
    @State private var failed = false
    @State private var contentHeight: CGFloat = 0
    @FocusState private var nameFocused: Bool
    @Environment(\.noteMaxHeight) private var maxHeight

    var body: some View {
        // The form's own height, capped by the space the note has (less the card's insets).
        let cap = max(maxHeight - 20, 240)
        ScrollView(.vertical) {
            form
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentHeight == 0 ? nil : min(contentHeight, cap))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius))
        .shadow(color: .black.opacity(isInline ? 0.06 : 0.18), radius: isInline ? 4 : 14, y: isInline ? 2 : 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("New habit")
        .accessibilityAddTraits(isInline ? [] : .isModal)
        .accessibilityIdentifier("habitForm")
        // After the first update: set while the field is still being inserted, focus doesn't take
        // (the panel kept first responder; found with the Phase 4 review's UI test).
        .task {
            await Task.yield()
            nameFocused = true
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "New habit", close: close)
            if addHabitState == .allowedWithNudge, showsNudge { nudge }
            field("Name") {
                UnderlinedField(placeholder: "e.g. Read", text: $draft.name, accessibilityLabel: "Name",
                                identifier: "habitForm.name")
                    .focused($nameFocused)
            }
            target
            schedule
            identity
            preview
            if failed {
                Text("Couldn’t add this habit. Please try again.")
                    .font(.text(11.5))
                    .foregroundStyle(Palette.dangerText)
            }
            HStack {
                Button("Cancel", action: close)
                    .buttonStyle(LinkButtonStyle(color: Palette.inkSecondary))
                Spacer()
                Button("Add habit", action: submit)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.request == nil)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("habitForm.add")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Palette.raisedPaper)
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius).strokeBorder(Palette.ink.opacity(0.08)))
    }

    private func submit() {
        guard let request = draft.request else { return }
        do {
            try add(request)
            close()
        } catch {
            failed = true
        }
    }

    // MARK: Sections

    /// Adding a 4th (or 5th) habit: "Fogg recommends starting with three." Dismissible.
    private var nudge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                Text("Fogg recommends starting with three. Consider waiting until these feel easy.")
                    .font(.handwriting(12.5))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                infoButton(.startWithThree)
                Button { showsNudge = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel("Dismiss")
            }
            infoBox(.startWithThree)
        }
        .padding(10)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("habitForm.nudge")
    }

    private var target: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Target")
            HStack(spacing: 6) {
                chip("Track an amount", selected: draft.kind == .amount) { draft.kind = .amount }
                chip("Just do it", selected: draft.kind == .yesNo) { draft.kind = .yesNo }
            }
            if draft.kind == .amount {
                HStack(spacing: 10) {
                    UnderlinedField(placeholder: "10", text: Binding(
                        get: { draft.target }, set: { draft.target = HabitDraft.filteredTarget($0) }),
                        accessibilityLabel: "Target amount", identifier: "habitForm.target")
                        .frame(width: 64)
                    UnderlinedField(placeholder: "pages", text: $draft.unit, accessibilityLabel: "Target unit",
                                    identifier: "habitForm.unit")
                }
            }
            if let targetHint = draft.targetHint {
                Text(targetHint)
                    .font(.text(11))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityIdentifier("habitForm.targetHint")
            }
            hint("Start smaller than you think.", topic: .startSmall)
        }
    }

    private var schedule: some View {
        ScheduleFields(choice: $draft.scheduleChoice, weekdays: $draft.weekdays)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            label("Identity (optional)")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("I’m")
                    .font(.handwriting(14))
                    .foregroundStyle(Palette.ink)
                UnderlinedField(placeholder: "a reader", text: $draft.identity, font: .handwriting(14),
                                accessibilityLabel: "Identity: I’m", identifier: "habitForm.identity")
            }
            hint("Who does this habit make you?", topic: .identity)
        }
    }

    private var preview: some View {
        HStack(spacing: 8) {
            LeafMark(state: .unchecked, size: 30)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(draft.previewName)
                    .font(.text(14, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(draft.previewDetails)
                    .font(.text(11))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(draft.previewName). \(draft.previewDetails)")
    }

    // MARK: Pieces

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            content()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.text(11.5))
            .foregroundStyle(Palette.inkSecondary)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ChipStyle(isSelected: selected))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func hint(_ text: String, topic: ScienceTopic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(text)
                    .font(.handwriting(12.5))
                    .foregroundStyle(Palette.inkSecondary)
                infoButton(topic)
            }
            infoBox(topic)
        }
    }

    private func infoButton(_ topic: ScienceTopic) -> some View {
        InfoButton(topic: topic, isExpanded: Binding(
            get: { expandedInfo == topic }, set: { expandedInfo = $0 ? topic : nil }))
    }

    @ViewBuilder private func infoBox(_ topic: ScienceTopic) -> some View {
        if expandedInfo == topic { InfoBox(entry: topic.entry) }
    }
}

/// "Schedule": Every day / Specific days, and the weekday chips (the new-habit form and the
/// notebook's edit forms).
struct ScheduleFields: View {
    @Binding var choice: HabitDraft.ScheduleChoice
    @Binding var weekdays: WeekdaySet
    var identifierPrefix = "habitForm"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Schedule")
                .font(.text(11.5))
                .foregroundStyle(Palette.inkSecondary)
            HStack(spacing: 6) {
                chip("Every day", selected: choice == .everyDay) { choice = .everyDay }
                chip("Specific days", selected: choice == .specificDays) { choice = .specificDays }
            }
            if choice == .specificDays {
                HStack(spacing: 4) {
                    ForEach(Weekday.allCases, id: \.self) { weekday in
                        let on = weekdays.contains(weekday)
                        Button {
                            if on { weekdays.remove(WeekdaySet(weekday)) } else { weekdays.insert(WeekdaySet(weekday)) }
                        } label: {
                            Text(weekday.letter).frame(width: 14)
                        }
                        .buttonStyle(ChipStyle(isSelected: on))
                        .accessibilityLabel(weekday.shortName)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        .accessibilityIdentifier("\(identifierPrefix).weekday.\(weekday.shortName)")
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(ChipStyle(isSelected: selected))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
