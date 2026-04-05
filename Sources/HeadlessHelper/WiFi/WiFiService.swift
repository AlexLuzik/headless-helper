import ApplicationServices
import CoreGraphics
import Foundation

/// Manages WiFi connections via Control Center UI automation.
final class WiFiService {

    private static let controlCenterBundleID = "com.apple.controlcenter"
    private static let ccMenuExtraIdent = "com.apple.menuextra.controlcenter"
    private static let wifiIdent = "controlcenter-wifi"
    private static let networkPrefix = "wifi-network-"

    // MARK: - Scan Networks

    /// Opens CC → WiFi panel, reads available networks, closes CC.
    func scanNetworks() -> [WiFiNetwork] {
        guard let app = AXUIElement.appElement(bundleIdentifier: Self.controlCenterBundleID) else {
            NSLog("[WiFi] Control Center not found")
            return []
        }

        do {
            try openWiFiPanel(app: app)
        } catch {
            NSLog("[WiFi] Could not open WiFi panel: %@", error.localizedDescription)
            return []
        }
        Thread.sleep(forTimeInterval: 2.0)

        // Expand "Other Networks" if present
        expandOtherNetworks(app: app)
        Thread.sleep(forTimeInterval: 1.0)

        let networks = readNetworks(app: app)
        closePanel(app: app)

        NSLog("[WiFi] Found %d networks", networks.count)
        return networks
    }

    enum WiFiConnectResult {
        case connected
        case needsPassword
        case failed
    }

    // MARK: - Connect

    /// Connect to a WiFi network by clicking its checkbox in CC.
    func connect(network: WiFiNetwork) -> WiFiConnectResult {
        guard let app = AXUIElement.appElement(bundleIdentifier: Self.controlCenterBundleID) else { return .failed }

        do {
            try openWiFiPanel(app: app)
        } catch {
            NSLog("[WiFi] Could not open WiFi panel")
            return .failed
        }
        Thread.sleep(forTimeInterval: 2.0)

        expandOtherNetworks(app: app)
        Thread.sleep(forTimeInterval: 0.5)

        guard let scrollArea = findWiFiScrollArea(app: app) else {
            closePanel(app: app)
            return .failed
        }

        let checkboxes = scrollArea.findAllRecursive(role: kAXCheckBoxRole)
        guard let target = checkboxes.first(where: { $0.identifier == network.id }) else {
            NSLog("[WiFi] Network '%@' not found in list", network.name)
            closePanel(app: app)
            return .failed
        }

        NSLog("[WiFi] Clicking network '%@'", network.name)
        target.press()
        Thread.sleep(forTimeInterval: 3.0)

        closePanel(app: app)

        // Check if password dialog appeared
        if Self.isPasswordDialogVisible() {
            NSLog("[WiFi] Password dialog detected")
            return .needsPassword
        }

        return .connected
    }

    enum PasswordResult {
        case connected
        case error(String)
        case cancelled
    }

    /// Wait for WiFi password flow to complete.
    /// Phase 1: wait for password dialog to close (user clicks Join/Cancel)
    /// Phase 2: wait up to 30s — if dialog reappears → read error; if IP appears → connected
    func waitForPasswordResult(expectedSSID: String) -> PasswordResult {
        // Phase 1: Wait for dialog to close
        for _ in 0..<120 {
            Thread.sleep(forTimeInterval: 0.5)
            if !Self.isPasswordDialogVisible() { break }
        }
        guard !Self.isPasswordDialogVisible() else { return .cancelled }

        NSLog("[WiFi] Dialog closed, monitoring for result...")

        // Remember if we had IP before (to detect new connection)
        let hadIP = Self.hasIPAddress()

        // Phase 2: Poll — dialog reappears with error OR network connects
        for i in 0..<60 { // 30 seconds
            Thread.sleep(forTimeInterval: 0.5)

            // Error: dialog reappeared
            if Self.isPasswordDialogVisible() {
                Thread.sleep(forTimeInterval: 1.0) // let it load
                let status = Self.readDialogStatus()
                let err = status.error ?? "Connection failed."
                NSLog("[WiFi] Error detected: %@", err)
                return .error(err)
            }

            // Success: got IP (or still have IP after reconnect)
            if i > 4 && Self.hasIPAddress() {
                NSLog("[WiFi] Network connected (IP active)")
                return .connected
            }
        }

        if Self.hasIPAddress() { return .connected }
        return .error("Connection timed out.")
    }

    /// Check if en0 has an IP address (= WiFi connected).
    private static func hasIPAddress() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        task.arguments = ["getifaddr", "en0"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !output.isEmpty
    }

