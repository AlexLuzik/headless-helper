import Foundation
import ServiceManagement
import Combine

/// Manages persistent settings via UserDefaults.
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var keyCombo: KeyCombo {
        didSet { saveKeyCombo() }
    }

    @Published var autoConnectOnLaunch: Bool {
        didSet { UserDefaults.standard.set(autoConnectOnLaunch, forKey: "autoConnectOnLaunch") }
    }

    @Published var lastDeviceID: String? {
        didSet { UserDefaults.standard.set(lastDeviceID, forKey: "lastDeviceID") }
    }

    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "appLanguage")
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    private init() {
        // Load saved values
        if let data = UserDefaults.standard.data(forKey: "keyCombo"),
           let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            self.keyCombo = combo
        } else {
            self.keyCombo = .default
        }

        self.autoConnectOnLaunch = UserDefaults.standard.bool(forKey: "autoConnectOnLaunch")
        self.lastDeviceID = UserDefaults.standard.string(forKey: "lastDeviceID")
        let savedLang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        // Migrate: if saved language is not supported, reset to English
        self.language = (savedLang == "en" || savedLang == "uk") ? savedLang : "en"
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
    }

    private func saveKeyCombo() {
        if let data = try? JSONEncoder().encode(keyCombo) {
            UserDefaults.standard.set(data, forKey: "keyCombo")
        }
    }

    private func updateLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[Settings] Failed to update login item: \(error)")
            }
        }
    }
}
