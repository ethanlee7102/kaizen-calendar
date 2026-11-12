import Core
import Testing

@Suite struct HabitRulesTests {
    @Test func journeyIs66Days() {
        #expect(HabitRules.journeyLength == 66)
    }

    @Test func atMostFiveActiveHabits() {
        #expect(HabitRules.maxActiveHabits == 5)
    }
}
