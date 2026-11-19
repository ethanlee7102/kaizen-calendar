import AppKit
import AppShell
import UI

/// The menu bar menus. Built in code because the app uses the AppKit life cycle (see main.swift).
/// The Edit menu matters: without it, copy/paste/undo shortcuts don't reach text fields.
enum MainMenu {
    /// Debug-only tools (the build plan's debug menu grows here).
    struct DebugActions {
        var refreshToday: () -> Void
        /// Does what a click on the never-miss-twice reminder does (UI tests can't click one).
        var clickReminder: () -> Void
        /// Moves the clock just past the next report time. Nil on real data.
        var skipToNextReport: (() -> Void)?
        /// Replaces every habit with N new ones. Nil on real data.
        var replaceHabits: ((Int) -> Void)?
        /// Moves "today" by N days (nil: back to the real today). Nil on real data.
        var moveToday: ((Int?) -> Void)?
    }

    static func make(note: NoteWindowController, navigation: NotebookNavigation, debug: DebugActions?) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("66 Days", appMenu(note: note, navigation: navigation)))
        menu.addItem(submenu("Edit", editMenu()))
        menu.addItem(submenu("Window", windowMenu(note: note)))
        if let debug {
            menu.addItem(submenu("Debug", debugMenu(note: note, actions: debug)))
        }
        return menu
    }

    private static func appMenu(note: NoteWindowController, navigation: NotebookNavigation) -> NSMenu {
        let menu = NSMenu(title: "66 Days")
        menu.addItem(NSMenuItem(title: "About 66 Days",
                                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        // Settings live in the notebook's Settings tab (spec-settings.md).
        menu.addItem(actionItem("Settings…", key: ",") {
            navigation.show(.settings)
            note.expand()
        })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Hide 66 Days", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "Hide Others",
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(NSMenuItem(title: "Show All",
                                action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit 66 Days", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        let pasteMatching = NSMenuItem(title: "Paste and Match Style",
                                       action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pasteMatching.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(pasteMatching)
        menu.addItem(NSMenuItem(title: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    private static func windowMenu(note: NoteWindowController) -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(actionItem("Expand Note") { note.expand() })
        menu.addItem(actionItem("Collapse Note", key: "w") { note.collapse() })
        return menu
    }

    private static func debugMenu(note: NoteWindowController, actions: DebugActions) -> NSMenu {
        let menu = NSMenu(title: "Debug")
        if let replaceHabits = actions.replaceHabits {
            let habits = NSMenu(title: "Test Habits")
            for count in 0...5 {
                habits.addItem(actionItem("\(count)") { replaceHabits(count) })
            }
            menu.addItem(submenu("Test Habits", habits))
        }
        if let moveToday = actions.moveToday {
            menu.addItem(actionItem("Next Day", key: "]") { moveToday(1) })
            menu.addItem(actionItem("Previous Day", key: "[") { moveToday(-1) })
            menu.addItem(actionItem("Back to Today") { moveToday(nil) })
            if let skip = actions.skipToNextReport {
                menu.addItem(actionItem("Skip to Next Report", key: "r", handler: skip))
            }
            menu.addItem(.separator())
        }
        menu.addItem(actionItem("Reset Note Position") { note.resetPosition() })
        menu.addItem(actionItem("Refresh Today") { actions.refreshToday() })
        menu.addItem(actionItem("Click the Reminder", handler: actions.clickReminder))
        menu.addItem(.separator())
        menu.addItem(actionItem("Open at Login", isOn: { LoginItem.status != .disabled }) {
            do {
                try LoginItem.setEnabled(LoginItem.status == .disabled)
                if LoginItem.status == .requiresApproval { LoginItem.openSystemSettings() }
            } catch {
                NSSound.beep()
                print("Open at Login failed: \(error)")
            }
        })
        return menu
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// Makes a menu item that runs a closure, optionally with a checkmark read when the menu opens.
private func actionItem(_ title: String, key: String = "", isOn: (() -> Bool)? = nil,
                            handler: @escaping () -> Void) -> NSMenuItem {
    let action = MenuAction(handler: handler, isOn: isOn)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.run(_:)), keyEquivalent: key)
    item.target = action
    item.representedObject = action // the item keeps its target alive
    return item
}

private final class MenuAction: NSObject, NSMenuItemValidation {
    private let handler: () -> Void
    private let isOn: (() -> Bool)?

    init(handler: @escaping () -> Void, isOn: (() -> Bool)?) {
        self.handler = handler
        self.isOn = isOn
    }

    @objc func run(_ sender: NSMenuItem) {
        handler()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let isOn { menuItem.state = isOn() ? .on : .off }
        return true
    }
}
