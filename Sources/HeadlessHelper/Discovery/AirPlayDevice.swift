import Foundation

struct AirPlayDevice: Identifiable, Equatable, Codable {
    /// AX identifier from Control Center, e.g. "screen-mirroring-device-AirPlay:AA:BB:CC:DD:EE:FF"
    let id: String
    /// Human-readable name from Bonjour, e.g. "Living Room TV"
    let name: String
    /// Normalized 12-char hex MAC address
    let macAddress: String

    /// Extract MAC portion from an AX identifier like "screen-mirroring-device-AirPlay:AA:BB:CC:DD:EE:FF"
    static func macFromAXIdentifier(_ axId: String) -> String? {
        guard let range = axId.range(of: "AirPlay:") else { return nil }
        let raw = String(axId[range.upperBound...])
        return normalizeMac(raw)
    }

    /// Normalize a MAC string: strip colons/dashes, lowercase, take last 12 hex chars
    static func normalizeMac(_ input: String) -> String? {
        let cleaned = input
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        guard cleaned.count >= 12,
              cleaned.suffix(12).allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return String(cleaned.suffix(12))
    }
}
