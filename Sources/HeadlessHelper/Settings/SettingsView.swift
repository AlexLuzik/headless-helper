import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(settingsManager)
                .tabItem {
                    Label(String(localized: "settings.tab.general"), systemImage: "gear")
                }

            HotkeySettingsView()
                .environmentObject(settingsManager)
                .tabItem {
                    Label(String(localized: "settings.tab.hotkey"), systemImage: "keyboard")
                }
        }
        .frame(width: 400, height: 250)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Form {
            Toggle(String(localized: "settings.launch_at_login"), isOn: $settingsManager.launchAtLogin)

            Toggle(String(localized: "settings.auto_connect"), isOn: $settingsManager.autoConnectOnLaunch)

            Picker(String(localized: "settings.language"), selection: $settingsManager.language) {
                Text("English").tag("en")
                Text("Українська").tag("uk")
            }
            .onChange(of: settingsManager.language) { _, newValue in
                AppState.shared.voiceService.setLanguage(newValue)
            }

            if settingsManager.autoConnectOnLaunch {
                if let lastID = settingsManager.lastDeviceID {
                    HStack {
                        Text(String(localized: "settings.last_device"))
                        Spacer()
                        Text(lastID)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(String(localized: "settings.no_last_device"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

struct HotkeySettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Form {
            HStack {
                Text(String(localized: "settings.global_hotkey"))
                Spacer()
                HotkeyRecorderView(keyCombo: $settingsManager.keyCombo)
                    .frame(width: 150, height: 30)
            }

            Text(String(localized: "settings.hotkey_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
