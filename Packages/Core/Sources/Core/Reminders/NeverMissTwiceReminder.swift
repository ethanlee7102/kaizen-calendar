import Foundation

/// The only notification: the never-miss-twice evening reminder (spec-notifications.md).
public enum NeverMissTwiceReminder {
    public struct Item: Hashable, Sendable {
        public let name: String
        public let streak: Int

        public init(name: String, streak: Int) {
            self.name = name
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
        evaluation.isActive && evaluation.recovery == .danger
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
            return Message(title: title, body: "Do it once today to keep your \(item.streak)-day streak going.")
        default:
            let names = items.map(\.name)
            let list = names.dropLast().joined(separator: ", ") + " and " + names.last!
            return Message(title: "Never miss twice:", body: "\(list) are still open today.")
        }
    }
}
