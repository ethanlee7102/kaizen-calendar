import AppKit
import SwiftUI

@MainActor
@Observable
final class NoteState {
    var expanded = false
    var checks = [false, false, false]
    var status = ""
    var log: [String] = []
    var config = WindowConfig()
}

let sampleGoals = ["Read 10 pages", "10 pushups", "Meditate 2 min"]

struct NoteView: View {
    @Bindable var state: NoteState
    var onToggleExpand: () -> Void
    var onConfigChanged: () -> Void
    var onMarker: (String) -> Void
    @State private var marker = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("66 Days").font(.headline)
                Spacer()
                Button(state.expanded ? "Collapse" : "Expand", action: onToggleExpand)
                    .controlSize(.small)
            }

            ForEach(sampleGoals.indices, id: \.self) { i in
                Toggle(sampleGoals[i], isOn: $state.checks[i])
                    .toggleStyle(.checkbox)
            }

            // Quick test toggle (visible while collapsed): one desktop vs all desktops vs automatic.
            Picker("", selection: binding(\.spaces)) {
                Text("1 desktop").tag(SpacesOption.none)
                Text("All").tag(SpacesOption.canJoinAllSpaces)
                Text("Auto").tag(SpacesOption.adaptive)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            Text(state.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.expanded {
                Divider()
                settings
                Divider()
                HStack {
                    TextField("Test marker (what you're about to test)", text: $marker)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addMarker)
                    Button("Add Marker", action: addMarker).disabled(marker.isEmpty)
                }
                Divider()
                Text("Event log (newest first)").font(.caption.bold())
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(state.log.reversed().enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Prototype window settings (same as the menu bar menu). They apply when the note is collapsed.
    private var settings: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Window settings (apply when collapsed)").font(.caption.bold())
            Picker("Level", selection: binding(\.level)) {
                ForEach(LevelOption.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Spaces", selection: binding(\.spaces)) {
                ForEach(SpacesOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Mission Control", selection: binding(\.missionControl)) {
                ForEach(MissionControlOption.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                ForEach(FlagOption.allCases, id: \.self) { flag in
                    Toggle(flag.rawValue, isOn: Binding(
                        get: { state.config.flags.contains(flag) },
                        set: { on in
                            if on { state.config.flags.insert(flag) } else { state.config.flags.remove(flag) }
                            onConfigChanged()
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                }
            }
        }
        .controlSize(.small)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<WindowConfig, T>) -> Binding<T> {
        Binding(
            get: { state.config[keyPath: keyPath] },
            set: { state.config[keyPath: keyPath] = $0; onConfigChanged() }
        )
    }

    private func addMarker() {
        guard !marker.isEmpty else { return }
        onMarker(marker)
        marker = ""
    }
}

/// Borderless panel that can take clicks without needing a title bar.
final class NoteWindow: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
