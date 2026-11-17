#if canImport(AppKit)
import AppKit
#endif
import Core
import SwiftUI

/// A card over the notebook's page.
enum NotebookSheet: Hashable {
    case dayCard(DayKey)
    case newHabit
    case edit(HabitID)
    /// `prefill`: "Choose my own" on a suggestion. `letter`: the change is a day-66 or re-check
    /// letter's decision.
    case changeTarget(HabitID, prefill: Int? = nil, letter: UUID? = nil)
    case changeSchedule(HabitID, prefill: Schedule? = nil, letter: UUID? = nil)
    case delete(HabitID)
}

public extension EnvironmentValues {
    /// The Settings tab's expand/collapse shortcut recorder (the app provides it: the recorder
    /// is macOS-only and lives outside this package).
    @Entry var shortcutRecorder: AnyView?
}

/// The expanded notebook (spec-expanded-structure.md): a paper page with divider tabs sticking
/// out of its right edge (Calendar · Habits · Reports · Stamp book · The Science · Settings).
/// Up and down arrows move between tabs; cards (day card, forms, confirmations) open over the
/// page.
public struct NotebookView: View {
    public let input: NotebookInput
    public let actions: NotebookActions
    @Bindable public var navigation: NotebookNavigation
    /// The notebook window is showing. Only then does visiting a tab count (a tab "appears" in
    /// the hidden window at launch too).
    public let isOpen: Bool

    @State private var sheet: NotebookSheet?
    @FocusState private var tabsFocused: Bool
    /// The arrow keys were used since the last click: show the focus ring on the selected tab
    /// (like the web's :focus-visible, so a mouse user never sees it).
    @State private var usesKeyboard = false

    public init(input: NotebookInput, actions: NotebookActions, navigation: NotebookNavigation, isOpen: Bool) {
        self.input = input
        self.actions = actions
        self.navigation = navigation
        self.isOpen = isOpen
    }

    /// Initial UI state, for snapshot tests.
    init(input: NotebookInput, actions: NotebookActions, navigation: NotebookNavigation, isOpen: Bool, sheet: NotebookSheet?) {
        self.init(input: input, actions: actions, navigation: navigation, isOpen: isOpen)
        _sheet = State(initialValue: sheet)
    }