    /// Find the Wi-Fi password dialog PID via CGWindowList.
    /// The dialog is owned by a process named "Wi-Fi".
    private static func findWiFiDialogPID() -> pid_t? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in windowList {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let pid = window[kCGWindowOwnerPID as String] as? Int ?? 0
            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            if owner == "Wi-Fi" && layer > 0 && pid > 0 {
                return pid_t(pid)
            }
        }
        return nil
    }

    /// Check if the WiFi password dialog is visible.
    private static func isPasswordDialogVisible() -> Bool {
        return findWiFiDialogPID() != nil
    }

    /// Read error text from the WiFi password dialog (e.g. "Connection failed.").
    static func readDialogError() -> String? {
        guard let pid = findWiFiDialogPID() else { return nil }
        let appEl = AXUIElementCreateApplication(pid)
        let windows: [AXUIElement] = appEl.windows
        guard let window = windows.first else { return nil }

        // Read all static text elements looking for error messages
        let texts = window.findAllRecursive(role: kAXStaticTextRole)
        for text in texts {
            if let v = text.value as? String,
               v.contains("failed") || v.contains("incorrect") || v.contains("error") ||
               v.contains("timeout") || v.contains("could not") {
                return v
            }
        }
        return nil
    }

    /// Read all text from the WiFi dialog for voice feedback.
    static func readDialogStatus() -> (message: String?, error: String?, hasPasswordField: Bool) {
        guard let pid = findWiFiDialogPID() else { return (nil, nil, false) }
        let appEl = AXUIElementCreateApplication(pid)
        let windows: [AXUIElement] = appEl.windows
        guard let window = windows.first else { return (nil, nil, false) }

        var message: String?
        var error: String?
        let hasPasswordField = window.findChild(role: kAXTextFieldRole, recursive: true) != nil

        let texts = window.findAllRecursive(role: kAXStaticTextRole)
        for text in texts {
            guard let v = text.value as? String, !v.isEmpty else { continue }
            if v.contains("failed") || v.contains("incorrect") || v.contains("error") ||
               v.contains("could not") || v.contains("Failed") {
                error = v
            } else if v.contains("requires") || v.contains("network") {
                message = v
            }
        }

        return (message, error, hasPasswordField)
    }

    // MARK: - Private

    private func openWiFiPanel(app: AXUIElement) throws {
        // Open CC if needed
        if app.windows.first(where: { $0.title == "Control Center" }) == nil {
            guard let eb: AXUIElement = app.attribute("AXExtrasMenuBar") else {
                throw AirPlayError.controlCenterNotFound
            }
            for item in eb.children {
                if item.identifier == Self.ccMenuExtraIdent {
                    guard item.press() else { throw AirPlayError.cannotClickMenuItem }
                    break
                }
            }
            Thread.sleep(forTimeInterval: 1.5)
        }

        // Find and click WiFi button
        guard let window = app.windows.first(where: { $0.title == "Control Center" }) else {
            throw AirPlayError.screenMirroringMenuNotFound
        }

        guard let wifiButton = window.findChild(identifier: Self.wifiIdent, recursive: true) else {
            throw AirPlayError.screenMirroringMenuNotFound
        }

        guard wifiButton.press() else {
            throw AirPlayError.cannotClickMenuItem
        }
        NSLog("[WiFi] WiFi panel opened")
    }

    private func expandOtherNetworks(app: AXUIElement) {
        guard let scrollArea = findWiFiScrollArea(app: app) else { return }
        let triangles = scrollArea.findAllRecursive(role: kAXDisclosureTriangleRole)
        for tri in triangles {
            if tri.axDescription?.contains("Other") == true {
                if let val = tri.value as? Int, val == 0 {
                    NSLog("[WiFi] Expanding Other Networks")
                    tri.press()
                }
            }
        }
    }

    private func readNetworks(app: AXUIElement) -> [WiFiNetwork] {
        guard let scrollArea = findWiFiScrollArea(app: app) else { return [] }

        var networks: [WiFiNetwork] = []
        let checkboxes = scrollArea.findAllRecursive(role: kAXCheckBoxRole)

        for cb in checkboxes {
            guard let ident = cb.identifier, ident.hasPrefix(Self.networkPrefix),
                  let desc = cb.axDescription else { continue }
            let val = (cb.value as? Int) ?? 0
            if let net = WiFiNetwork.parse(identifier: ident, description: desc, value: val) {
                networks.append(net)
            }
        }

        return networks
    }

    private func findWiFiScrollArea(app: AXUIElement) -> AXUIElement? {
        guard let window = app.windows.first(where: { $0.title == "Control Center" }) else { return nil }
        return window.findChild(role: kAXScrollAreaRole, recursive: true)
    }

    private func closePanel(app: AXUIElement) {
        if app.windows.first(where: { $0.title == "Control Center" }) != nil {
            if let eb: AXUIElement = app.attribute("AXExtrasMenuBar") {
                for item in eb.children {
                    if item.identifier == Self.ccMenuExtraIdent {
                        item.press()
                        Thread.sleep(forTimeInterval: 0.3)
                        if app.windows.first(where: { $0.title == "Control Center" }) != nil {
                            item.press()
                        }
                        break
                    }
                }
            }
        }
    }
}
