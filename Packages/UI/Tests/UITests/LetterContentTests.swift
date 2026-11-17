import Core
import Foundation
import Testing
@testable import UI

/// What letters, the Reports tab, the envelope, suggestion cards and milestone cards say
/// (Phase 6).
@Suite struct LetterContentTests {
    // MARK: Titles and archive

    @Test func titlesAndArchiveLines() {
        #expect(LetterFixture.weekly().title == "Your week, Nov 1–7")
        #expect(LetterFixture.weekly().archiveLine == "Nov 1–7")
        #expect(LetterFixture.monthly().title == "Your October")
        #expect(LetterFixture.monthly().archiveLine == "Aug 30–Oct 24 · monthly")
        #expect(LetterFixture.day66().title == "Day 66: Read")
        #expect(LetterFixture.recheck().title == "Checking in: Read")
        #expect(DayText.range(DayRange(d("2026-12-27"), d("2027-01-02"))) == "Dec 27, 2026–Jan 2, 2027")
    }

    @Test func theArchiveKeepsNewLettersOnTopThenMonthsNewestFirst() {
        let archive = LetterArchive(letters: [LetterFixture.recheck(), LetterFixture.weekly(isFiled: true),
                                              LetterFixture.day66(), LetterFixture.monthly()])
        #expect(archive.new.map(\.id) == [LetterFixture.recheckID, LetterFixture.day66ID])
        #expect(archive.months.map(\.title) == ["November 2026", "October 2026"])
        #expect(archive.months[0].letters.map(\.id) == [LetterFixture.weeklyID])
        #expect(LetterArchive(letters: []).isEmpty)
    }

    @Test func theEnvelopeAndTheReportsMarker() {
        let waiting = LetterFixture.input(letters: [LetterFixture.weekly()])
        #expect(waiting.newMarkers == [.reports])
        #expect(waiting.envelopeLetter?.id == LetterFixture.weeklyID)
        #expect(NoteEnvelope(letter: LetterFixture.weekly()).title == "Your week, Nov 1–7")
        // Opened (still new until Done): no envelope, no marker.
        let opened = LetterFixture.input(letters: [LetterFixture.weekly(isUnread: false)])
        #expect(opened.newMarkers.isEmpty && opened.envelopeLetter == nil)
        // Filed unread (replaced by a newer one): in the archive as unread, not in the envelope.
        let filed = LetterFixture.input(letters: [LetterFixture.weekly(isFiled: true)])
        #expect(filed.envelopeLetter == nil)
    }

    // MARK: Weekly letter

    @Test func aWeeklyLetter() throws {
        let page = try #require(LetterFixture.input(letters: [LetterFixture.weekly()]).letterPage(LetterFixture.weeklyID))
        #expect(page.arrivedLine == "Arrived Sunday, Nov 8")
        #expect(page.glance.map(\.name) == ["Read"])
        #expect(page.glance[0].percent == "86%") // Nov 3 missed (recovered): 6 of 7
        #expect(page.glance[0].dots.map(\.kind) == [.done, .done, .recovered, .done, .done, .done, .done])
        #expect(page.savesLine == "Missed once, and recovered.")
        #expect(page.journeys == [LetterLine(label: "Read", text: "Day 68 ✓66")])
        #expect(page.notesTitle == "Your notes this week")
        #expect(page.notes == [LetterLine(label: "Thu, Nov 5", text: "Read before bed, not after.")])
        #expect(page.suggestions.map(\.change) == ["11 pages instead of 10, from today."])
        #expect(page.suggestions.map(\.state) == [.open])
        let obstacle = try #require(page.obstacle)
        #expect(obstacle.previous == "Late meetings. Read at lunch instead.")
        #expect(obstacle.canKeepSame)
        #expect(page.questions.isEmpty && page.automaticity == nil && page.recap == nil)
        #expect(page.firstWeekLine == nil)
    }

    @Test func keepTheSameOnlyWhileNothingNewIsWritten() throws {
        let answered = LetterFixture.input(letters: [LetterFixture.weekly(answers: [.obstacle: "Travel"])])
        #expect(try #require(answered.letterPage(LetterFixture.weeklyID)?.obstacle).canKeepSame == false)
        let filed = LetterFixture.input(letters: [LetterFixture.weekly(isFiled: true)])
        #expect(try #require(filed.letterPage(LetterFixture.weeklyID)?.obstacle).canKeepSame == false)
    }

