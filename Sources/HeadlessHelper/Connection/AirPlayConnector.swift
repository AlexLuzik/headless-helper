import ApplicationServices
import CoreGraphics
import Foundation

/// Result of a connection attempt.
enum ConnectResult {
    case connected
    case alreadyConnected
    case needsPIN
}

/// Orchestrates connecting to an AirPlay device via Control Center UI automation.
final class AirPlayConnector {

    func connect(device: AirPlayDevice) async throws -> ConnectResult {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let app = try ControlCenterAccessor.openScreenMirroring()

                    guard let scrollArea = ControlCenterAccessor.findScrollArea(app: app) else {
                        ControlCenterAccessor.closePanel(app: app)
                        continuation.resume(throwing: AirPlayError.scrollAreaNotFound)
                        return
                    }

                    ControlCenterAccessor.scrollToRevealAll(scrollArea: scrollArea)

                    // Check if target device is already connected (DisclosureTriangle = active)
                    let allElements = scrollArea.findAllRecursive(role: kAXDisclosureTriangleRole)
                    for el in allElements {
                        if el.axDescription == device.name {
                            NSLog("[Connector] '%@' is already connected", device.name)

                            // Check if mirroring or extending
                            let texts = scrollArea.findAllRecursive(role: kAXStaticTextRole)
                            let isMirroring = texts.contains { ($0.value as? String)?.contains("Mirroring") == true }

                            if isMirroring {
                                NSLog("[Connector] Already mirroring to '%@'", device.name)
                                ControlCenterAccessor.closePanel(app: app)
                                continuation.resume(returning: .alreadyConnected)
                                return
                            }

                            // Connected but extending — switch to mirror
                            NSLog("[Connector] Connected but not mirroring — switching...")
                            self.switchToMirroring(scrollArea: scrollArea, app: app)
                            ControlCenterAccessor.closePanel(app: app)
                            continuation.resume(returning: .connected)
                            return
                        }
                    }

                    // Device not connected — find its checkbox and click
                    let checkboxes = ControlCenterAccessor.findDeviceCheckboxes(scrollArea: scrollArea)
                    NSLog("[Connector] Looking for '%@' among %d devices", device.name, checkboxes.count)

                    let target = checkboxes.first { $0.element.axDescription == device.name }
                        ?? checkboxes.first { $0.identifier.contains(device.id) }

                    guard let target else {
                        ControlCenterAccessor.closePanel(app: app)
                        continuation.resume(throwing: AirPlayError.deviceNotFound(device.name))
                        return
                    }

                    guard target.element.press() else {
                        ControlCenterAccessor.closePanel(app: app)
                        continuation.resume(throwing: AirPlayError.cannotClickDevice)
                        return
                    }

                    NSLog("[Connector] Clicked device, waiting for connection...")

                    // Poll for PIN dialog — it may take several seconds to appear
                    for i in 0..<12 { // up to 6 seconds
                        Thread.sleep(forTimeInterval: 0.5)
                        if Self.isPINDialogVisible() {
                            NSLog("[Connector] PIN dialog detected after %.1fs", Double(i + 1) * 0.5)
                            ControlCenterAccessor.closePanel(app: app)
                            continuation.resume(returning: .needsPIN)
                            return
                        }
                    }

                    // Reopen CC -> SM to check status and ensure mirroring
                    ControlCenterAccessor.closePanel(app: app)
                    Thread.sleep(forTimeInterval: 1.0)

                    NSLog("[Connector] Reopening CC to check status...")
                    do {
                        try ControlCenterAccessor.openScreenMirroring()
                    } catch {
                        NSLog("[Connector] Could not reopen SM: %@", error.localizedDescription)
                        continuation.resume(returning: .connected)
                        return
                    }
                    Thread.sleep(forTimeInterval: 3.0)

                    // PIN might have appeared during reopen
                    if Self.isPINDialogVisible() {
                        NSLog("[Connector] PIN dialog detected during status check")
                        ControlCenterAccessor.closePanel(app: app)
                        continuation.resume(returning: .needsPIN)
                        return
                    }

                    guard let scrollArea2 = ControlCenterAccessor.findScrollArea(app: app) else {
                        NSLog("[Connector] No scroll area after reopen — assuming connected")
                        ControlCenterAccessor.closePanel(app: app)
                        continuation.resume(returning: .connected)
                        return
                    }

                    // Already mirroring?
                    let texts = scrollArea2.findAllRecursive(role: kAXStaticTextRole)
                    if texts.contains(where: { ($0.value as? String)?.contains("Mirroring") == true }) {
                        NSLog("[Connector] Mirroring confirmed")
                        ControlCenterAccessor.closePanel(app: app)
                        continuation.resume(returning: .connected)
                        return
                    }

                    // Not mirroring — try to switch
                    self.switchToMirroring(scrollArea: scrollArea2, app: app)
                    ControlCenterAccessor.closePanel(app: app)
                    continuation.resume(returning: .connected)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Switch to Mirroring

    /// If device is connected but extending/just connected, click "Change"/"Choose Content"
    /// and automate the picker to select "Entire Screen" + "Start Mirroring".
    private func switchToMirroring(scrollArea: AXUIElement, app: AXUIElement) {
        let buttons = scrollArea.findAllRecursive(role: kAXButtonRole)
        let pickerButton = buttons.first(where: { $0.axDescription == "Choose Content" })
            ?? buttons.first(where: { $0.axDescription == "Change" })

        guard let btn = pickerButton else {
            NSLog("[Connector] No Change/Choose Content button found")
            return
        }

        NSLog("[Connector] Clicking '%@'...", btn.axDescription ?? "?")
        btn.press()
        Thread.sleep(forTimeInterval: 2.0)

        if Self.clickStartMirroringInPicker() {
            NSLog("[Connector] Picker automated successfully")
        } else {
            NSLog("[Connector] Picker not found")
        }
        Thread.sleep(forTimeInterval: 3.0)
    }

    // MARK: - Ensure Mirroring After Connection

    /// Check if device is connected and ensure mirroring. Returns true if connected.
    func ensureMirroring() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Thread.sleep(forTimeInterval: 2.0)

                guard let app = AXUIElement.appElement(bundleIdentifier: "com.apple.controlcenter") else {
                    continuation.resume(returning: false)
                    return
                }

                do {
                    try ControlCenterAccessor.openScreenMirroring()
                } catch {
                    continuation.resume(returning: false)
                    return
                }
                Thread.sleep(forTimeInterval: 3.0)

                guard let scrollArea = ControlCenterAccessor.findScrollArea(app: app) else {
                    ControlCenterAccessor.closePanel(app: app)
                    continuation.resume(returning: false)
                    return
                }

                // Check if any device is connected (DisclosureTriangle = active device)
                let activeDevices = scrollArea.findAllRecursive(role: kAXDisclosureTriangleRole)
                if activeDevices.isEmpty {
                    NSLog("[Connector] No active device — not connected")
                    ControlCenterAccessor.closePanel(app: app)
                    continuation.resume(returning: false)
                    return
                }

                // Already mirroring?
                let texts = scrollArea.findAllRecursive(role: kAXStaticTextRole)
                if texts.contains(where: { ($0.value as? String)?.contains("Mirroring") == true }) {
                    NSLog("[Connector] Already mirroring")
                    ControlCenterAccessor.closePanel(app: app)
                    continuation.resume(returning: true)
                    return
                }

                // Connected but not mirroring — switch
                self.switchToMirroring(scrollArea: scrollArea, app: app)
                ControlCenterAccessor.closePanel(app: app)
                continuation.resume(returning: true)
            }
        }
    }

    // MARK: - PIN Dialog Detection

    /// Check if the AirPlay PIN dialog is visible (owned by AirPlayUIAgent).
    private static func isPINDialogVisible() -> Bool {
        guard let app = AXUIElement.appElement(bundleIdentifier: "com.apple.AirPlayUIAgent") else {
            return false
        }
        let windows: [AXUIElement] = app.windows
        return windows.contains { $0.title?.contains("AirPlay") == true || $0.title?.contains("Code") == true }
    }

    // MARK: - Picker Dialog Automation

    private static func clickStartMirroringInPicker() -> Bool {
        for _ in 0..<10 {
            if let b = findPickerWindowBounds() {
                NSLog("[Connector] Picker window: x=%.0f y=%.0f w=%.0f h=%.0f",
                      b.origin.x, b.origin.y, b.width, b.height)

                // Click "Entire Screen" — first option, left side
                let entireScreenX = b.origin.x + b.width * 0.20
                let entireScreenY = b.origin.y + b.height * 0.52
                NSLog("[Connector] Clicking Entire Screen at (%.0f, %.0f)", entireScreenX, entireScreenY)
                clickAt(x: entireScreenX, y: entireScreenY)
                Thread.sleep(forTimeInterval: 0.5)

                // Click "Start Mirroring" — bottom-right button
                let startX = b.origin.x + b.width - 90
                let startY = b.origin.y + b.height - 35
                NSLog("[Connector] Clicking Start Mirroring at (%.0f, %.0f)", startX, startY)
                clickAt(x: startX, y: startY)
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private static func findPickerWindowBounds() -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in windowList {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let name = window[kCGWindowName as String] as? String ?? ""
            let layer = window[kCGWindowLayer as String] as? Int ?? 0

            guard owner.contains("Control Center"), name.isEmpty, layer > 0 else { continue }

            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? Double,
                  let y = boundsDict["Y"] as? Double,
                  let w = boundsDict["Width"] as? Double,
                  let h = boundsDict["Height"] as? Double else { continue }

            if w > 400 && w < 800 && h > 250 && h < 500 {
                return CGRect(x: x, y: y, width: w, height: h)
            }
        }
        return nil
    }

    private static func clickAt(x: Double, y: Double) {
        let helperPath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("click_helper").path

        if let path = helperPath, FileManager.default.fileExists(atPath: path) {
            NSLog("[Connector] click_helper at (%d, %d)", Int(x), Int(y))
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = [String(Int(x)), String(Int(y))]
            try? process.run()
            process.waitUntilExit()
        } else {
            NSLog("[Connector] click_helper not found, using CGEvent fallback")
            let point = CGPoint(x: x, y: y)
            CGWarpMouseCursorPosition(point)
            CGAssociateMouseAndMouseCursorPosition(1)
            Thread.sleep(forTimeInterval: 0.3)
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                              mouseCursorPosition: point, mouseButton: .left)
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                            mouseCursorPosition: point, mouseButton: .left)
            down?.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05)
            up?.post(tap: .cghidEventTap)
        }
    }
}
