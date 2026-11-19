import Core
import SwiftUI

/// The Settings tab (spec-settings.md): four groups, saved instantly. No info buttons (none of
/// these have a research source). Appearance shows only once Dark mode is unlocked.
struct SettingsTabView: View {
    let settings: SettingsValues
    let actions: NotebookActions

    @Environment(\.shortcutRecorder) private var shortcutRecorder
    @State private var exportMessage: String?
    @State private var resetMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings")
                .font(.heading(28))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            group("Your day") {
                row("My day ends at", caption: settings.dayEndCaption) {
                    ChoiceChips(options: Array(SettingsValues.dayEndHours), selection: settings.dayEndHour,
                                title: SettingsValues.dayEndTitle, identifier: "settings.dayEnd") { hour in
                        update { $0.dayEndHour = hour }
                    }
                }
            }
            group("Reports & reminders") {
                row("Weekly report", caption: settings.monthlyNote) {
                    HStack(spacing: 8) {
                        Picker("Report day", selection: binding(\.reportWeekday)) {
                            ForEach(Weekday.allCases, id: \.self) { Text(DayText.weekdayName($0)).tag($0) }
                        }
                        .accessibilityIdentifier("settings.reportDay")
                        Picker("Report time", selection: Binding(
                            get: { settings.reportHour },
                            set: { hour in update { $0.reportHour = hour; $0.reportMinute = 0 } })) {
                            ForEach(Self.hours(including: settings.reportHour), id: \.self) { hour in
                                Text(hour == settings.reportHour ? settings.reportTime : SettingsValues.time(hour: hour, minute: 0))
                                    .tag(hour)
                            }
                        }
                        .accessibilityIdentifier("settings.reportTime")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                row("Never-miss-twice reminder", caption: settings.reminderCaption) {
                    HStack(spacing: 8) {
                        if settings.reminderBlocked {
                            Button("Open Notification Settings") {
                                actions.used()
                                actions.openNotificationSettings()
                            }
                            .buttonStyle(PaperButtonStyle())
                            .accessibilityIdentifier("settings.openNotificationSettings")
                        } else if settings.reminderEnabled {
                            Picker("Reminder time", selection: Binding(
                                get: { settings.reminderHour },
                                set: { hour in update { $0.reminderHour = hour; $0.reminderMinute = 0 } })) {
                                ForEach(NeverMissTwiceReminder.reminderHours(dayEndHour: settings.dayEndHour,
                                                                             including: settings.reminderHour),
                                        id: \.self) { hour in
                                    Text(hour == settings.reminderHour ? settings.reminderTime
                                                                       : SettingsValues.time(hour: hour, minute: 0))
                                        .tag(hour)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                            .accessibilityIdentifier("settings.reminderTime")
                        }
                        PaperToggle(label: "Never-miss-twice reminder", isOn: settings.reminderEnabled,
                                    identifier: "settings.reminder") { on in update { $0.reminderEnabled = on } }
                    }
                }
            }
            group("Look & feel") {
                if settings.appearanceUnlocked {
                    row("Appearance", caption: nil) {
                        AppearanceChips(selection: settings.appearance) { choice in update { $0.appearance = choice } }
                    }
                }
                row("Sounds", caption: "Water and stamp sounds. Always silent when your Mac is muted.") {
                    PaperToggle(label: "Sounds", isOn: settings.soundsEnabled, identifier: "settings.sounds") { on in
                        update { $0.soundsEnabled = on }
                    }
                }
                row("Reduce motion", caption: "On: no waves or bobbing, simple fades only.") {
                    ChoiceChips(options: SettingsValues.ReduceMotion.allCases, selection: settings.reduceMotion,
                                title: \.title, identifier: "settings.reduceMotion") { choice in
                        update { $0.reduceMotion = choice }
                    }
                }
                row("Expand/collapse shortcut", caption: "A keyboard shortcut that opens and folds the notebook from any app.") {
                    if let shortcutRecorder { shortcutRecorder.fixedSize() }
                }
            }
            group("Data") {
                row("Open at login", caption: loginCaption) {
                    HStack(spacing: 8) {
                        if settings.openAtLogin == .needsApproval {
                            Button("Open Login Items") {
                                actions.used()
                                actions.openLoginItemsSettings()
                            }
                            .buttonStyle(PaperButtonStyle())
                        }
                        PaperToggle(label: "Open at login", isOn: settings.openAtLogin != .off,
                                    identifier: "settings.openAtLogin") { on in
                            actions.used()
                            actions.setOpenAtLogin(on)
                        }
                    }
                }
                row("Export my data",
                    caption: exportMessage ?? "A readable JSON file with everything: habits, check-offs, rest days, notes and report answers.") {
                    Button("Export…") {
                        actions.used()
                        exportMessage = actions.exportData()
                    }
                    .buttonStyle(PaperButtonStyle())
                    .accessibilityIdentifier("settings.export")
                }
                row("Reset note position", caption: resetMessage ?? "Moves the note back to the top-right of the main display.") {
                    Button("Reset") {
                        actions.used()
                        actions.resetNotePosition()
                        resetMessage = "Done. The note is back at the top-right."
                    }
                    .buttonStyle(PaperButtonStyle())
                    .accessibilityIdentifier("settings.resetPosition")
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private var loginCaption: String {
        settings.openAtLogin == .needsApproval
            ? "macOS needs your OK: allow 66 Days in System Settings › General › Login Items."
            : "66 Days opens when you log in, so the note is always on your desktop."
    }

    /// Every hour on the hour. A stored time off the hour (not settable here) shows as itself
    /// on its hour's item.
    static func hours(including hour: Int) -> [Int] { Array(0...23) }

    private func update(_ change: @escaping (inout SettingsValues) -> Void) {
        actions.used()
        actions.updateSettings(change)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SettingsValues, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.heading(16))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) { rows() }
                .background(Palette.raisedPaper.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.track))
        }
    }

    private func row(_ title: String, caption: String?, @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.text(13, weight: .medium))
                    .foregroundStyle(Palette.ink)
                if let caption {
                    Text(caption)
                        .font(.text(11.5))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Palette.track).frame(height: 1).padding(.horizontal, 14).opacity(0.7) }
    }
}

/// An on/off switch drawn on the paper (indigo when on).
struct PaperToggle: View {
    let label: String
    let isOn: Bool
    let identifier: String
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!isOn) } label: {
            Capsule()
                .fill(isOn ? AnyShapeStyle(Palette.indigo) : AnyShapeStyle(Palette.fieldLine))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(Palette.raisedPaper).frame(width: 16, height: 16).padding(2)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                }
                .animation(.easeInOut(duration: 0.15), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier(identifier)
    }
}
