import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyManager: HotkeyManager?
    private var wifiHotkeyManager: HotkeyManager?
    private var cancellables = Set<AnyCancellable>()

    private var accessibilityTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appState = AppState.shared
        let settings = SettingsManager.shared

        appState.discoveryService.startBrowsing()
        appState.voiceService.setLanguage(settings.language)

        if AXIsProcessTrusted() {
            startHotkeys(appState: appState, settings: settings)
        } else {
            // Show system prompt for accessibility
            Permissions.ensureAccessibility()
            NSLog("[App] Waiting for Accessibility permission...")

            // Poll every 2 seconds until permission is granted, then relaunch
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                if AXIsProcessTrusted() {
                    NSLog("[App] Accessibility granted — relaunching to activate hotkeys")
                    self?.accessibilityTimer?.invalidate()
                    self?.accessibilityTimer = nil

                    let bundlePath = Bundle.main.bundlePath
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                    task.arguments = ["-n", bundlePath, "--args", "--relaunched"]
                    try? task.run()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        NSApp.terminate(nil)
                    }
                }
            }
        }

        // Wire selection mode
        NotificationCenter.default.publisher(for: .selectionModeActivated)
            .compactMap { $0.object as? SelectionModeConfig }
            .sink { [weak self] config in
                self?.hotkeyManager?.digitHandler = config.onDigit
                self?.hotkeyManager?.escapeHandler = config.onEscape
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .selectionModeDeactivated)
            .sink { [weak self] _ in
                self?.hotkeyManager?.digitHandler = nil
                self?.hotkeyManager?.escapeHandler = nil
            }
            .store(in: &cancellables)

        settings.$keyCombo
            .dropFirst()
            .sink { [weak self] combo in
                self?.hotkeyManager?.updateKeyCombo(combo)
            }
            .store(in: &cancellables)

        settings.$language
            .dropFirst()
            .sink { newLang in
                appState.voiceService.setLanguage(newLang)
                UserDefaults.standard.set([newLang], forKey: "AppleLanguages")
                // Relaunch app to apply new language
                let bundlePath = Bundle.main.bundlePath
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = ["-n", bundlePath, "--args", "--relaunched"]
                try? task.run()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.terminate(nil)
                }
            }
            .store(in: &cancellables)

        if settings.autoConnectOnLaunch, let lastID = settings.lastDeviceID {
            appState.scheduleAutoConnect(deviceID: lastID)
        }
    }

    private func startHotkeys(appState: AppState, settings: SettingsManager) {
        hotkeyManager = HotkeyManager(keyCombo: settings.keyCombo) {
            DispatchQueue.main.async { appState.handleHotkeyPressed() }
        }
        hotkeyManager?.start()

        let wifiCombo = KeyCombo(keyCode: 0x0D, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue)
        wifiHotkeyManager = HotkeyManager(keyCombo: wifiCombo) {
            DispatchQueue.main.async { appState.handleWiFiHotkeyPressed() }
        }
        wifiHotkeyManager?.start()
        NSLog("[App] Hotkeys started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.stop()
        wifiHotkeyManager?.stop()
        AppState.shared.discoveryService.stopBrowsing()
        AppState.shared.voiceService.stopSpeaking()
    }
}
