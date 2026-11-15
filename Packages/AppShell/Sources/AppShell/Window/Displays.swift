import AppKit

extension NSScreen {
    /// The display's UUID. Unlike `CGDirectDisplayID`, it stays the same across unplug/replug
    /// and restarts, so saved positions find their display again.
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    var display: Display? {
        displayUUID.map { Display(id: $0, visibleFrame: visibleFrame) }
    }
}

extension Display {
    /// The connected displays, the main display (with the menu bar) first.
    static var connected: [Display] {
        NSScreen.screens.compactMap(\.display)
    }
}
