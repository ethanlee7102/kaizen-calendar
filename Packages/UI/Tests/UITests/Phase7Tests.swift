import Core
import Foundation
import Testing
@testable import UI

/// The Science tab, info buttons on the note's lines, onboarding and the drag hint (Phase 7).
@Suite struct ScienceAndOnboardingTests {
    // MARK: The Science page

    @Test func theSciencePageListsEveryEntryOnceInGroupOrder() {
        let page = SciencePage()
        #expect(page.sections.map(\.group) == ScienceGroup.allCases)
        let topics = page.sections.flatMap { $0.entries.map(\.topic) }
        #expect(topics.count == ScienceTopic.allCases.count)
        #expect(Set(topics) == Set(ScienceTopic.allCases))
        #expect(page.sources == ScienceRegistry.allSources)
    }

    @Test func sourceReferencesNameTheWorkAndWhereItAppeared() {
        let paper = SciencePage.reference(.lally2010)
        #expect(paper.lead == "Lally, van Jaarsveld, Potts & Wardle (2010)")
        #expect(paper.title == "How are habits formed: Modelling habit formation in the real world")
        #expect(paper.publication == "European Journal of Social Psychology")
        let book = SciencePage.reference(.clear2018)
        #expect(book.lead == "James Clear (2018)")
        #expect(book.title == "Atomic Habits")
        #expect(book.publication == nil)
        #expect(SciencePage.spokenReference(.clear2018) == "James Clear (2018). Atomic Habits")
    }

    @Test func infoBoxLinksOpenTheScienceTabAtTheirEntry() {
        let navigation = NotebookNavigation(defaults: nil, tab: .habits)
        navigation.showScience(.recovery)
        #expect(navigation.tab == .science)
        #expect(navigation.scienceTopic == .recovery)
    }

    // MARK: Info buttons on the note's lines (replacing first-time notes)

    @Test func dangerAndRecoveredLinesExplainThemselvesButRestHasNoSource() {
        #expect(RowLine.danger.topic == .neverMissTwice)
        #expect(RowLine.recovered.topic == .recovery)
        #expect(RowLine.resting.topic == nil)
        // Every info button needs a source (spec-science.md rule 1).
        for line in [RowLine.danger, .recovered] {
            #expect(line.topic.map { !$0.entry.sources.isEmpty } == true)
        }
    }

    // MARK: Onboarding

    @Test func onboardingStartsAtTheWelcomeOrResumesAtTheFirstHabit() {
        let flow = OnboardingFlow()
        #expect(flow.page(hasHabits: false) == .welcome)
        // Left after adding a habit: back on page 2 with it listed (user's choice).
        #expect(flow.page(hasHabits: true) == .firstHabit)
        flow.go(to: .yourNote)
        #expect(flow.page(hasHabits: true) == .yourNote)
        flow.go(to: .welcome)
        #expect(flow.page(hasHabits: true) == .welcome)
        #expect(OnboardingFlow.Page.yourNote.position == "3 of 3")
    }

    @Test func firstHabitPageOffersAnotherUntilThree() {
        func input(_ count: Int) -> OnboardingInput {
            let habits = ["Read", "Walk", "Floss", "Stretch"].prefix(count).map {
                noteHabit($0, created: "2026-11-14", today: Fixture.today)
            }
            return OnboardingInput(note: NoteInput(today: Fixture.today, habits: Array(habits)))
        }
        #expect(!input(0).canContinue)
        #expect(!input(0).offersAnother)
        #expect(!input(0).hasPlenty)
        for count in [1, 2] {
            #expect(input(count).canContinue)
            #expect(input(count).offersAnother)
            #expect(!input(count).hasPlenty)
        }
        for count in [3, 4] {
            #expect(input(count).canContinue)
            #expect(!input(count).offersAnother)
            #expect(input(count).hasPlenty)
        }
    }

    @Test func onboardingListsHabitsWithTheirTargetAndDays() {
        let read = noteHabit("Read", kind: .amount(unit: "pages"), target: 10, created: "2026-11-14", today: Fixture.today)
        let gym = noteHabit("Gym", schedule: Schedule([.monday, .thursday])!, created: "2026-11-14", today: Fixture.today)
        let paused = noteHabit("Run", created: "2026-11-01", deactivated: "2026-11-05", today: Fixture.today)
        let input = OnboardingInput(note: NoteInput(today: Fixture.today, habits: [read, gym, paused]))
        #expect(input.habits.map(\.name) == ["Read", "Gym"])
        #expect(input.habits.map(\.detail) == ["10 pages · every day", "2 days a week"])
    }

    @Test func onboardingCopySaysHabitNotGoal() {
        // "goal" only in "not a goal tracker" and "A habit, not a goal." (the point being made).
        let texts = [OnboardingInput.welcomeResearch, OnboardingInput.welcomeReason, OnboardingInput.habitBody,
                     OnboardingInput.startWithOne, OnboardingInput.plentyLine, OnboardingInput.noteBody]
        for text in texts { #expect(!text.lowercased().contains("goal"), "\(text)") }
        #expect(OnboardingInput.habitTopics.allSatisfy { !$0.entry.sources.isEmpty })
    }

    // MARK: "Drag me anywhere."

    @Test func theDragHintShowsFromFinishUntilADragDismissOrTheNextDay() {
        var hint = DragHint()
        #expect(!hint.isShowing(today: Fixture.today))
        hint.start(today: Fixture.today)
        #expect(hint.isShowing(today: Fixture.today))
        #expect(!hint.isShowing(today: Fixture.today.adding(days: 1)))
        // Never restarts.
        hint.start(today: Fixture.today.adding(days: 1))
        #expect(!hint.isShowing(today: Fixture.today.adding(days: 1)))

        var dragged = DragHint()
        dragged.start(today: Fixture.today)
        dragged.finish()
        #expect(!dragged.isShowing(today: Fixture.today))

        // Dragged before onboarding finished: never shows.
        var early = DragHint()
        early.finish()
        early.start(today: Fixture.today)
        #expect(!early.isShowing(today: Fixture.today))
    }

    @Test func theDragHintSurvivesARelaunch() throws {
        var hint = DragHint()
        hint.start(today: Fixture.today)
        let decoded = try JSONDecoder().decode(DragHint.self, from: JSONEncoder().encode(hint))
        #expect(decoded == hint)
        #expect(decoded.isShowing(today: Fixture.today))
    }
}
