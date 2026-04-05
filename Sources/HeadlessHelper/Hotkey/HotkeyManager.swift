import CoreGraphics
import Foundation

/// Manages a global hotkey via CGEvent tap.
/// When the configured key combo is pressed, calls the onHotkey closure.
final class HotkeyManager {
    fileprivate var eventTap: CFMachPort?
    fileprivate var runLoopSource: CFRunLoopSource?
    fileprivate var keyCombo: KeyCombo
    fileprivate let onHotkey: () -> Void

    init(keyCombo: KeyCombo, onHotkey: @escaping () -> Void) {
        self.keyCombo = keyCombo
        self.onHotkey = onHotkey
    }

    func start() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // Store self in unmanaged pointer for the C callback
        let selfPtr = Unmanaged.passRetained(HotkeyManagerWrapper(manager: self)).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: selfPtr
        )

        guard let eventTap else {
            NSLog("[HotkeyManager] Failed to create event tap. Accessibility permission may be missing.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        NSLog("[HotkeyManager] Event tap started. Hotkey: %@", keyCombo.displayString)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func updateKeyCombo(_ combo: KeyCombo) {
        self.keyCombo = combo
    }

    // MARK: - Digit interception for selection/PIN mode

    var digitHandler: ((UInt16) -> Void)?
    var escapeHandler: (() -> Void)?
}

// MARK: - C callback and helpers (file-private, outside class to avoid dynamic Self capture)

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let wrapper = Unmanaged<HotkeyManagerWrapper>.fromOpaque(refcon).takeUnretainedValue()
    let manager = wrapper.manager

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        NSLog("[HotkeyManager] Event tap re-enabled (was disabled by %@)", type == .tapDisabledByTimeout ? "timeout" : "user")
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    if manager.keyCombo.matches(event: event) {
        NSLog("[HotkeyManager] Hotkey activated")
        DispatchQueue.main.async {
            manager.onHotkey()
        }
        return nil // consume the event
    }

    // When in selection/PIN mode, check for digit keys
    if manager.digitHandler != nil {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if let digit = digitForKeyCode(keyCode) {
            DispatchQueue.main.async {
                manager.digitHandler?(digit)
            }
            return nil // consume
        }
        // Escape cancels
        if keyCode == 0x35 { // Escape
            DispatchQueue.main.async {
                manager.escapeHandler?()
            }
            return nil
        }
    }

    return Unmanaged.passUnretained(event)
}

private func digitForKeyCode(_ keyCode: UInt16) -> UInt16? {
    let digitCodes: [UInt16: UInt16] = [
        0x12: 1, 0x13: 2, 0x14: 3, 0x15: 4,
        0x17: 5, 0x16: 6, 0x1A: 7, 0x1C: 8,
        0x19: 9, 0x1D: 0,
    ]
    return digitCodes[keyCode]
}

// Private wrapper class to pass self through C callback
private class HotkeyManagerWrapper {
    let manager: HotkeyManager
    init(manager: HotkeyManager) { self.manager = manager }
}
