/// Fixed numbers from the product rules. The full rule engine (streaks, journey, suggestions,
/// reports) arrives in Phase 1; see claude-context/build-plan.md.
public enum HabitRules {
    /// "Day X of 66": the median time new daily habits took to feel automatic (Lally et al., 2010).
    public static let journeyLength = 66

    /// The most habits that can be active at once ("Why 5?", spec-collapsed-note.md §8).
    public static let maxActiveHabits = 5
}
