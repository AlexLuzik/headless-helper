import AppKit
import SwiftUI

enum AboutWindow {
    private static var window: NSWindow?

    static func open() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "About Headless Helper"
        w.contentView = NSHostingView(rootView: aboutView)
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            w.level = .normal
        }

        window = w
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)
            }

            Text("Headless Helper")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 6) {
                Text("Developed by Oleksandr Luzin")
                    .font(.callout)

                Link("luzin.cc", destination: URL(string: "https://luzin.cc")!)
                    .font(.callout)

                Link("GitHub", destination: URL(string: "https://github.com/AlexLuzik/headless-helper")!)
                    .font(.callout)
            }

            Divider()

            VStack(spacing: 4) {
                Text("Inspired by")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link("headless-airplay-screen-mirror", destination: URL(string: "https://github.com/TylerBoni/headless-airplay-screen-mirror")!)
                    .font(.caption)
            }

            Spacer()

            Text("\u{00A9} 2026 Oleksandr Luzin. MIT License.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 360, height: 340)
    }
}
