import CoreGraphics
import Foundation

/// Represents a keyboard shortcut (modifier flags + key code).
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64  // CGEventFlags.rawValue

    /// Default: Control + Option + M
    static let `default` = KeyCombo(keyCode: 0x2E, modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue) // 0x2E = M

    var eventFlags: CGEventFlags {
        CGEventFlags(rawValue: modifiers)
    }

    /// Human-readable display string like "⌥F1"
    var displayString: String {
        var parts: [String] = []
        let flags = eventFlags
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    func matches(event: CGEvent) -> Bool {
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == keyCode else { return false }

        // Compare only modifier keys, ignoring device-dependent flags
        let relevantMask: UInt64 = CGEventFlags.maskCommand.rawValue
            | CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskControl.rawValue

        let eventMods = event.flags.rawValue & relevantMask
        let comboMods = modifiers & relevantMask
        return eventMods == comboMods
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D",
            0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H",
            0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
            0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
            0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T",
            0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
            0x10: "Y", 0x06: "Z",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
            0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8",
            0x19: "9", 0x1D: "0",
            0x31: "Space", 0x24: "Return", 0x30: "Tab",
            0x33: "Delete", 0x35: "Escape",
        ]
        return names[keyCode] ?? "Key(\(keyCode))"
    }
}
