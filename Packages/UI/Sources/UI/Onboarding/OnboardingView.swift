import Core
import SwiftUI

/// First launch (spec-onboarding.md): three pages in the notebook window, on the notebook's
/// paper page without its tabs. 1 Welcome (what the app is, "everything has a reason"), 2 the
/// first habit (can't be skipped: the app is empty without one), 3 the note (open at login, day
/// end), then it folds into the note.
public struct OnboardingView: View {
    public let input: OnboardingInput
    public let actions: OnboardingActions
    @Bindable public var flow: OnboardingFlow

    public init(input: OnboardingInput, actions: OnboardingActions, flow: OnboardingFlow) {
        self.input = input
        self.actions = actions
        self.flow = flow
    }

    private var page: OnboardingFlow.Page { flow.page(hasHabits: input.hasHabits) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical) {
                Group {
                    switch page {
                    case .welcome: WelcomePage(begin: { go(to: .firstHabit) })
                    case .firstHabit: FirstHabitPage(input: input, actions: actions, back: { go(to: .welcome) },
                                                     next: { go(to: .yourNote) })
                    case .yourNote: YourNotePage(dayEndHour: input.dayEndHour, actions: actions,
                                                 back: { go(to: .firstHabit) })
                    }
                }
                .padding(.horizontal, 56)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(page) // each page starts at the top
        }
        .frame(width: Metrics.notebookPageWidth)
        .frame(maxHeight: .infinity)
        .background(PaperBackground().shadow(color: .black.opacity(0.28), radius: 18, y: 10))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // No "More on The Science page →" here: leaving would lose your place.
        .environment(\.openScience, nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding")
    }

    private func go(to page: OnboardingFlow.Page) {
        withAnimation(.easeInOut(duration: 0.2)) { flow.go(to: page) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(page.position)
                .font(.text(11.5))
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel("Page \(page.rawValue + 1) of \(OnboardingFlow.Page.allCases.count)")
                .accessibilityIdentifier("onboarding.position")
            Spacer()
            Button(action: actions.collapse) {
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
}

extension EnvironmentValues {
    /// Draws the welcome's brush circle at once (snapshot tests; Reduce Motion does the same).
    @Entry var drawsIntroInstantly = false
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    let begin: () -> Void

    @State private var circleProgress = 0.0
    @State private var showsWhy66 = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.drawsIntroInstantly) private var drawsInstantly

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // The brush circle draws itself as the page opens.
            BrushArc(progress: circleProgress)
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)
                .onAppear {
                    if reduceMotion || drawsInstantly {
                        circleProgress = 0.93
                    } else {
                        withAnimation(.easeOut(duration: 1.1).delay(0.15)) { circleProgress = 0.93 }
                    }
                }
            Text("66 Days")
                .font(.heading(34))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            paragraph(OnboardingInput.welcomeLead)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    paragraph(OnboardingInput.welcomeResearch)
                    InfoButton(topic: .why66, isExpanded: $showsWhy66)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                        .accessibilityIdentifier("onboarding.why66")
                }
                if showsWhy66 { InfoBox(entry: ScienceTopic.why66.entry).frame(maxWidth: 520) }
            }
            paragraph(OnboardingInput.welcomeReason)
            Button("Begin", action: begin)
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.begin")
                .padding(.top, 6)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }
}

