import AppKit

/// Window levels to compare. Ordered from lowest (wallpaper) to highest.
enum LevelOption: String, CaseIterable {
    case desktop
    case desktopIcon
    case aboveDesktopIcon
    case belowNormal
    case normal

    var title: String {
        switch self {
        case .desktop: "Desktop (wallpaper level)"
        case .desktopIcon: "Desktop icons level"
        case .aboveDesktopIcon: "Desktop icons + 1"
        case .belowNormal: "Normal − 1"
        case .normal: "Normal"
        }
    }

    var level: NSWindow.Level {
        switch self {
        case .desktop: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        case .desktopIcon: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        case .aboveDesktopIcon: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .belowNormal: NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        case .normal: .normal
        }
    }
}

/// Spaces group: at most one may be set.
/// `adaptive` = starts attached to the current desktop (slides with it, so no blink when leaving a
/// full-screen app). The first time a second desktop is seen, it switches to canJoinAllSpaces until
/// the next launch.
enum SpacesOption: String, CaseIterable {
    case none, canJoinAllSpaces, moveToActiveSpace, adaptive

    var behavior: NSWindow.CollectionBehavior {
        switch self {
        case .none, .adaptive: []
        case .canJoinAllSpaces: .canJoinAllSpaces
        case .moveToActiveSpace: .moveToActiveSpace
        }
    }
}

/// Mission Control (Exposé) group: at most one may be set.
enum MissionControlOption: String, CaseIterable {
    case none, managed, transient, stationary

    var behavior: NSWindow.CollectionBehavior {
        switch self {
        case .none: []
        case .managed: .managed
        case .transient: .transient
        case .stationary: .stationary
        }
    }
}

/// Independent flags that can be combined freely.
enum FlagOption: String, CaseIterable {
    case ignoresCycle, fullScreenAuxiliary, auxiliary, canJoinAllApplications

    var behavior: NSWindow.CollectionBehavior {
        switch self {
        case .ignoresCycle: .ignoresCycle
        case .fullScreenAuxiliary: .fullScreenAuxiliary
        case .auxiliary: .auxiliary
        case .canJoinAllApplications: .canJoinAllApplications
        }
    }
}

struct WindowConfig {
    var level: LevelOption = .aboveDesktopIcon
    var spaces: SpacesOption = .canJoinAllSpaces
    var missionControl: MissionControlOption = .stationary
    var flags: Set<FlagOption> = [.ignoresCycle]

    var collectionBehavior: NSWindow.CollectionBehavior {
        var b = spaces.behavior.union(missionControl.behavior)
        for f in flags { b.formUnion(f.behavior) }
        return b
    }

    var summary: String {
        let flagList = flags.map(\.rawValue).sorted().joined(separator: ",")
        return "level=\(level.title) spaces=\(spaces.rawValue) missionControl=\(missionControl.rawValue) flags=[\(flagList)]"
    }
}
