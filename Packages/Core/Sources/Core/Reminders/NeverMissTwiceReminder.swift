import Foundation

/// The only notification: the never-miss-twice evening reminder (spec-notifications.md).
public enum NeverMissTwiceReminder {
    public struct Item: Hashable, Sendable {
        public let name: String
        public let kind: HabitKind
        public let streak: Int

        public init(name: String, kind: HabitKind, streak: Int) {
            self.name = name
            self.kind = kind
            self.streak = streak
        }
    }

    public struct Message: Hashable, Sendable {
        public let title: String
        public let body: String
    }

    /// Habits that qualify tonight: missed on their last scheduled day (not recovered, not
    /// rest), scheduled today, and not done or rested yet. That's exactly the danger state.
    public static func qualifies(_ evaluation: HabitEvaluation) -> Bool {
        evaluation.history.isActiveNow && evaluation.recovery == .danger
    }

    /// One combined message for everything that qualifies, or nil (no notification).
    public static func message(for items: [Item]) -> Message? {
        switch items.count {
        case 0:
            return nil
        case 1:
            let item = items[0]
            let title = "\(item.name): never miss twice."
            if item.streak == 0 {
                return Message(title: title, body: "Do it once today to get your streak going.")
            }
            if case .amount(let unit) = item.kind, let one = singular(unit) {
                return Message(title: title, body: "One small \(one) keeps your \(item.streak)-day streak going.")
            }
            return Message(title: title, body: "Do it once today to keep your \(item.streak)-day streak going.")
        default:
            let names = items.map(\.name)
            let list = names.dropLast().joined(separator: ", ") + " and " + names.last!
            return Message(title: "Never miss twice:", body: "\(list) are still open today.")
        }
    }

    /// Units ending in "ies" are irregular ("stories" vs "movies"), so only known ones.
    static let knownIesPlurals = ["calories": "calorie", "stories": "story", "entries": "entry",
                                  "cookies": "cookie", "movies": "movie", "pastries": "pastry"]

    /// "pages" → "page", "stretches" → "stretch", "minutes" → "minute". Nil when it can't
    /// tell (then the generic wording is used).
    static func singular(_ unit: String) -> String? {
        let word = unit.trimmingCharacters(in: .whitespaces)
        guard word.count >= 3, !word.contains(" ") else { return nil }
        let lower = word.lowercased()
        if lower.hasSuffix("ies") {
            guard let known = knownIesPlurals[lower] else { return nil }
            return word == lower ? known : known.prefix(1).uppercased() + known.dropFirst()
        }
        for ending in ["ches", "shes", "sses", "xes"] where lower.hasSuffix(ending) {
            return String(word.dropLast(2))
        }
        if lower.hasSuffix("ss") || lower.hasSuffix("us") || lower.hasSuffix("is") { return nil }
        if lower.hasSuffix("s") { return String(word.dropLast()) }
        return nil
    }
}
