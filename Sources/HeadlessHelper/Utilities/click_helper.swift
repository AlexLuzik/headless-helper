import CoreGraphics
import Foundation

// Standalone click helper — sends a mouse click at given coordinates.
// Used as a child process because the ScreenCaptureKit picker dialog
// ignores CGEvents from the parent process but accepts them from a separate process.

guard CommandLine.arguments.count >= 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]) else {
    exit(1)
}

let point = CGPoint(x: x, y: y)

CGWarpMouseCursorPosition(point)
CGAssociateMouseAndMouseCursorPosition(1)
Thread.sleep(forTimeInterval: 0.3)

let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                   mouseCursorPosition: point, mouseButton: .left)
let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                 mouseCursorPosition: point, mouseButton: .left)
down?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.05)
up?.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.1)