/// A paragraph of onboarding copy (Markdown **bold**).
private func paragraph(_ text: String) -> some View {
    Text(LocalizedStringKey(text))
        .font(.text(14.5))
        .lineSpacing(4)
        .foregroundStyle(Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
}

// MARK: - Page 2: Your first habit

private struct FirstHabitPage: View {
    let input: OnboardingInput
    let actions: OnboardingActions
    let back: () -> Void
    let next: () -> Void

    @State private var showsWhy = false
    /// Nil: open while there's no habit yet.
    @State private var formOpen: Bool?

    private var showsForm: Bool { formOpen ?? !input.hasHabits }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(OnboardingInput.habitTitle)
                        .font(.heading(26))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    InfoButton(topic: .fixedDays, isExpanded: $showsWhy)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                        .accessibilityIdentifier("onboarding.whyDays")
                }
                paragraph(OnboardingInput.habitBody)
                if showsWhy {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(OnboardingInput.habitTopics, id: \.self) { InfoBox(entry: $0.entry) }
                    }
                    .frame(maxWidth: 560)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            if input.hasHabits {
                habitList
            } else {
                // Only before the first habit (user's choice, Phase 7 review).
                Text(OnboardingInput.startWithOne)
                    .font(.handwriting(15))
                    .foregroundStyle(Palette.inkSecondary)
            }
            if showsForm {
                HabitFormView(addHabitState: input.note.addHabitState, add: actions.addHabit,
                              close: { formOpen = false }, isInline: true)
                    .frame(width: Metrics.notebookCardWidth)
                    .id(input.habits.count) // a fresh, empty form for each habit
            } else if input.offersAnother {
                Button("Add another") { formOpen = true }
                    .buttonStyle(LinkButtonStyle(size: 13.5))
                    .accessibilityIdentifier("onboarding.addAnother")
            } else if input.hasPlenty {
                Text(OnboardingInput.plentyLine)
                    .font(.handwriting(14.5))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityIdentifier("onboarding.plenty")
            } else if !input.hasHabits {
                Button("+ Add a habit") { formOpen = true }
                    .buttonStyle(LinkButtonStyle(size: 13.5))
                    .accessibilityIdentifier("onboarding.addAnother")
            }
            HStack(spacing: 16) {
                Button("Back", action: back)
                    .buttonStyle(LinkButtonStyle(color: Palette.inkSecondary, size: 13))
                    .accessibilityIdentifier("onboarding.back")
                Button("Next", action: next)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!input.canContinue)
                    // Return adds the habit while the form is open; Next only takes it after.
                    .keyboardShortcut(showsForm ? nil : .defaultAction)
                    .accessibilityIdentifier("onboarding.next")
            }
            .padding(.top, 6)
        }
        // A habit was added: the form closes (its own close) and the list shows it.
        .onChange(of: input.habits.count) { old, new in if new > old { formOpen = false } }
    }

    private var habitList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(input.habits) { habit in
                HStack(spacing: 10) {
                    LeafMark(state: .unchecked)
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(habit.name)
                            .font(.text(14, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text(habit.detail)
                            .font(.text(11.5))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(habit.name), \(habit.detail)")
                .accessibilityIdentifier("onboarding.habit.\(habit.name)")
            }
        }
    }
}

// MARK: - Page 3: Your note

private struct YourNotePage: View {
    let actions: OnboardingActions
    let back: () -> Void

    /// On by default (spec-onboarding.md).
    @State private var openAtLogin = true
    @State private var dayEndHour: Int

    init(dayEndHour: Int, actions: OnboardingActions, back: @escaping () -> Void) {
        self.actions = actions
        self.back = back
        _dayEndHour = State(initialValue: dayEndHour)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(OnboardingInput.noteTitle)
                .font(.heading(26))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            paragraph(OnboardingInput.noteBody)
                .frame(maxWidth: 560, alignment: .leading)
            HStack(spacing: 12) {
                Text(OnboardingInput.openAtLogin)
                    .font(.text(13, weight: .bold))
                    .foregroundStyle(Palette.ink)
                PaperToggle(label: OnboardingInput.openAtLogin, isOn: openAtLogin, identifier: "onboarding.openAtLogin") {
                    openAtLogin = $0
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(OnboardingInput.dayEndLabel)
                    .font(.text(13, weight: .bold))
                    .foregroundStyle(Palette.ink)
                ChoiceChips(options: Array(SettingsValues.dayEndHours), selection: dayEndHour,
                            title: SettingsValues.dayEndTitle, identifier: "onboarding.dayEnd") { dayEndHour = $0 }
                Text(OnboardingInput.dayEndHelp)
                    .font(.text(11.5))
                    .foregroundStyle(Palette.inkSecondary)
            }
            HStack(spacing: 16) {
                Button("Back", action: back)
                    .buttonStyle(LinkButtonStyle(color: Palette.inkSecondary, size: 13))
                    .accessibilityIdentifier("onboarding.back")
                Button("Skip", action: actions.skip)
                    .buttonStyle(LinkButtonStyle(color: Palette.inkSecondary, size: 13))
                    .accessibilityIdentifier("onboarding.skip")
                Button("Finish") { actions.finish(openAtLogin, dayEndHour) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.finish")
            }
            .padding(.top, 6)
        }
    }
}
