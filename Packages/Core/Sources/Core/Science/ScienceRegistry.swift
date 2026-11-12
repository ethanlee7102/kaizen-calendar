/// Every "why" in the app, written once (spec-science.md rule 3). Info buttons, The Science
/// page and first-time notes all read from here, so they can't disagree.
///
/// Rules: only features with a source get an entry; never claim more than the source says.
/// All citations must be verified against the originals before shipping (Phase 7).

public struct Source: Hashable, Sendable {
    /// e.g. "Lally, van Jaarsveld, Potts & Wardle"
    public let authors: String
    /// Book title or journal.
    public let work: String
    public let year: Int
    /// The work is a book (shown in italics), not a journal.
    public let isBook: Bool

    /// "Lally, van Jaarsveld, Potts & Wardle, European Journal of Social Psychology (2010)"
    public var citation: String { "\(authors), \(work) (\(year))" }
}

public extension Source {
    static let lally2010 = Source(authors: "Lally, van Jaarsveld, Potts & Wardle",
                                  work: "European Journal of Social Psychology", year: 2010, isBook: false)
    static let gardner2012 = Source(authors: "Gardner, Abraham, Lally & de Bruijn",
                                    work: "International Journal of Behavioral Nutrition and Physical Activity",
                                    year: 2012, isBook: false)
    static let clear2018 = Source(authors: "James Clear", work: "Atomic Habits", year: 2018, isBook: true)
    static let fogg2019 = Source(authors: "B.J. Fogg", work: "Tiny Habits", year: 2019, isBook: true)
    static let babauta2009 = Source(authors: "Leo Babauta", work: "The Power of Less", year: 2009, isBook: true)
    static let daltonSpiller2012 = Source(authors: "Dalton & Spiller", work: "Journal of Consumer Research",
                                          year: 2012, isBook: false)
    static let polivyHerman1985 = Source(authors: "Polivy & Herman", work: "American Psychologist",
                                         year: 1985, isBook: false)
    static let woodRunger2016 = Source(authors: "Wood & Rünger", work: "Annual Review of Psychology",
                                       year: 2016, isBook: false)
    static let kaushalRhodes2015 = Source(authors: "Kaushal & Rhodes", work: "Journal of Behavioral Medicine",
                                          year: 2015, isBook: false)
    static let beshears2021 = Source(authors: "Beshears, Lee, Milkman, Mislavsky & Wisdom",
                                     work: "Management Science", year: 2021, isBook: false)
    static let harkin2016 = Source(authors: "Harkin et al.", work: "Psychological Bulletin", year: 2016, isBook: false)
    static let oettingen2014 = Source(authors: "Gabriele Oettingen", work: "Rethinking Positive Thinking",
                                      year: 2014, isBook: true)
    static let amabileKramer2011 = Source(authors: "Teresa Amabile & Steven Kramer", work: "The Progress Principle",
                                          year: 2011, isBook: true)
    static let deci1999 = Source(authors: "Deci, Koestner & Ryan", work: "Psychological Bulletin",
                                 year: 1999, isBook: false)
}

/// The Science page groups entries by idea, not by screen.
public enum ScienceGroup: String, CaseIterable, Hashable, Sendable {
    case sixtySixDays, neverMissTwice, habitsNotGoals, smallSteps, identity, lookingBack, celebrating, progress

    public var title: String {
        switch self {
        case .sixtySixDays: "The 66 days"
        case .neverMissTwice: "Never miss twice"
        case .habitsNotGoals: "Habits, not goals"
        case .smallSteps: "Small steps"
        case .identity: "Identity"
        case .lookingBack: "Looking back"
        case .celebrating: "Celebrating"
        case .progress: "Seeing progress"
        }
    }
}

public enum ScienceTopic: String, CaseIterable, Hashable, Sendable {
    case why66, journeyCountsDoneDays, day66Check, automaticityQuestion, day254
    case neverMissTwice, recovery, eveningReminder, consistency
    case fixedDays, flexibleTime, whyFive, startWithThree
    case startSmall, levelUp, levelDown, onePercent
    case identity
    case lookingBack, obstacle
    case celebration
    case stampBook

    public var entry: ScienceEntry { ScienceRegistry.entry(for: self) }
}

