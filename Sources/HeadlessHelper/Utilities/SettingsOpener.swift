import AppKit
import SwiftUI

/// Opens settings in a standalone NSWindow — reliable for menu bar apps.
enum SettingsOpener {
    private static var settingsWindow: NSWindow?

    static func open() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(AppState.shared)
            .environmentObject(SettingsManager.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "menu.settings").replacingOccurrences(of: "…", with: "")
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        // Reset level after appearing so it doesn't stay always-on-top
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            window.level = .normal
        }

        settingsWindow = window
    }
}
