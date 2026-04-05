import AppKit
import ApplicationServices
import CoreGraphics

/// Handles PIN entry for AirPlay device authentication.
/// Finds the system PIN dialog (owned by AirPlayUIAgent) via Accessibility API,
/// focuses the text field, sets the PIN, and confirms with Enter.
final class PINHandler {

    private static let airplayUIAgentBundleID = "com.apple.AirPlayUIAgent"

    /// Enter a 4-digit PIN into the AirPlay PIN dialog.
    func enterPIN(digits: [UInt16]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let pin = digits.map { String($0) }.joined()
                NSLog("[PIN] Entering PIN: %@", pin)

                guard let runningApp = NSRunningApplication.runningApplications(
                    withBundleIdentifier: Self.airplayUIAgentBundleID
                ).first else {
                    NSLog("[PIN] AirPlayUIAgent not running")
                    continuation.resume(throwing: AirPlayError.pinEntryFailed)
                    return
                }

                let pid = runningApp.processIdentifier
                let appEl = AXUIElementCreateApplication(pid)

                // Activate AirPlayUIAgent to bring its window to front
                runningApp.activate()
                Thread.sleep(forTimeInterval: 0.5)

                let windows: [AXUIElement] = appEl.windows
                guard let window = windows.first else {
                    NSLog("[PIN] No PIN dialog window found")
                    continuation.resume(throwing: AirPlayError.pinEntryFailed)
                    return
                }

                // Find the text field
                guard let textField = window.findChild(role: kAXTextFieldRole, recursive: true) else {
                    NSLog("[PIN] No text field in PIN dialog")
                    continuation.resume(throwing: AirPlayError.pinEntryFailed)
                    return
                }

                // Focus the text field
                AXUIElementSetAttributeValue(textField, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                Thread.sleep(forTimeInterval: 0.3)

                // Set PIN value via AX
                AXUIElementSetAttributeValue(textField, kAXValueAttribute as CFString, pin as CFTypeRef)
                NSLog("[PIN] Value set via AX")
                Thread.sleep(forTimeInterval: 0.3)

                // Send Enter key targeted at AirPlayUIAgent process
                Self.sendKey(keyCode: 0x24, toPID: pid) // Return
                NSLog("[PIN] Enter key sent to pid %d", pid)

                Thread.sleep(forTimeInterval: 2.0)
                continuation.resume()
            }
        }
    }

    /// Send a key event targeted at a specific process.
    private static func sendKey(keyCode: CGKeyCode, toPID pid: pid_t) {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }

        keyDown.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        keyUp.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))

        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        keyUp.post(tap: .cghidEventTap)
    }
}
