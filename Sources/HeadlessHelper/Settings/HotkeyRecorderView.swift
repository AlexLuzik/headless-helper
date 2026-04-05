import AppKit
import SwiftUI

/// A SwiftUI wrapper around an NSView that captures a key combination.
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCombo: KeyCombo

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.keyCombo = keyCombo
        view.onKeyComboChanged = { combo in
            keyCombo = combo
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.keyCombo = keyCombo
        nsView.needsDisplay = true
    }
}

/// NSView that displays the current hotkey and enters recording mode on click.
final class HotkeyRecorderNSView: NSView {
    var keyCombo: KeyCombo = .default
    var onKeyComboChanged: ((KeyCombo) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isRecording ? .controlAccentColor.withAlphaComponent(0.2) : .controlBackgroundColor
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.fill()

        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording
            ? String(localized: "settings.hotkey_recording")
            : keyCombo.displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        str.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape cancels recording
        if event.keyCode == 0x35 {
            isRecording = false
            needsDisplay = true
            return
        }

        // Require at least one modifier
        let mods = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !mods.isEmpty else { return }

        var cgFlags: UInt64 = 0
        if mods.contains(.control) { cgFlags |= CGEventFlags.maskControl.rawValue }
        if mods.contains(.option) { cgFlags |= CGEventFlags.maskAlternate.rawValue }
        if mods.contains(.shift) { cgFlags |= CGEventFlags.maskShift.rawValue }
        if mods.contains(.command) { cgFlags |= CGEventFlags.maskCommand.rawValue }

        let combo = KeyCombo(keyCode: event.keyCode, modifiers: cgFlags)
        keyCombo = combo
        onKeyComboChanged?(combo)
        isRecording = false
        needsDisplay = true
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't handle flags-only changes; wait for a full keystroke
    }
}
