import Core
import SwiftUI
import UniformTypeIdentifiers

/// The Habits tab (spec-goals-list.md): the active list (drag to reorder), + New habit, the
/// inactive list, and the selected habit's page.
struct HabitsTabView: View {
    let input: NotebookInput
    let actions: NotebookActions
    @Bindable var navigation: NotebookNavigation
    let present: (NotebookSheet) -> Void

    @State private var showsWhyFive = false
    @State private var dropTarget: HabitID?

    private var note: NoteInput { input.note }
    private var selection: HabitID? { note.habitSelection(keeping: navigation.selectedHabit) }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            list
                .frame(width: 176)
            if let selection, let page = note.habitPage(selection, trendSpan: navigation.trendSpan) {
                HabitPageView(page: page, addHabitState: note.addHabitState, actions: actions,
                              trendSpan: $navigation.trendSpan, present: present) { offset in
                    if let order = note.activeOrder(moving: page.id, by: offset) {
                        actions.used()
                        actions.reorder(order)
                    }
                }
                .id(page.id)
            } else {
                emptyPage
            }
        }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(note.activeTitle)
            ForEach(note.activeItems) { item in
                row(item, draggable: note.activeItems.count > 1)
            }
            addHabit
            if note.activeItems.count > 1 {
                Text("Drag to reorder")
                    .font(.handwriting(11.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 10)
            }
            let inactive = note.inactiveItems
            if !inactive.isEmpty {
                sectionLabel("Inactive").padding(.top, 10)
                ForEach(inactive) { item in row(item, draggable: false) }
            }
            if !input.unreadableHabits.isEmpty {
                sectionLabel("Couldn’t be read").padding(.top, 10)
                ForEach(input.unreadableHabits) { habit in
                    HStack {
                        Text(habit.name)
                            .font(.text(13))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button("Delete") {
                            actions.used()
                            actions.delete(habit.id)
                        }
                        .buttonStyle(LinkButtonStyle(color: Palette.dangerText, size: 11.5))
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.text(10.5, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Palette.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: HabitListItem, draggable: Bool) -> some View {
        HabitListRow(item: item, isSelected: item.id == selection, showsHandle: draggable,
                     isDropTarget: dropTarget == item.id) {
            actions.used()
            navigation.selectedHabit = item.id
        }
        .contextMenu {
            if item.status == nil {
                Button("Move Up") { move(item.id, by: -1) }
                    .disabled(note.activeOrder(moving: item.id, by: -1) == nil)
                Button("Move Down") { move(item.id, by: 1) }
                    .disabled(note.activeOrder(moving: item.id, by: 1) == nil)
            }
        }
        .modifier(ReorderDrag(id: item.id, isEnabled: draggable, dropTarget: $dropTarget) { dragged in
            guard let order = note.activeOrder(moving: dragged, onto: item.id) else { return false }
            actions.used()
            actions.reorder(order)
            return true
        })
    }

    private func move(_ id: HabitID, by offset: Int) {
        guard let order = note.activeOrder(moving: id, by: offset) else { return }
        actions.used()
        actions.reorder(order)
    }

    @ViewBuilder private var addHabit: some View {
        if note.addHabitState == .atLimit {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 4) {
                    Text("You’re at 5 habits. Graduate one that feels automatic to make room.")
                        .font(.text(11.5))
                        .lineSpacing(2)
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    InfoButton(topic: .whyFive, isExpanded: $showsWhyFive)
                }
                if showsWhyFive { InfoBox(entry: ScienceTopic.whyFive.entry) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        } else {
            Button("+ New habit") {
                actions.used()
                present(.newHabit)
            }
            .buttonStyle(LinkButtonStyle(size: 13))
            .padding(.horizontal, 8)
            .accessibilityIdentifier("habits.new")
        }
    }

    private var emptyPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No habits yet.")
                .font(.heading(24))
                .foregroundStyle(Palette.ink)
            Text("Start with one small thing.")
                .font(.handwriting(15))
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One habit in the list: drag handle on hover, a tiny brush circle, the name and "Day N", or the
/// inactive label.
private struct HabitListRow: View {
    let item: HabitListItem
    let isSelected: Bool
    let showsHandle: Bool
    let isDropTarget: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                if showsHandle {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .opacity(isHovered ? 1 : 0)
                        .frame(width: 10)
                        .accessibilityHidden(true)
                }
                ZStack {
                    Circle().stroke(Palette.track, lineWidth: 1.6)
                    BrushArc(progress: item.journey.progress)
                        .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
                Text(item.name)
                    .font(.text(14, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let status = item.statusText {
                    Text(status)
                        .font(.text(10.5, weight: item.status == .graduated ? .bold : .regular))
                        .foregroundStyle(item.status == .graduated ? Palette.goldText : Palette.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Text(item.dayText)
                        .font(.text(11))
                        .monospacedDigit()
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize()
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(isSelected ? AnyShapeStyle(Palette.selectedName) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .top) {
                if isDropTarget {
                    Rectangle().fill(Palette.indigo).frame(height: 2).offset(y: -2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(item.statusText.map { "\(item.name), \($0)" } ?? "\(item.name), \(item.dayText)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("habits.row.\(item.name)")
    }
}

/// Drag a habit row onto another to put it in that one's place.
private struct ReorderDrag: ViewModifier {
    let id: HabitID
    let isEnabled: Bool
    @Binding var dropTarget: HabitID?
    let drop: (HabitID) -> Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .draggable(id.description)
                .dropDestination(for: String.self) { items, _ in
                    dropTarget = nil
                    guard let text = items.first, let uuid = UUID(uuidString: text) else { return false }
                    return drop(HabitID(uuid))
                } isTargeted: { targeted in
                    if targeted { dropTarget = id } else if dropTarget == id { dropTarget = nil }
                }
        } else {
            content
        }
    }
}
