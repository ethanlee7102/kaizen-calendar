import AppKit
import AppShell
import Core
import Foundation
import Observation
import Persistence
import UI

/// The never-miss-twice reminder on real data (spec-notifications.md): keeps tonight's
/// notification matching the habits (Core's `NeverMissTwiceReminder.plan`, applied by
/// `ReminderScheduler`), decides when the note asks "Want a gentle reminder tonight…?", and
/// handles the answer.
///
/// It checks again after every change to the data, the day, the settings or the permission, at
/// tonight's reminder time (the prompt hides then), on wake and on clock changes.
@MainActor
@Observable
final class ReminderController {
    /// The note shows the prompt.
    private(set) var showsPrompt = false

    let scheduler: ReminderScheduler
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var monitor: DayChangeMonitor?
    @ObservationIgnored private var model: AppModel?
    static let key = "reminder.scheduled"

    /// No `defaults`: the last scheduled reminder is kept in memory only (UI tests, sample data).
    init(center: ReminderCenter, defaults: UserDefaults?) {
        scheduler = ReminderScheduler(center: center)
        self.defaults = defaults
        last = defaults?.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(NeverMissTwiceReminder.Scheduled.self, from: $0) }
    }

    /// macOS lets 66 Days notify, as the Settings tab shows it. Unknown until read: shown as
    /// allowed, so "off in System Settings" never flashes up.
    var access: SettingsValues.ReminderAccess {
        switch scheduler.permission {
        case .notDetermined: .notAsked
        case .denied: .blocked
        case .allowed, nil: .allowed
        }
    }

    func start(_ model: AppModel) {
        self.model = model
        scheduler.refreshPermission()
        let monitor = DayChangeMonitor(
            // The app's clock, like `nextCheck`: with a fixed or shifted day (UI tests, Debug
            // time travel) the real clock would see tonight as past and fire every second
            // (Phase 8 review).
            now: { model.currentDate },
            nextChange: { [weak self] in self?.nextCheck(model) ?? .distantFuture },
            onChange: { [weak self] in
                self?.scheduler.refreshPermission()
                self?.update()
            })
        monitor.start()
        self.monitor = monitor
        Task { [weak self] in
            // Anything the plan reads: the habits (through the evaluations), today, the settings
            // and the permission.
            for await _ in Observations({ [weak self] in
                (model.evaluations, model.today, model.data.settings, model.hasLoaded,
                 model.data.onboardingCompleted, self?.scheduler.permission, self?.scheduler.isAskingPermission)
            }) {
                self?.update()
                self?.monitor?.reschedule()
            }
        }
    }

    /// Back in the app or the notebook opened: the user may have changed it in System Settings.
    func refreshPermission() {
        scheduler.refreshPermission()
    }

    /// "Yes, remind me" shows macOS's dialog; "No thanks" turns the reminder off (it can be
    /// turned on again in Settings; decided in the Phase 8 build).
    func answerPrompt(_ yes: Bool) {
        if yes {
            scheduler.requestPermission()
        } else if let model {
            Writes.attempt("reminder off") { try model.repository.updateSettings { $0.reminderEnabled = false } }
        }
    }

    /// The reminder was turned on in Settings: ask macOS if it never was.
    func reminderTurnedOn() {
        // The scheduler checks it's undecided itself, so this works even before the permission
        // was first read (Phase 8 review).
        scheduler.requestPermission()
    }

    // MARK: Plan

    /// The reminder handed to macOS last (`NeverMissTwiceReminder.Plan.record`), kept on this Mac.
    @ObservationIgnored private var last: NeverMissTwiceReminder.Scheduled? {
        didSet {
            if let last, let data = try? JSONEncoder().encode(last) {
                defaults?.set(data, forKey: Self.key)
            } else {
                defaults?.removeObject(forKey: Self.key)
            }
        }
    }

    private func fireDate(_ model: AppModel) -> Date {
        let settings = model.data.settings
        return NeverMissTwiceReminder.fireDate(on: model.today, hour: settings.reminderHour,
                                               minute: settings.reminderMinute, dayEnd: settings.dayEnd)
    }

    /// Tonight's reminder time while it's ahead (the prompt hides then and the plan records that
    /// it fired); otherwise the end of today (the day change brings a new plan anyway).
    private func nextCheck(_ model: AppModel) -> Date {
        let fire = fireDate(model)
        return fire > model.currentDate ? fire : model.data.settings.dayEnd.end(of: model.today)
    }

    private func update() {
        guard let model else { return }
        // Nothing before the data is read, and nothing during onboarding (no habits have a past
        // yet, and the note isn't in use).
        // Nor before the permission was read: unknown isn't "not allowed", and treating it so
        // would cancel tonight's reminder and remove a delivered one at every launch (Phase 8
        // review). Reading it changes `permission`, which runs this again.
        guard model.hasLoaded, model.data.onboardingCompleted, scheduler.permission != nil else {
            if showsPrompt { showsPrompt = false }
            return
        }
        let settings = model.data.settings
        let names = Dictionary(model.data.habits.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let items = NeverMissTwiceReminder.items(model.activeEvaluations) { names[$0] }
        let now = model.currentDate
        let fire = fireDate(model)

        let plan = NeverMissTwiceReminder.plan(
            items: items, isEnabled: settings.reminderEnabled, canNotify: scheduler.permission == .allowed,
            today: model.today, now: now, fireDate: fire, last: last)
        if last != plan.record { last = plan.record }
        let change: ReminderScheduler.PendingChange = switch plan.pending {
        case .schedule(let pending):
            .schedule(ReminderRequest(title: pending.message.title, body: pending.message.body,
                                      date: pending.scheduled.fireDate))
        case .cancel: .cancel
        case .leave: .leave
        }
        scheduler.apply(pending: change, keepsDelivered: plan.keepsDelivered)

        let prompt = NeverMissTwiceReminder.showsPrompt(
            anyQualifies: !items.isEmpty, isEnabled: settings.reminderEnabled,
            permissionUndecided: scheduler.permission == .notDetermined && !scheduler.isAskingPermission,
            now: now, fireDate: fire)
        if prompt != showsPrompt { showsPrompt = prompt }
    }
}
