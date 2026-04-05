import Foundation

/// Matches AX identifiers from Control Center checkboxes to Bonjour-discovered device names.
/// Port of the MAC-normalization logic from ListAirplayDevices.sh.
enum DeviceMatcher {
    /// Given a list of AX identifiers and a discovery service, produce matched AirPlayDevice entries.
    /// AX identifiers look like: "screen-mirroring-device-AirPlay:AA:BB:CC:DD:EE:FF"
    static func match(
        axIdentifiers: [String],
        discoveryService: DeviceDiscoveryService
    ) -> [AirPlayDevice] {
        axIdentifiers.compactMap { axId in
            guard let mac = AirPlayDevice.macFromAXIdentifier(axId) else { return nil }
            let name = discoveryService.nameForMac(mac) ?? String(localized: "device.unknown \(axId)")
            return AirPlayDevice(id: axId, name: name, macAddress: mac)
        }
    }
}
