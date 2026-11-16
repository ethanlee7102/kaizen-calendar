import Core

/// The new-habit form's fields and rules (spec-collapsed-note.md §8), with no SwiftUI involved.
nonisolated public struct HabitDraft: Hashable, Sendable {
    public enum Kind: Hashable, Sendable, CaseIterable {
        /// "Track an amount" (default): a number and a unit.
        case amount
        /// "Just do it": a yes/no habit.
        case yesNo
    }

    public enum ScheduleChoice: Hashable, Sendable {
        case everyDay
        case specificDays
    }

    public var name = ""
    public var kind: Kind = .amount
    /// Digits only (the field filters input).
    public var target = ""
    public var unit = ""
    public var scheduleChoice: ScheduleChoice = .everyDay
    /// The picked weekdays for "Specific days". None picked at first.
    public var weekdays: WeekdaySet = []
    public var identity = ""

    public init() {}

    /// What the repository needs to add the habit, or nil while the form is incomplete.
    public struct Request: Hashable, Sendable {
        public let name: String
        public let identity: String?
        public let kind: HabitKind
        public let target: Int?
        public let schedule: Schedule
    }

    /// The largest target the field accepts (a sanity limit, not a rule).
    public static let maxTarget = 99_999

    public var targetAmount: Int? {
        guard let value = Int(target), (1...Self.maxTarget).contains(value) else { return nil }
        return value
    }

    /// Under the target field while it holds 0 (user's choice after the Phase 4 review).
    public var targetHint: String? {
        kind == .amount && !target.isEmpty && Int(target) == 0 ? "At least 1." : nil
    }

    public var schedule: Schedule? {
        switch scheduleChoice {
        case .everyDay: .everyDay
        case .specificDays: Schedule(days: weekdays)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUnit: String { unit.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedIdentity: String { identity.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "Add habit" is enabled once there's a name, a target number and unit for "Track an
    /// amount", and at least one day for "Specific days".
    public var request: Request? {
        guard !trimmedName.isEmpty, let schedule else { return nil }
        let identity = trimmedIdentity.isEmpty ? nil : trimmedIdentity
        switch kind {
        case .amount:
            guard let amount = targetAmount, !trimmedUnit.isEmpty else { return nil }
            return Request(name: trimmedName, identity: identity, kind: .amount(unit: trimmedUnit), target: amount,
                           schedule: schedule)
        case .yesNo:
            return Request(name: trimmedName, identity: identity, kind: .yesNo, target: nil, schedule: schedule)
        }
    }

    /// The live preview row's name.
    public var previewName: String { trimmedName.isEmpty ? "Your habit" : trimmedName }

    /// The live preview row's second line: `target · schedule · I'm …`, with the parts filled in
    /// so far.
    public var previewDetails: String {
        var parts: [String] = []
        if kind == .amount, let amount = targetAmount {
            parts.append(trimmedUnit.isEmpty ? "\(amount)" : "\(amount) \(trimmedUnit)")
        }
        if let schedule { parts.append(DayText.schedule(schedule)) }
        if !trimmedIdentity.isEmpty { parts.append("I’m \(trimmedIdentity)") }
        return parts.joined(separator: " · ")
    }

    /// Keeps only digits, at most 5 of them.
    public static func filteredTarget(_ text: String) -> String {
        String(text.filter { $0.isASCII && $0.isNumber }.prefix(5))
    }
}
