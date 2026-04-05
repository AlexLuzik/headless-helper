import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        // AirPlay section
        Text("AirPlay")
            .font(.caption)
            .foregroundStyle(.secondary)

        if appState.devices.isEmpty {
            Text("menu.scanning", bundle: .main)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(appState.devices.enumerated()), id: \.element.id) { index, device in
                Button {
                    Task { await appState.connectToDevice(at: index) }
                } label: {
                    Text("\(index + 1). \(device.name)")
                }
                // no keyboard shortcut — selection via hotkey digit mode
            }
        }

        Divider()

        // WiFi section
        Text("Wi-Fi")
            .font(.caption)
            .foregroundStyle(.secondary)

        if appState.wifiNetworks.isEmpty {
            Button(String(localized: "wifi.scan")) {
                appState.refreshWiFiNetworks()
            }
        } else {
            ForEach(Array(appState.wifiNetworks.enumerated()), id: \.element.id) { index, network in
                Button {
                    Task { await appState.connectToWiFi(network) }
                } label: {
                    Text("\(index + 1). \(network.name)\(network.isConnected ? " ✓" : "")")
                }
            }

            Button(String(localized: "wifi.refresh")) {
                appState.refreshWiFiNetworks()
            }
        }

        Divider()

        Button(String(localized: "menu.settings")) {
            SettingsOpener.open()
        }
        .keyboardShortcut(",")

        Button(String(localized: "menu.about")) {
            AboutWindow.open()
        }

        Button(String(localized: "menu.quit")) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func wifiIcon(bars: Int) -> String {
        switch bars {
        case 3: return "wifi"
        case 2: return "wifi"
        case 1: return "wifi.exclamationmark"
        default: return "wifi.slash"
        }
    }
}
