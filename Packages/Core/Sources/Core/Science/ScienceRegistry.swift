import Foundation

/// Every "why" in the app, written once (spec-science.md rule 3). Info buttons and The Science
/// page both read from here, so they can't disagree.
///
/// Rules: only features with a source get an entry; never claim more than the source says.

public struct Source: Hashable, Sendable {
    /// e.g. "Lally, van Jaarsveld, Potts & Wardle"
    public let authors: String
    /// Book title or journal.
    public let work: String
    public let year: Int
    /// The work is a book (shown in italics), not a journal.
    public let isBook: Bool
    /// The paper's title, for the Sources list (books: nil, `work` is the title).
    public let title: String?
    /// The DOI link for papers; the publisher's (or author's) page for books.
    public let url: URL

    public init(authors: String, work: String, year: Int, isBook: Bool, title: String? = nil, url: URL) {
        self.authors = authors
        self.work = work
        self.year = year
        self.isBook = isBook
        self.title = title
        self.url = url
    }

    /// "Lally, van Jaarsveld, Potts & Wardle, European Journal of Social Psychology (2010)"
    public var citation: String { "\(authors), \(work) (\(year))" }
}

/// Verified against the originals (Crossref for papers, publisher pages for books) in the
/// Phase 7 build, 2026-11-17.
public extension Source {
    static let lally2010 = Source(authors: "Lally, van Jaarsveld, Potts & Wardle",
                                  work: "European Journal of Social Psychology", year: 2010, isBook: false,
                                  title: "How are habits formed: Modelling habit formation in the real world",
                                  url: URL(string: "https://doi.org/10.1002/ejsp.674")!)
    static let gardner2012 = Source(authors: "Gardner, Abraham, Lally & de Bruijn",
                                    work: "International Journal of Behavioral Nutrition and Physical Activity",
                                    year: 2012, isBook: false,
                                    title: "Towards parsimony in habit measurement: Testing the convergent and predictive validity of an automaticity subscale of the Self-Report Habit Index",
                                    url: URL(string: "https://doi.org/10.1186/1479-5868-9-102")!)
    static let clear2018 = Source(authors: "James Clear", work: "Atomic Habits", year: 2018, isBook: true,
                                  url: URL(string: "https://www.penguinrandomhouse.com/books/543993/atomic-habits-by-james-clear/")!)
    static let fogg2019 = Source(authors: "BJ Fogg", work: "Tiny Habits", year: 2019, isBook: true,
                                 url: URL(string: "https://tinyhabits.com/book/")!)
    static let babauta2009 = Source(authors: "Leo Babauta", work: "The Power of Less", year: 2009, isBook: true,
                                    url: URL(string: "https://www.hachettebookgroup.com/titles/leo-babauta/the-power-of-less/9781401309701/")!)
    static let daltonSpiller2012 = Source(authors: "Dalton & Spiller", work: "Journal of Consumer Research",
                                          year: 2012, isBook: false,
                                          title: "Too much of a good thing: The benefits of implementation intentions depend on the number of goals",
                                          url: URL(string: "https://doi.org/10.1086/664500")!)
    static let polivyHerman1985 = Source(authors: "Polivy & Herman", work: "American Psychologist",
                                         year: 1985, isBook: false, title: "Dieting and binging: A causal analysis",
                                         url: URL(string: "https://doi.org/10.1037/0003-066X.40.2.193")!)
    static let woodRunger2016 = Source(authors: "Wood & Rünger", work: "Annual Review of Psychology",
                                       year: 2016, isBook: false, title: "Psychology of habit",
                                       url: URL(string: "https://doi.org/10.1146/annurev-psych-122414-033417")!)
    static let kaushalRhodes2015 = Source(authors: "Kaushal & Rhodes", work: "Journal of Behavioral Medicine",
                                          year: 2015, isBook: false,
                                          title: "Exercise habit formation in new gym members: A longitudinal study",
                                          url: URL(string: "https://doi.org/10.1007/s10865-015-9640-7")!)
    static let beshears2021 = Source(authors: "Beshears, Lee, Milkman, Mislavsky & Wisdom",
                                     work: "Management Science", year: 2021, isBook: false,
                                     title: "Creating exercise habits using incentives: The trade-off between flexibility and routinization",
                                     url: URL(string: "https://doi.org/10.1287/mnsc.2020.3706")!)
    static let harkin2016 = Source(authors: "Harkin et al.", work: "Psychological Bulletin", year: 2016, isBook: false,
                                   title: "Does monitoring goal progress promote goal attainment? A meta-analysis of the experimental evidence",
                                   url: URL(string: "https://doi.org/10.1037/bul0000025")!)
    static let oettingen2014 = Source(authors: "Gabriele Oettingen", work: "Rethinking Positive Thinking",
                                      year: 2014, isBook: true,
                                      url: URL(string: "https://www.penguinrandomhouse.com/books/315221/rethinking-positive-thinking-by-gabriele-oettingen/")!)
    static let amabileKramer2011 = Source(authors: "Teresa Amabile & Steven Kramer", work: "The Progress Principle",
                                          year: 2011, isBook: true,
                                          url: URL(string: "https://store.hbr.org/product/the-progress-principle-using-small-wins-to-ignite-joy-engagement-and-creativity-at-work/10106")!)
    static let deci1999 = Source(authors: "Deci, Koestner & Ryan", work: "Psychological Bulletin",
                                 year: 1999, isBook: false,
                                 title: "A meta-analytic review of experiments examining the effects of extrinsic rewards on intrinsic motivation",
                                 url: URL(string: "https://doi.org/10.1037/0033-2909.125.6.627")!)
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
    /// What the entry explains, as a heading on The Science page ("The 66-day journey").
    public let feature: String
    /// The info box's title ("Why 66?").
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
            ScienceEntry(topic: topic, group: .sixtySixDays, feature: "The 66-day journey", title: "Why 66?",
                         body: "In a study of new daily habits, it took a median of 66 days for them to become close to fully automatic, with estimates from 18 to 254 days. Missing a single day didn't meaningfully set people back.",
                         sources: [.lally2010])
        case .journeyCountsDoneDays:
            ScienceEntry(topic: topic, group: .sixtySixDays, feature: "The journey counts done days only", title: "Why only done days count",
                         body: "Habits are built by repetition: doing the same thing again and again in the same context. So only the days you do it move your journey forward.",
                         sources: [.woodRunger2016])
        case .day66Check:
            ScienceEntry(topic: topic, group: .sixtySixDays, feature: "The day-66 check and graduating", title: "Why check at day 66?",
                         body: "66 days is the median, not a finish line. Checking how automatic it feels tells you whether the habit is ready to stand on its own.",
                         sources: [.lally2010])
        case .automaticityQuestion:
            ScienceEntry(topic: topic, group: .sixtySixDays, feature: "The automaticity question", title: "Just one question",
                         body: "In habit research, automaticity is measured with four related statements: \"I do it automatically\", \"I do it without having to consciously remember\", \"I do it without thinking\", and \"I start doing it before I realize I'm doing it\". Averaging them gives a steadier answer. We ask the first one to keep this quick. If you're unsure, run through the other three in your head.",
                         sources: [.gardner2012])
        case .day254:
            ScienceEntry(topic: topic, group: .sixtySixDays, feature: "The Day 254 milestone", title: "Why 254?",
                         body: "In the 66-day study, the slowest habit was estimated to take 254 days to become automatic.",
                         sources: [.lally2010])

