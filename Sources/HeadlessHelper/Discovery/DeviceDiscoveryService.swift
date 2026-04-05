import Foundation
import Combine

/// Discovers AirPlay devices via Bonjour (_airplay._tcp) using NetServiceBrowser.
/// Filters to only show display-capable devices (Apple TV, etc.)
/// Publishes discovered devices with their names and MAC addresses.
final class DeviceDiscoveryService: NSObject, ObservableObject {
    @Published var devices: [AirPlayDevice] = []

    private var browser: NetServiceBrowser?
    private var pendingServices: Set<NetService> = []
    private var resolvedDevices: [String: ResolvedDevice] = [:]

    struct ResolvedDevice {
        let name: String
        let macAddress: String
        let model: String?
        let supportsVideo: Bool
    }

    private var refreshTimer: Timer?

    func startBrowsing() {
        restartBrowser()

        // Periodically restart browser to pick up devices that were missed
        DispatchQueue.main.async { [weak self] in
            self?.refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                NSLog("[Discovery] Periodic refresh")
                self?.restartBrowser()
            }
        }
    }

    func stopBrowsing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        browser?.stop()
        browser = nil
        pendingServices.removeAll()
    }

    private func restartBrowser() {
        browser?.stop()
        pendingServices.removeAll()
        let newBrowser = NetServiceBrowser()
        newBrowser.delegate = self
        newBrowser.searchForServices(ofType: "_airplay._tcp.", inDomain: "local.")
        self.browser = newBrowser
        NSLog("[Discovery] Started browsing for _airplay._tcp")
    }

    /// Look up a device name by its MAC address
    func nameForMac(_ mac: String) -> String? {
        resolvedDevices[mac]?.name
    }

    private func publishDevices() {
        let airplayDevices = resolvedDevices.values
            .filter { $0.supportsVideo }
            .map { AirPlayDevice(id: $0.macAddress, name: $0.name, macAddress: $0.macAddress) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async { [weak self] in
            self?.devices = airplayDevices
        }
    }

    fileprivate func processResolvedService(_ service: NetService) {
        guard let txtData = service.txtRecordData() else {
            NSLog("[Discovery] No TXT record for '%@'", service.name)
            return
        }

        let txtDict = NetService.dictionary(fromTXTRecord: txtData)

        let model = txtDict["model"].flatMap { String(data: $0, encoding: .utf8) }
        let deviceID = txtDict["deviceid"].flatMap { String(data: $0, encoding: .utf8) }
        let psi = txtDict["psi"].flatMap { String(data: $0, encoding: .utf8) }

        NSLog("[Discovery] Resolved '%@': model=%@, deviceid=%@", service.name, model ?? "nil", deviceID ?? "nil")

        // Determine if this device supports video (has a display)
        let supportsVideo = Self.isDisplayDevice(model: model)

        // Get MAC address
        var mac: String?
        if let did = deviceID {
            mac = AirPlayDevice.normalizeMac(did)
        }
        if mac == nil, let p = psi {
            mac = AirPlayDevice.normalizeMac(p)
        }

        let deviceKey = mac ?? service.name.lowercased().replacingOccurrences(of: " ", with: "-")

        resolvedDevices[deviceKey] = ResolvedDevice(
            name: service.name,
            macAddress: mac ?? deviceKey,
            model: model,
            supportsVideo: supportsVideo
        )

        publishDevices()
    }

    /// Check if a device model supports video output (has a display).
    /// Known model prefixes:
    /// - AppleTV*        → Apple TV (has display output)
    /// - AudioAccessory* → HomePod / HomePod mini (audio only)
    /// - MacBookPro*, iMac*, Macmini*, MacPro*, Mac* → Mac (AirPlay receiver, usually not a target)
    private static func isDisplayDevice(model: String?) -> Bool {
        guard let model else { return true } // If unknown, include it
        if model.hasPrefix("AppleTV") { return true }
        if model.hasPrefix("AudioAccessory") { return false }
        // Filter out Macs - they're AirPlay receivers but not typical mirror targets
        if model.hasPrefix("Mac") || model.hasPrefix("iMac") { return false }
        // Unknown model - include it (could be a smart TV)
        return true
    }
}

// MARK: - NetServiceBrowserDelegate

extension DeviceDiscoveryService: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        NSLog("[Discovery] Found service: '%@'", service.name)
        pendingServices.insert(service)
        service.delegate = self
        service.resolve(withTimeout: 10)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        NSLog("[Discovery] Removed service: '%@'", service.name)
        pendingServices.remove(service)
        // Remove from resolved and republish
        resolvedDevices = resolvedDevices.filter { $0.value.name != service.name }
        publishDevices()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        NSLog("[Discovery] Search failed: %@", errorDict.description)
        // Retry after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.startBrowsing()
        }
    }
}

// MARK: - NetServiceDelegate

extension DeviceDiscoveryService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        processResolvedService(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        NSLog("[Discovery] Failed to resolve '%@': %@", sender.name, errorDict.description)
    }

    func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        processResolvedService(sender)
    }
}