    private var tabLeading: CGFloat { Metrics.notebookPageWidth - 8 }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(NotebookTab.allCases.enumerated()), id: \.element) { index, tab in
                tabButton(tab)
                    // A card is open: the tabs wait too, like the page (Phase 5 review).
                    .disabled(sheet != nil)
                    .accessibilityHidden(sheet != nil)
                    .offset(x: tabLeading, y: 54 + CGFloat(index) * 50)
                    .zIndex(tab == navigation.tab ? 3 : 1)
            }
            page
                .frame(width: Metrics.notebookPageWidth)
                .frame(maxHeight: .infinity)
                .zIndex(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusable()
        .focused($tabsFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            // Not while a text field is being edited: arrows in a letter's answer field move the
            // cursor, not the tab (Phase 6, found by a UI test). The focus state doesn't tell:
            // it stays true while a field inside the notebook has the keyboard.
            guard sheet == nil, !Self.isEditingText else { return .ignored }
            usesKeyboard = true
            select(navigation.tab.moved(by: press.key == .upArrow ? -1 : 1))
            return .handled
        }
        .onChange(of: isOpen, initial: true) {
            guard isOpen else { return }
            // However it was opened (note, Dock, shortcut, menu), opening counts as using the
            // note for "Welcome back" (Phase 5 review).
            actions.used()
            navigation.opened(waitingLetter: input.envelopeLetter?.id)
            focusTabs()
        }
        .task(id: StampVisit(isOpen: isOpen, tab: navigation.tab, hasNew: input.newMarkers.contains(.stampBook))) {
            if isOpen, navigation.tab == .stampBook, input.newMarkers.contains(.stampBook) { actions.visitStampBook() }
        }
        .onChange(of: input.today) {
            if case .dayCard(let day) = sheet, day > input.today { sheet = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notebook")
    }

    /// A text field has the keyboard (AppKit's field editor is the first responder).
    private static var isEditingText: Bool {
        #if canImport(AppKit)
        NSApp?.keyWindow?.firstResponder is NSText
        #else
        false
        #endif
    }

    private struct StampVisit: Hashable {
        let isOpen: Bool
        let tab: NotebookTab
        let hasNew: Bool
    }

    private func focusTabs() {
        Task {
            await Task.yield()
            tabsFocused = true
        }
    }

    private func select(_ tab: NotebookTab) {
        actions.used()
        withAnimation(.easeInOut(duration: 0.15)) { navigation.tab = tab }
    }

    // MARK: Page

    private var page: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical) {
                tabContent
                    .padding(.horizontal, 28)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(navigation.tab) // each tab starts at the top
        }
        .disabled(sheet != nil)
        .accessibilityHidden(sheet != nil)
        .background(PaperBackground().shadow(color: .black.opacity(0.28), radius: 18, y: 10))
        .overlay {
            if sheet != nil {
                RoundedRectangle(cornerRadius: Metrics.noteCornerRadius)
                    .fill(Palette.paper.opacity(0.6))
                    .transition(.opacity)
            }
        }
        .overlay { sheetView.padding(24) }
        .overlay(alignment: .bottom) {
            if let name = input.pendingDeletion {
                UndoToast(name: name) {
                    actions.used()
                    actions.undoDelete()
                }
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: sheet)
        .animation(.easeOut(duration: 0.2), value: input.pendingDeletion)
        .onChange(of: input.pendingDeletion) {
            // The toast doesn't take focus, so VoiceOver users hear that Undo is there.
            if let name = input.pendingDeletion {
                AccessibilityNotification.Announcement("\(name) deleted. Undo is available for a few seconds.").post()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrushArc(progress: 0.93)
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                .frame(width: 15, height: 15)
                .padding(2.5)
                .accessibilityHidden(true)
            Text("66 Days")
                .font(.heading(15))
                .foregroundStyle(Palette.ink)
            Spacer()
            Button {
                actions.collapse()
            } label: {
                CollapseIcon()
                    .stroke(Palette.inkSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 16, height: 16)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
            .accessibilityIdentifier("notebook.collapse")
            .help("Collapse (Esc)")
        }
        .padding(.top, 14)
        .padding(.leading, 26)
        .padding(.trailing, 18)
    }

    @ViewBuilder private var tabContent: some View {
        switch navigation.tab {
        case .calendar:
            CalendarTabView(input: input.note, navigation: navigation, used: actions.used) { day in
                actions.used()
                sheet = .dayCard(day)
            }
        case .habits:
            HabitsTabView(input: input, actions: actions, navigation: navigation) { sheet = $0 }
        case .reports:
            ReportsTabView(input: input, actions: actions, navigation: navigation, isOpen: isOpen) { request in
                actions.used()
                sheet = Self.sheet(for: request)
            }
        case .stampBook:
            StampBookTabView(input: input, actions: actions)
        case .science:
            PlaceholderTabView(title: "The Science", line: "Every feature’s reason and its source, in one place.")
        case .settings:
            SettingsTabView(settings: input.settings, actions: actions)
        }
    }

    // MARK: Cards

    @ViewBuilder private var sheetView: some View {
        let close = { sheet = nil }
        Group {
            switch sheet {
            case .dayCard(let day):
                DayCardView(card: input.note.dayCard(for: day), actions: usedActions(actions.dayCard), close: close)
                    .id(day)
            case .newHabit:
                HabitFormView(addHabitState: input.note.addHabitState, add: { request in
                    actions.used()
                    let id = try actions.addHabit(request)
                    navigation.showHabit(id)
                }, close: close)
                .environment(\.noteMaxHeight, Metrics.expandedSize.height - 48)
            case .edit(let id):
                if let habit = input.note.habit(id) {
                    HabitEditForm(draft: HabitEditDraft(habit: habit, today: input.today), close: close) {
                        actions.used()
                        try actions.editHabit(id, $0)
                    }
                }
            case .changeTarget(let id, let prefill, let letter):
                if case .target(let current, let unit)? = input.note.habitPage(id)?.primaryChange {
                    TargetForm(draft: TargetDraft(current: current, unit: unit, prefill: prefill), close: close) {
                        actions.used()
                        if let letter {
                            try actions.letters.decide(letter, .changeTarget($0))
                        } else {
                            try actions.changeTarget(id, $0)
                        }
                    }
                }
            case .changeSchedule(let id, let prefill, let letter):
                if let habit = input.note.habit(id) {
                    ScheduleForm(draft: ScheduleDraft(current: habit.history.schedule(on: input.today), prefill: prefill),
                                 close: close) {
                        actions.used()
                        if let letter {
                            try actions.letters.decide(letter, .changeSchedule($0))
                        } else {
                            try actions.changeSchedule(id, $0)
                        }
                    }
                }
            case .delete(let id):
                if let confirmation = input.note.deleteConfirmation(id) {
                    DeleteConfirmationCard(confirmation: confirmation, close: close, moveToInactive: {
                        actions.used()
                        actions.deactivate(id)
                        close()
                    }, delete: {
                        actions.used()
                        actions.delete(id)
                        close()
                    })
                }
            case nil:
                EmptyView()
            }
        }
        .frame(width: Metrics.notebookCardWidth)
        .transition(.opacity.combined(with: .offset(y: 6)))
    }

    /// The card a letter's button opens.
    static func sheet(for request: LetterRequest) -> NotebookSheet? {
        switch request {
        case .chooseTarget(let suggestion):
            guard case .target(_, let to) = suggestion.change else { return nil }
            return .changeTarget(suggestion.habitID, prefill: to)
        case .chooseSchedule(let suggestion):
            guard case .schedule(_, let to) = suggestion.change else { return nil }
            return .changeSchedule(suggestion.habitID, prefill: to)
        case .decideTarget(let letter, let habit):
            return .changeTarget(habit, letter: letter)
        case .decideSchedule(let letter, let habit):
            return .changeSchedule(habit, letter: letter)
        }
    }

    private func usedActions(_ card: DayCardActions) -> DayCardActions {
        let used = actions.used
        return DayCardActions(
            setDone: { used(); card.setDone($0, $1, $2, $3) },
            setRested: { used(); card.setRested($0, $1, $2) },
            setNote: { used(); card.setNote($0, $1, $2) })
    }

    // MARK: Tabs

    private func tabButton(_ tab: NotebookTab) -> some View {
        let selected = tab == navigation.tab
        let isNew = input.newMarkers.contains(tab)
        return Button {
            usesKeyboard = false
            select(tab)
        } label: {
            // The marker sits under the title: "Stamp book" and "1 new" don't fit side by side.
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.text(13, weight: selected ? .bold : .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if isNew {
                    Text("1 new")
                        .font(.text(9.5, weight: .bold))
                        .foregroundStyle(Palette.onSeal)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Palette.vermilion, in: Capsule())
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 10)
            .frame(width: Metrics.notebookTabWidth, height: 44, alignment: .leading)
            .background(selected ? AnyShapeStyle(Palette.paper) : AnyShapeStyle(Palette.recessedTab),
                        in: UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10))
            .overlay {
                if selected, tabsFocused, usesKeyboard {
                    UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10)
                        .strokeBorder(Palette.indigo, lineWidth: 2)
                        .padding(.leading, 8)
                }
            }
            .shadow(color: .black.opacity(selected ? 0.16 : 0.08), radius: selected ? 5 : 2, x: 2, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isNew ? "\(tab.title), 1 new" : tab.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}

/// The ↙↗ collapse arrows (the expand icon's arrows pointing inwards).
nonisolated struct CollapseIcon: Shape {
    static let svg = SVGPath("M13.5 6.5h-4v-4M9.5 6.5 14 2M2.5 9.5h4v4M6.5 9.5 2 14")
    func path(in rect: CGRect) -> Path { Self.svg.path(in: rect, viewBox: CGSize(width: 16, height: 16)) }
}

/// A tab whose content comes in a later phase.
struct PlaceholderTabView: View {
    let title: String
    let line: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.heading(24))
                .foregroundStyle(Palette.ink)
            Text(line)
                .font(.handwriting(15))
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 460)
    }
}

/// "Read deleted. Undo" for about 10 seconds after Delete forever (spec-goals-list.md).
struct UndoToast: View {
    let name: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("\(name) deleted.")
                .font(.text(12.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Button("Undo", action: undo)
                .buttonStyle(LinkButtonStyle())
                .accessibilityIdentifier("notebook.undoDelete")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.raisedPaper, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.track))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notebook.undoToast")
    }
}
