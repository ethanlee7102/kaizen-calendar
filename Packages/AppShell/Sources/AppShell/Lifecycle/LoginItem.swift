import ServiceManagement

/// "Open at login" through macOS's standard login items (SMAppService). The user can also change
/// it in System Settings → General → Login Items, so always read the live status.
/// The toggles that use it come with Settings (Phase 5) and onboarding (Phase 7).
public enum LoginItem {
    public enum Status: Sendable, Equatable {
        case enabled
        /// Registered, but the user has to allow it in System Settings → Login Items.
        case requiresApproval
        case disabled
    }

    public static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Opens System Settings → General → Login Items (when the user has to approve it there).
    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