public struct ScienceEntry: Hashable, Sendable {
    public let topic: ScienceTopic
    public let group: ScienceGroup
    public let title: String
    /// 1–3 plain sentences (the info box).
    public let body: String
    public let sources: [Source]
}

public enum ScienceRegistry {
    public static var all: [ScienceEntry] { ScienceTopic.allCases.map(entry(for:)) }

    public static func entries(in group: ScienceGroup) -> [ScienceEntry] {
        all.filter { $0.group == group }
    }

    /// Every source cited anywhere, for the Sources list at the bottom of The Science page.
    public static var allSources: [Source] {
        var seen = Set<Source>()
        return all.flatMap(\.sources).filter { seen.insert($0).inserted }
            .sorted { $0.authors < $1.authors }
    }

    public static func entry(for topic: ScienceTopic) -> ScienceEntry {
        switch topic {
        // The 66 days
        case .why66:
            ScienceEntry(topic: topic, group: .sixtySixDays, title: "Why 66?",
                         body: "In a study of new daily habits, it took a median of 66 days for them to feel automatic, ranging from 18 to 254 days. Missing a single day didn't set people back.",
                         sources: [.lally2010])
        case .journeyCountsDoneDays:
            ScienceEntry(topic: topic, group: .sixtySixDays, title: "Why only done days count",
                         body: "The study followed the days people actually did the behavior. Repetition is what builds a habit, so only the days you do it move your journey forward.",
                         sources: [.lally2010])
        case .day66Check:
            ScienceEntry(topic: topic, group: .sixtySixDays, title: "Why check at day 66?",
                         body: "66 days is the median, not a finish line. Checking how automatic it feels tells you whether the habit is ready to stand on its own.",
                         sources: [.lally2010])
        case .automaticityQuestion:
            ScienceEntry(topic: topic, group: .sixtySixDays, title: "Just one question",
                         body: "In habit research, automaticity is measured with four near-identical statements: \"I do it automatically\", \"I do it without having to consciously remember\", \"I do it without thinking\", and \"I start doing it before I realize I'm doing it\". Averaging them gives a steadier answer. We ask the first one to keep this quick. If you're unsure, run through the other three in your head.",
                         sources: [.gardner2012])
        case .day254:
            ScienceEntry(topic: topic, group: .sixtySixDays, title: "Why 254?",
                         body: "254 days was the longest it took anyone in the 66-day study for a habit to feel automatic.",
                         sources: [.lally2010])

        // Never miss twice
        case .neverMissTwice:
            ScienceEntry(topic: topic, group: .neverMissTwice, title: "Never miss twice",
                         body: "In the 66-day study, missing one day didn't meaningfully affect how the habit formed. Letting misses pile up is what hurts, so one miss is fine and two in a row break the streak.",
                         sources: [.lally2010, .clear2018])
        case .recovery:
            ScienceEntry(topic: topic, group: .neverMissTwice, title: "Why celebrate a recovery?",
                         body: "Coming back right after a miss is the behavior that keeps a habit alive, so it gets its own mark: the gold seam.",
                         sources: [.clear2018, .lally2010])
        case .eveningReminder:
            ScienceEntry(topic: topic, group: .neverMissTwice, title: "Why only one reminder?",
                         body: "Your note already reminds you every day. The one notification comes only when it matters most: the day after a miss.",
                         sources: [.clear2018])
        case .consistency:
            ScienceEntry(topic: topic, group: .neverMissTwice, title: "Why show consistency too?",
                         body: "All-or-nothing thinking can turn one slip into giving up, the \"what the hell\" effect. Consistency shows that one bad day is a small part of the picture.",
                         sources: [.polivyHerman1985, .clear2018])

        // Habits, not goals
        case .fixedDays:
            ScienceEntry(topic: topic, group: .habitsNotGoals, title: "A habit, not a goal",
                         body: "Habits form when you repeat the same action in the same context, until the context triggers it on its own. In the 66-day study, people repeated their habit every day, and new gym members needed at least 4 sessions a week for about 6 weeks before exercise became a habit. So 66 Days asks you to commit to your days.",
                         sources: [.woodRunger2016, .lally2010, .kaushalRhodes2015])
        case .flexibleTime:
            ScienceEntry(topic: topic, group: .habitsNotGoals, title: "Why no set time?",
                         body: "Being strict about when can backfire: rewarding a fixed time window led to less lasting exercise than letting people go any time. So the time of day is up to you.",
                         sources: [.beshears2021])
        case .whyFive:
            ScienceEntry(topic: topic, group: .habitsNotGoals, title: "Why 5?",
                         body: "Building a habit takes repetition and attention, and you only have so much of both. Habit experts recommend starting with about three (or even one) and adding more once those feel easy. Taking on too many at once is one of the most common reasons habits fail. Five is the most 66 Days lets you build at once.",
                         sources: [.fogg2019, .babauta2009, .daltonSpiller2012])
        case .startWithThree:
            ScienceEntry(topic: topic, group: .habitsNotGoals, title: "Start with three",
                         body: "Fogg recommends starting with three tiny habits, or even one, and adding more once they feel easy.",
                         sources: [.fogg2019])

        // Small steps
        case .startSmall:
            ScienceEntry(topic: topic, group: .smallSteps, title: "Start smaller than you think",
                         body: "Tiny habits stick. Make it so easy you can't say no, and let the routine form first. You can level up anytime, and 66 Days will suggest it when you're ready.",
                         sources: [.fogg2019])
        case .levelUp:
            ScienceEntry(topic: topic, group: .smallSteps, title: "Why a little more?",
                         body: "Motivation peaks when a task sits just beyond what you can already do. Once a habit is reliably easy, a small stretch keeps it engaging.",
                         sources: [.clear2018])
        case .levelDown:
            ScienceEntry(topic: topic, group: .smallSteps, title: "Why smaller?",
                         body: "Shrink the behavior instead of quitting. A smaller habit you actually do beats a bigger one you skip.",
                         sources: [.fogg2019])
        case .onePercent:
            ScienceEntry(topic: topic, group: .smallSteps, title: "1% better",
                         body: "Small improvements add up over time. One thing to do 1% better tomorrow is enough.",
                         sources: [.clear2018])

        // Identity
        case .identity:
            ScienceEntry(topic: topic, group: .identity, title: "Who does this habit make you?",
                         body: "Every check-off is a vote for the person you're becoming. Habits last longer when they're about who you are, not only what you do.",
                         sources: [.clear2018])

        // Looking back
        case .lookingBack:
            ScienceEntry(topic: topic, group: .lookingBack, title: "Why look back?",
                         body: "Keeping track of your progress makes you more likely to follow through on what you set out to do.",
                         sources: [.harkin2016])
        case .obstacle:
            ScienceEntry(topic: topic, group: .lookingBack, title: "Why ask about obstacles?",
                         body: "Picturing what might get in the way, and deciding what you'll do instead, helps you follow through.",
                         sources: [.oettingen2014])

        // Celebrating
        case .celebration:
            ScienceEntry(topic: topic, group: .celebrating, title: "Why the celebration?",
                         body: "A good feeling right after you do the behavior helps wire in the habit.",
                         sources: [.fogg2019])

        // Seeing progress
        case .stampBook:
            ScienceEntry(topic: topic, group: .progress, title: "Why a stamp book?",
                         body: "Seeing your progress add up is motivating in itself. Unlocks stay small surprises on purpose: rewards you expect can crowd out your own reasons for doing something, while unexpected ones don't.",
                         sources: [.amabileKramer2011, .deci1999])
        }
    }
}

/// Handwritten notes shown once, the first time something special happens
/// (spec-celebrations.md). They can be reread on The Science page.
public enum FirstTimeNote: String, CaseIterable, Hashable, Sendable, Codable {
    case checkOffWave, recovery, restDay, firstReport, day66Seal

    public var text: String {
        switch self {
        case .checkOffWave: "Small wins feel good on purpose. Celebrating right away helps the habit stick."
        case .recovery: "Missed once, back the next time. That's the whole trick: never miss twice."
        case .restDay: "Rest pauses your streak instead of breaking it. Use it rarely."
        case .firstReport: "A weekly look back helps you notice what's working before it slips."
        case .day66Seal: "66 days is the median time it took habits to feel automatic in the study this app is named after."
        }
    }

    /// The info button's entry; nil for product rules without a source (no info button).
    public var topic: ScienceTopic? {
        switch self {
        case .checkOffWave: .celebration
        case .recovery: .recovery
        case .restDay: nil
        case .firstReport: .lookingBack
        case .day66Seal: .why66
        }
    }
}
