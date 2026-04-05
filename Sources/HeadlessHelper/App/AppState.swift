import AppKit
import Combine
import Foundation

enum ConnectionStatus: Equatable {
    case idle
    case connecting(String)
    case connected
    case error(String)
    case waitingForPIN
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var devices: [AirPlayDevice] = []
    @Published var wifiNetworks: [WiFiNetwork] = []
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var isSelectionModeActive = false

    let discoveryService = DeviceDiscoveryService()
    let wifiService = WiFiService()
    let voiceService = VoiceFeedbackService()
    let connector = AirPlayConnector()
    let pinHandler = PINHandler()
    private let selectionMode = KeyboardSelectionMode()

    private var cancellables = Set<AnyCancellable>()
    private var autoConnectTask: Task<Void, Never>?

    private init() {
        discoveryService.$devices
            .receive(on: RunLoop.main)
            .assign(to: &$devices)
    }

    func handleHotkeyPressed() {
        guard !isSelectionModeActive else { return }

        if devices.isEmpty {
            voiceService.speak(String(localized: "voice.no_devices"))
            return
        }

        isSelectionModeActive = true
        voiceService.speakDeviceList(devices)

        selectionMode.activate(deviceCount: devices.count) { [weak self] selection in
            guard let self else { return }
            Task { @MainActor in
                self.isSelectionModeActive = false
                switch selection {
                case .device(let index):
                    await self.connectToDevice(at: index)
                case .cancelled:
                    self.voiceService.stopSpeaking()
                case .timeout:
                    self.voiceService.speak(String(localized: "voice.timeout"))
                }
            }
        }
    }

    func connectToDevice(at index: Int) async {
        guard index >= 0, index < devices.count else { return }
        let device = devices[index]
        await connectToDevice(device)
    }

    func connectToDevice(_ device: AirPlayDevice) async {
        connectionStatus = .connecting(device.name)
        voiceService.speak(String(localized: "voice.connecting \(device.name)"))

        do {
            let result = try await connector.connect(device: device)

            switch result {
            case .alreadyConnected:
                connectionStatus = .connected
                voiceService.speak(String(localized: "voice.already_connected \(device.name)"))

            case .connected:
                connectionStatus = .connected
                voiceService.speak(String(localized: "voice.connected"))
                SettingsManager.shared.lastDeviceID = device.id

            case .needsPIN:
                connectionStatus = .waitingForPIN
                voiceService.speak(String(localized: "voice.enter_pin"))

                // Wait for PIN dialog to close
                NSLog("[PIN] Waiting for PIN dialog to close...")
                await Self.waitForPINDialogClose()

                // Verify connection via CC → SM
                NSLog("[PIN] Dialog closed, verifying connection...")
                let isConnected = await connector.ensureMirroring()

                if isConnected {
                    connectionStatus = .connected
                    voiceService.speak(String(localized: "voice.connected"))
                    SettingsManager.shared.lastDeviceID = device.id
                } else {
                    connectionStatus = .idle
                    voiceService.speak(String(localized: "voice.cancelled"))
                }
            }
        } catch {
            connectionStatus = .error(error.localizedDescription)
            voiceService.speak(String(localized: "voice.connection_error"))
        }
    }

    /// Show a PIN input dialog and return the entered 4-digit code.
    /// Poll until the AirPlay PIN dialog closes (user entered PIN or cancelled).
    /// Returns true if PIN was accepted (dialog closed without Cancel).
    private static func waitForPINDialogClose() async -> Bool {
        for _ in 0..<120 { // Wait up to 60 seconds
            try? await Task.sleep(for: .milliseconds(500))

            guard let app = AXUIElement.appElement(bundleIdentifier: "com.apple.AirPlayUIAgent") else {
                return true // Process gone = PIN accepted
            }
            let windows: [AXUIElement] = app.windows
            if windows.isEmpty {
                return true // Dialog closed = PIN accepted
            }
        }
        return false // Timeout
    }

    // MARK: - WiFi

    func handleWiFiHotkeyPressed() {
        guard !isSelectionModeActive else { return }

        voiceService.speak(String(localized: "wifi.scanning"))

        Task {
            let networks = await Task.detached { self.wifiService.scanNetworks() }.value
            self.wifiNetworks = networks

            if networks.isEmpty {
                voiceService.speak(String(localized: "wifi.no_networks"))
                return
            }

            isSelectionModeActive = true
            voiceService.speakWiFiList(networks)

            selectionMode.activate(deviceCount: networks.count) { [weak self] selection in
                guard let self else { return }
                Task { @MainActor in
                    self.isSelectionModeActive = false
                    switch selection {
                    case .device(let index):
                        guard index >= 0, index < self.wifiNetworks.count else { return }
                        await self.connectToWiFi(self.wifiNetworks[index])
                    case .cancelled:
                        self.voiceService.stopSpeaking()
                    case .timeout:
                        self.voiceService.speak(String(localized: "voice.timeout"))
                    }
                }
            }
        }
    }

    func connectToWiFi(_ network: WiFiNetwork) async {
        if network.isConnected {
            voiceService.speak(String(localized: "wifi.already_connected \(network.name)"))
            return
        }

        voiceService.speak(String(localized: "wifi.connecting \(network.name)"))

        let result = await Task.detached { self.wifiService.connect(network: network) }.value

        switch result {
        case .connected:
            voiceService.speak(String(localized: "wifi.connected \(network.name)"))

        case .needsPassword:
            voiceService.speak(String(localized: "wifi.enter_password"))
            let passwordResult = await Task.detached {
                self.wifiService.waitForPasswordResult(expectedSSID: network.name)
            }.value
            switch passwordResult {
            case .connected:
                voiceService.speak(String(localized: "wifi.connected \(network.name)"))
            case .error(let msg):
                voiceService.speak(msg)
            case .cancelled:
                voiceService.speak(String(localized: "voice.cancelled"))
            }

        case .failed:
            voiceService.speak(String(localized: "voice.connection_error"))
        }
    }

    func refreshWiFiNetworks() {
        Task {
            let networks = await Task.detached { self.wifiService.scanNetworks() }.value
            self.wifiNetworks = networks
        }
    }

    func scheduleAutoConnect(deviceID: String) {
        autoConnectTask = Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                if let device = devices.first(where: { $0.id == deviceID }) {
                    await connectToDevice(device)
                    return
                }
            }
            voiceService.speak(String(localized: "voice.auto_connect_failed"))
        }
    }
}
