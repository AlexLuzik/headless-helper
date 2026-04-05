import ApplicationServices
import Foundation

/// Provides AXUIElement-based access to Control Center's Screen Mirroring panel.
/// Opens Control Center, clicks Screen Mirroring, then interacts with the device list.
enum ControlCenterAccessor {
    private static let controlCenterBundleID = "com.apple.controlcenter"
    private static let ccMenuExtraIdent = "com.apple.menuextra.controlcenter"
    private static let screenMirroringIdent = "controlcenter-screen-mirroring"
    private static let deviceListIdent = "screen-mirroring-device-list"
    private static let deviceIdentifierPrefix = "screen-mirroring-device-"

    // MARK: - Open / Close Screen Mirroring Panel

    /// Opens the Screen Mirroring panel via Control Center.
    /// Returns the Control Center app AXUIElement.
    @discardableResult
    static func openScreenMirroring() throws -> AXUIElement {
        guard let app = AXUIElement.appElement(bundleIdentifier: controlCenterBundleID) else {
            throw AirPlayError.controlCenterNotFound
        }

        // Check if Screen Mirroring panel is already open
        if let window = findControlCenterWindow(app: app),
           window.findChild(identifier: deviceListIdent, recursive: true) != nil {
            NSLog("[CC] Screen Mirroring already open")
            return app
        }

        // Step 1: Open Control Center if not already open
        if findControlCenterWindow(app: app) == nil {
            NSLog("[CC] Opening Control Center...")
            guard let ccButton = findMenuBarItem(app: app, identifier: ccMenuExtraIdent) else {
                // Fallback: try finding Screen Mirroring as a direct menu bar item
                if let smMenuItem = findScreenMirroringMenuItem(app: app) {
                    guard smMenuItem.press() else {
                        throw AirPlayError.cannotClickMenuItem
                    }
                    Thread.sleep(forTimeInterval: 1.5)
                    return app
                }
                throw AirPlayError.controlCenterNotFound
            }
            guard ccButton.press() else {
                throw AirPlayError.cannotClickMenuItem
            }
            Thread.sleep(forTimeInterval: 1.5)
        }

        // Step 2: Find and click Screen Mirroring within Control Center
        guard let window = findControlCenterWindow(app: app) else {
            NSLog("[CC] No Control Center window found after opening")
            throw AirPlayError.screenMirroringMenuNotFound
        }
        NSLog("[CC] CC window found, looking for Screen Mirroring button...")

        guard let smButton = window.findChild(identifier: screenMirroringIdent, recursive: true) else {
            NSLog("[CC] Screen Mirroring button not found in CC window")
            // Dump children for debugging
            for child in window.children {
                NSLog("[CC]   child: role=%@ id=%@ desc=%@",
                      child.role ?? "?", child.identifier ?? "nil", child.axDescription ?? "nil")
                for sub in child.children {
                    NSLog("[CC]     sub: role=%@ id=%@ desc=%@",
                          sub.role ?? "?", sub.identifier ?? "nil", sub.axDescription ?? "nil")
                }
            }
            closePanel(app: app)
            throw AirPlayError.screenMirroringMenuNotFound
        }

        NSLog("[CC] Clicking Screen Mirroring...")
        guard smButton.press() else {
            closePanel(app: app)
            throw AirPlayError.cannotClickMenuItem
        }
        Thread.sleep(forTimeInterval: 2.0)

        // Verify device list appeared
        if let updatedWindow = findControlCenterWindow(app: app),
           updatedWindow.findChild(identifier: deviceListIdent, recursive: true) != nil {
            NSLog("[CC] Screen Mirroring device list visible")
        } else {
            NSLog("[CC] Warning: device list not found after clicking Screen Mirroring")
        }

        return app
    }