    @Test(arguments: [
        (0, 0, "No misses this week."),
        (1, 1, "Missed once, and recovered."),
        (3, 3, "Missed 3 times, recovered every time."),
        (3, 2, "Missed 3 times, recovered 2 of them."),
        (2, 0, "Missed twice. The next day is always a fresh start."),
    ])
    func savesLines(misses: Int, recovered: Int, line: String) throws {
        let saves = try JSONDecoder().decode(Insights.Saves.self, from: Data(#"{"misses":\#(misses),"recovered":\#(recovered)}"#.utf8))
        #expect(NotebookInput.savesLine(saves, period: "week") == line)
    }

    // MARK: Suggestion cards

    @Test func suggestionChangeText() {
        let three = Schedule([.monday, .wednesday, .friday])!
        let four = Schedule([.monday, .wednesday, .thursday, .friday])!
        #expect(SuggestionCard.changeText(.target(from: 10, to: 11), kind: .amount(unit: "pages"))
            == "11 pages instead of 10, from today.")
        #expect(SuggestionCard.changeText(.schedule(from: three, to: four), kind: .yesNo)
            == "Add Thursday: 4 days a week instead of 3, from today.")
        #expect(SuggestionCard.changeText(.schedule(from: four, to: three), kind: .yesNo)
            == "Drop Thursday: 3 days a week instead of 4, from today.")
        let five = Schedule(days: WeekdaySet([.sunday, .monday, .wednesday, .thursday, .friday]))!
        #expect(SuggestionCard.changeText(.schedule(from: .everyDay, to: five), kind: .yesNo)
            == "Drop Tuesday and Saturday: 5 days a week instead of every day, from today.")
    }

    /// A letter's buttons act on today's data (spec-reports.md, decided 2026-11-13).
    @Test func aLetterCardFollowsTodaysData() {
        let suggestion = Suggestion(habitID: LetterFixture.readID, kind: .levelUp, change: .target(from: 10, to: 11))
        let note = LetterFixture.note()
        let delivered = d("2026-11-08")
        #expect(note.letterSuggestionState(suggestion, deliveredOn: delivered, dismissals: []) == .open)
        // Not now after the letter came: says so. A "Not now" from before it doesn't count.
        #expect(note.letterSuggestionState(suggestion, deliveredOn: delivered,
                                           dismissals: [SuggestionDismissal(kind: .levelUp, day: d("2026-11-10"))]) == .notNow)
        #expect(note.letterSuggestionState(suggestion, deliveredOn: delivered,
                                           dismissals: [SuggestionDismissal(kind: .levelUp, day: d("2026-11-01"))]) == .open)

        var history = LetterFixture.readHistory()
        history.changeTarget(to: 11, on: d("2026-11-14"), source: .suggested)
        let accepted = NoteInput(today: Fixture.today, habits: [NoteHabit(name: "Read", identity: nil,
                                                                          evaluation: HabitEvaluation(history: history, today: Fixture.today))])
        #expect(accepted.letterSuggestionState(suggestion, deliveredOn: delivered, dismissals: []) == .accepted)
        let card = SuggestionCard(suggestion: suggestion, habitName: "Read", kind: .amount(unit: "pages"), state: .accepted)
        #expect(card.stateLine == "Done. 11 pages instead of 10 from now on.")

        history.changeTarget(to: 20, on: d("2026-11-14"), source: .manual)
        let changed = NoteInput(today: Fixture.today, habits: [NoteHabit(name: "Read", identity: nil,
                                                                         evaluation: HabitEvaluation(history: history, today: Fixture.today))])
        #expect(changed.letterSuggestionState(suggestion, deliveredOn: delivered, dismissals: []) == .noLongerApplies)
        // Deleted or paused: no longer applies.
        #expect(NoteInput(today: Fixture.today, habits: []).letterSuggestionState(suggestion, deliveredOn: delivered,
                                                                                  dismissals: []) == .noLongerApplies)
    }

    @Test func theHabitPageShowsTodaysSuggestion() {
        let suggestion = Suggestion(habitID: LetterFixture.readID, kind: .levelUp, change: .target(from: 10, to: 11))
        let input = LetterFixture.input(letters: [], suggestions: [LetterFixture.readID: suggestion])
        #expect(input.suggestionCard(for: LetterFixture.readID)?.title == "Two steady weeks. Ready for a little more?")
        #expect(input.suggestionCard(for: LetterFixture.walkID) == nil)
    }

    // MARK: Monthly letter

    @Test func aMonthlyLetter() throws {
        let page = try #require(LetterFixture.input(letters: [LetterFixture.monthly()]).letterPage(LetterFixture.monthlyID))
        #expect(page.glance.map(\.name) == ["Read", "Walk"])
        #expect(page.trend?.isEmpty == false)
        #expect(page.questions.map(\.question) == [.biggestWin, .nextFocus])
        #expect(page.questions.map(\.answer) == ["Reading every single day in October.", ""])
        #expect(page.obstacle == nil)
        #expect(page.notesTitle == "Your notes this month")
        // Walk is still paused today, with room for it.
        #expect(page.reactivate?.items == [ReactivateSection.Item(id: LetterFixture.walkID, name: "Walk", state: .canReactivate)])
    }

    @Test func reactivateFollowsTodaysHabits() throws {
        var input = LetterFixture.input(letters: [LetterFixture.monthly()])
        input.note.habits.removeAll { $0.id == LetterFixture.walkID }
        #expect(try #require(input.letterPage(LetterFixture.monthlyID)?.reactivate).items.map(\.state) == [.deleted])

        input = LetterFixture.input(letters: [LetterFixture.monthly()])
        for name in ["A", "B", "C", "D"] { input.note.habits.append(noteHabit(name, created: "2026-11-01", today: Fixture.today)) }
        #expect(try #require(input.letterPage(LetterFixture.monthlyID)?.reactivate).items.map(\.state) == [.atLimit])
    }

    // MARK: Day 66 and re-checks

    @Test func aDay66Letter() throws {
        let page = try #require(LetterFixture.input(letters: [LetterFixture.day66()]).letterPage(LetterFixture.day66ID))
        let recap = try #require(page.recap)
        #expect(recap.doneLine == "66 done days in 67 days") // Sep 1 – Nov 6, Nov 3 missed
        #expect(recap.streakLine == "Longest streak 66 days · no streak breaks · 1 never-miss-twice save")
        #expect(recap.historyLine == "10 pages the whole way.")
        #expect(recap.weeks.count == 10) // Aug 30 – Nov 7, Sunday-first columns
        #expect(recap.weeks.flatMap { $0 }.count { $0 == true } == 66)
        #expect(recap.firstNote == LetterLine(label: "Your first note (Sep 2)", text: "Ten pages felt long."))
        #expect(recap.latestNote == LetterLine(label: "Your latest note (Nov 5)", text: "Read before bed, not after."))

        let check = try #require(page.automaticity)
        #expect(check.canDecide && check.canAnswer)
        #expect(check.primaryChange == .target(current: 10, unit: "pages"))
        #expect(check.recommendationLine == nil && check.decisionLine == nil)
    }

    @Test func theAutomaticityAnswerAndTheDecision() throws {
        let answered = LetterFixture.input(letters: [LetterFixture.day66(answers: [.automaticity: "5"])])
        var check = try #require(answered.letterPage(LetterFixture.day66ID)?.automaticity)
        #expect(check.answer == .completely && check.recommendation == .graduate)
        #expect(check.recommendationLine?.hasPrefix("That sounds automatic.") == true)

        let decided = LetterFixture.input(letters: [LetterFixture.day66(answers: [.automaticity: "2", .decision: "keepGoing"])])
        check = try #require(decided.letterPage(LetterFixture.day66ID)?.automaticity)
        #expect(check.recommendation == .keepGoing)
        #expect(!check.canDecide)
        #expect(check.decisionLine == "You chose: Keep going. This check comes back in about 3 weeks.")

        // A paused habit can't be decided on.
        var paused = LetterFixture.input(letters: [LetterFixture.day66()])
        var history = LetterFixture.readHistory()
        history.deactivate(on: d("2026-11-14"), reason: .paused)
        paused.note.habits[0] = NoteHabit(name: "Read", identity: nil, evaluation: HabitEvaluation(history: history, today: Fixture.today))
        check = try #require(paused.letterPage(LetterFixture.day66ID)?.automaticity)
        #expect(!check.canDecide && !check.canAnswer)
        #expect(check.unavailableLine == "Read isn’t active right now, so there’s nothing to decide here.")
    }

    /// A filed day-66 letter (replaced in the envelope before it was opened) can still be
    /// decided; after the decision the answer is settled (Phase 6 review).
    @Test func aFiledUndecidedLetterCanStillBeDecided() throws {
        let filed = LetterInput(id: LetterFixture.day66ID, kind: .day66, deliveryDay: d("2026-11-06"), period: nil,
                                isUnread: true, isFiled: true, content: LetterFixture.day66().content,
                                habits: [LetterFixture.readID: LetterFixture.read], answers: [:])
        let check = try #require(LetterFixture.input(letters: [filed]).letterPage(filed.id)?.automaticity)
        #expect(check.canDecide && check.canAnswer)
        #expect(check.decisionLine == nil)

        let decided = LetterFixture.input(letters: [LetterFixture.day66(answers: [.automaticity: "4", .decision: "graduate"])])
        let after = try #require(decided.letterPage(LetterFixture.day66ID)?.automaticity)
        #expect(!after.canDecide && !after.canAnswer)
    }

    /// The notebook never reopens on an older letter while a new one waits (Phase 6 review).
    @Test func openingWithALetterWaitingShowsTheListNotAnOldLetter() {
        let navigation = NotebookNavigation(defaults: nil, tab: .calendar)
        navigation.openLetter = LetterFixture.monthlyID // left open last time
        navigation.opened(waitingLetter: LetterFixture.weeklyID)
        #expect(navigation.tab == .reports && navigation.openLetter == nil)

        // The envelope opens its letter, and opening keeps it.
        navigation.showLetter(LetterFixture.weeklyID)
        navigation.opened(waitingLetter: LetterFixture.weeklyID)
        #expect(navigation.openLetter == LetterFixture.weeklyID)

        // Nothing waiting: the tab and page stay as they were.
        navigation.tab = .habits
        navigation.opened(waitingLetter: nil)
        #expect(navigation.tab == .habits && navigation.openLetter == LetterFixture.weeklyID)
    }

    @Test func aRecheckLetter() throws {
        let page = try #require(LetterFixture.input(letters: [LetterFixture.recheck()]).letterPage(LetterFixture.recheckID))
        #expect(page.checkInLine == "Day 73. Last time you answered “Somewhat”.")
        #expect(page.automaticity?.canDecide == true)
        #expect(page.recap == nil && page.glance.isEmpty)
    }

    @Test func anUnreadableLetter() throws {
        let letter = LetterInput(id: UUID(), kind: .weekly, deliveryDay: d("2026-11-08"), period: nil, isUnread: true,
                                 isFiled: false, content: nil, habits: [:], answers: [:])
        let page = try #require(LetterFixture.input(letters: [letter]).letterPage(letter.id))
        #expect(page.isUnreadable && page.obstacle == nil && page.title == "Your week")
    }

    // MARK: Milestones

    @Test func milestoneCards() {
        let today = d("2027-01-01")
        func read(_ doneDays: Int) -> NoteHabit {
            noteHabit("Read", created: "2026-01-01", done: (0..<doneDays).map { d("2026-01-01").adding(days: $0) }, today: today)
        }
        #expect(NoteInput(today: today, habits: [read(99)]).milestoneNotice == nil)
        let hundred = NoteInput(today: today, habits: [read(100)])
        #expect(hundred.milestoneNotice?.title == "Day 100 · Read")
        #expect(hundred.milestoneNotice?.line == "Triple digits.")
        #expect(hundred.milestoneNotice?.topic == .journeyCountsDoneDays)

        // Past 254 with 100 never dismissed: one card, for the highest, covering both.
        let habit = read(260)
        let both = NoteInput(today: today, habits: [habit])
        #expect(both.milestoneNotice?.milestone == 254 && both.milestoneNotice?.milestones == [100, 254])
        #expect(both.milestoneNotice?.topic == .day254)
        #expect(NoteInput(today: today, habits: [habit], milestonesSeen: [habit.id: [100, 254]]).milestoneNotice == nil)
    }
}
