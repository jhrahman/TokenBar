import SwiftUI
import AppKit

/// Dark ash glass window shared by Settings and Cost details. One window per key, reused when reopened.
@MainActor
enum GlassWindow {
    private static var windows: [String: NSWindow] = [:]

    static func show<Content: View>(key: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if windows[key] == nil {
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)

            let ash = NSColor(red: 0x1C / 255, green: 0x1D / 255, blue: 0x21 / 255, alpha: 1)
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            let glass = NSVisualEffectView()
            glass.material = .hudWindow
            glass.blendingMode = .behindWindow
            glass.state = .active
            let tint = NSView()
            tint.wantsLayer = true
            tint.layer?.backgroundColor = ash.withAlphaComponent(reduce ? 1 : 0.6).cgColor
            let host = NSHostingView(rootView: content())
            for v in [tint, host] {
                v.translatesAutoresizingMaskIntoConstraints = false
                glass.addSubview(v)
                NSLayoutConstraint.activate([
                    v.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                    v.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                    v.topAnchor.constraint(equalTo: glass.topAnchor),
                    v.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
                ])
            }
            w.contentView = glass
            w.center()
            windows[key] = w
        }
        NSApp.activate(ignoringOtherApps: true)
        windows[key]?.makeKeyAndOrderFront(nil)
    }
}
