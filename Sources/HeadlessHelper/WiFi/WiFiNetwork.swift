import Foundation

struct WiFiNetwork: Identifiable, Equatable {
    let id: String        // AX identifier e.g. "wifi-network-Luzik"
    let name: String      // SSID
    let isSecure: Bool
    let signalBars: Int   // 1-3
    let isConnected: Bool
    let isHotspot: Bool

    /// Parse from AX description like "Luzik, secure network, 3 bars"
    static func parse(identifier: String, description: String, value: Int) -> WiFiNetwork? {
        let parts = description.components(separatedBy: ", ")
        guard let name = parts.first, !name.isEmpty else { return nil }

        let isSecure = parts.contains { $0.contains("secure") }
        let isHotspot = parts.contains { $0.contains("Hotspot") || $0.contains("hotspot") }
        let bars = parts.compactMap { part -> Int? in
            if part.contains("bar") {
                return Int(part.components(separatedBy: " ").first ?? "")
            }
            return nil
        }.first ?? 0

        return WiFiNetwork(
            id: identifier,
            name: name,
            isSecure: isSecure,
            signalBars: bars,
            isConnected: value == 1,
            isHotspot: isHotspot
        )
    }
}