        // Never miss twice
        case .neverMissTwice:
            ScienceEntry(topic: topic, group: .neverMissTwice, feature: "Never-miss-twice streaks", title: "Never miss twice",
                         body: "In the 66-day study, missing one day didn't meaningfully affect how the habit formed. James Clear's rule builds on that: missing once is an accident; missing twice is the start of a new pattern.",
                         sources: [.lally2010, .clear2018])
        case .recovery:
            ScienceEntry(topic: topic, group: .neverMissTwice, feature: "The gold “Recovered” line and seam", title: "Why celebrate a recovery?",
                         body: "Coming back right after a miss is the behavior that keeps a habit alive, so it gets its own mark: the gold seam.",
                         sources: [.clear2018, .lally2010])
        case .eveningReminder:
            ScienceEntry(topic: topic, group: .neverMissTwice, feature: "The evening reminder", title: "Why only one reminder?",
                         body: "Your note already reminds you every day. The one notification comes only when it matters most: the day after a miss.",
                         sources: [.clear2018])
        case .consistency:
            ScienceEntry(topic: topic, group: .neverMissTwice, feature: "Consistency next to the streak", title: "Why show consistency too?",
                         body: "In dieting research, breaking a rule once often led people to give up on it altogether, the \"what the hell\" effect. Consistency shows that one bad day is a small part of the picture.",
                         sources: [.polivyHerman1985, .clear2018])