    /// Closes the Control Center panel completely.
    static func closePanel(app: AXUIElement) {
        // If CC window is open, click CC button to close it
        // May need two clicks: one to exit Screen Mirroring sub-panel, one to close CC
        if findControlCenterWindow(app: app) != nil {
            if let ccButton = findMenuBarItem(app: app, identifier: ccMenuExtraIdent) {
                ccButton.press()
                Thread.sleep(forTimeInterval: 0.3)
                // Check if still open (was in sub-panel)
                if findControlCenterWindow(app: app) != nil {
                    ccButton.press()
                }
            }
        }
    }

    // MARK: - Find Devices

    /// Finds the scroll area containing AirPlay device checkboxes.
    static func findScrollArea(app: AXUIElement) -> AXUIElement? {
        guard let window = findControlCenterWindow(app: app) else {
            return nil
        }

        // Look for scroll area containing the device list
        if let scrollArea = window.findChild(role: kAXScrollAreaRole, recursive: true) {
            return scrollArea
        }

        // Fallback: the window group itself may contain checkboxes
        let groups = window.children.filter { $0.role == "AXGroup" }
        return groups.first
    }

    /// Scrolls the device list to ensure all lazy-loaded items appear.
    static func scrollToRevealAll(scrollArea: AXUIElement) {
        let scrollBars = scrollArea.children.filter { $0.role == "AXScrollBar" }
        for scrollBar in scrollBars {
            if let minVal = scrollBar.minValue {
                scrollBar.setValue(minVal)
            }
        }
        Thread.sleep(forTimeInterval: 0.2)
        for scrollBar in scrollBars {
            if let maxVal = scrollBar.maxValue {
                scrollBar.setValue(maxVal)
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Finds all device checkboxes in the scroll area.
    static func findDeviceCheckboxes(scrollArea: AXUIElement) -> [(identifier: String, element: AXUIElement)] {
        scrollArea.findAllCheckboxes(identifierPrefix: deviceIdentifierPrefix)
    }

    /// Checks if a PIN text field appeared after clicking a device.
    static func findPINTextField(app: AXUIElement) -> AXUIElement? {
        guard let window = findControlCenterWindow(app: app) else {
            return nil
        }
        return window.findChild(role: kAXTextFieldRole, recursive: true)
    }

    // MARK: - Private

    private static func findControlCenterWindow(app: AXUIElement) -> AXUIElement? {
        app.windows.first(where: { $0.title == "Control Center" })
    }

    private static func findMenuBarItem(app: AXUIElement, identifier: String) -> AXUIElement? {
        if let extrasBar: AXUIElement = app.attribute("AXExtrasMenuBar") {
            for item in extrasBar.children {
                if item.identifier == identifier {
                    return item
                }
            }
        }
        return nil
    }

    /// Fallback: look for Screen Mirroring as a standalone menu bar item.
    private static func findScreenMirroringMenuItem(app: AXUIElement) -> AXUIElement? {
        let knownDescriptions = ["Screen Mirroring", "Повтор экрана", "Видеоповтор"]

        if let extrasBar: AXUIElement = app.attribute("AXExtrasMenuBar") {
            for item in extrasBar.children {
                if let desc = item.axDescription, knownDescriptions.contains(desc) {
                    return item
                }
                if item.identifier?.contains("screen-mirroring") == true ||
                   item.identifier?.contains("screenmirror") == true {
                    return item
                }
            }
        }
        return nil
    }
}

// MARK: - Errors

enum AirPlayError: LocalizedError {
    case controlCenterNotFound
    case screenMirroringMenuNotFound
    case cannotClickMenuItem
    case scrollAreaNotFound
    case deviceNotFound(String)
    case cannotClickDevice
    case pinEntryFailed

    var errorDescription: String? {
        switch self {
        case .controlCenterNotFound:
            return "Control Center process not found"
        case .screenMirroringMenuNotFound:
            return "Screen Mirroring not found in Control Center"
        case .cannotClickMenuItem:
            return "Failed to click Screen Mirroring"
        case .scrollAreaNotFound:
            return "Screen Mirroring device list not found"
        case .deviceNotFound(let id):
            return "Device not found: \(id)"
        case .cannotClickDevice:
            return "Failed to click device"
        case .pinEntryFailed:
            return "Failed to enter PIN"
        }
    }
}
