import AppKit
import ApplicationServices

enum Permissions {
    static func ensureAccessibility() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