        // Habits, not goals
        case .fixedDays:
            ScienceEntry(topic: topic, group: .habitsNotGoals, feature: "Fixed days, not “N times a week”", title: "A habit, not a goal",
                         body: "Habits form when you repeat the same action in the same context, until the context triggers it on its own. In the 66-day study, people repeated their habit every day, and new gym members needed at least 4 sessions a week for about 6 weeks before exercise became a habit. So 66 Days asks you to commit to your days.",
                         sources: [.woodRunger2016, .lally2010, .kaushalRhodes2015])
        case .flexibleTime:
            ScienceEntry(topic: topic, group: .habitsNotGoals, feature: "Any time of day", title: "Why no set time?",
                         body: "Being strict about when can backfire: paying people to exercise only in a set daily time window led to less exercise, during and after, than paying them to go any time. So the time of day is up to you.",
                         sources: [.beshears2021])
        case .whyFive:
            ScienceEntry(topic: topic, group: .habitsNotGoals, feature: "At most 5 habits at once", title: "Why 5?",
                         body: "Building a habit takes repetition and attention, and you only have so much of both. Fogg suggests starting with three tiny habits or even one, and Babauta recommends one at a time. Research also found that detailed planning helped people working on one thing but not several at once. Five is the most 66 Days lets you build at once.",
                         sources: [.fogg2019, .babauta2009, .daltonSpiller2012])
        case .startWithThree:
            ScienceEntry(topic: topic, group: .habitsNotGoals, feature: "The nudge at 3 habits", title: "Start with three",
                         body: "Fogg suggests starting with three tiny habits, or even one, and adding more once they feel easy.",
                         sources: [.fogg2019])

        // Small steps
        case .startSmall:
            ScienceEntry(topic: topic, group: .smallSteps, feature: "“Start smaller than you think”", title: "Start smaller than you think",
                         body: "Tiny habits stick. Start with a version so small it's easy even on a bad day, and let the routine form first. You can level up anytime, and 66 Days will suggest it when you're ready.",
                         sources: [.fogg2019])
        case .levelUp:
            ScienceEntry(topic: topic, group: .smallSteps, feature: "Level-up suggestions", title: "Why a little more?",
                         body: "Motivation peaks when a task sits just beyond what you can already do. Once a habit is reliably easy, a small stretch keeps it engaging.",
                         sources: [.clear2018])
        case .levelDown:
            ScienceEntry(topic: topic, group: .smallSteps, feature: "Level-down suggestions", title: "Why smaller?",
                         body: "Shrink the behavior instead of quitting. A smaller habit you actually do beats a bigger one you skip.",
                         sources: [.fogg2019])
        case .onePercent:
            ScienceEntry(topic: topic, group: .smallSteps, feature: "The “1% better” daily note", title: "1% better",
                         body: "Small improvements add up over time. One thing to do 1% better tomorrow is enough.",
                         sources: [.clear2018])

        // Identity
        case .identity:
            ScienceEntry(topic: topic, group: .identity, feature: "The identity line", title: "Who does this habit make you?",
                         body: "Every check-off is a vote for the person you're becoming. Habits last longer when they're about who you are, not only what you do.",
                         sources: [.clear2018])

        // Looking back
        case .lookingBack:
            ScienceEntry(topic: topic, group: .lookingBack, feature: "Reports, the trend graph and the weakest weekday", title: "Why look back?",
                         body: "Keeping track of your progress makes you more likely to follow through on what you set out to do.",
                         sources: [.harkin2016])
        case .obstacle:
            ScienceEntry(topic: topic, group: .lookingBack, feature: "The weekly obstacle question", title: "Why ask about obstacles?",
                         body: "Picturing what might get in the way, and deciding what you'll do instead, helps you follow through.",
                         sources: [.oettingen2014])

        // Celebrating
        case .celebration:
            ScienceEntry(topic: topic, group: .celebrating, feature: "Check-off celebrations", title: "Why the celebration?",
                         body: "A good feeling right after you do the behavior helps wire in the habit.",
                         sources: [.fogg2019])

        // Seeing progress
        case .stampBook:
            ScienceEntry(topic: topic, group: .progress, feature: "The Stamp book and surprise unlocks", title: "Why a stamp book?",
                         body: "Making progress, even small wins, is one of the biggest boosts to motivation. Unlocks stay small surprises on purpose: rewards you expect can lower your interest in doing something for its own sake, while unexpected ones don't.",
                         sources: [.amabileKramer2011, .deci1999])
        }
    }
}
