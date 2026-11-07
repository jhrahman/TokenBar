import AppKit
import TokenBarCore

enum MenuBarIcon {
    /// Template image drawn from what's enabled: one bar per provider, filled by 5h usage.
    /// Nothing enabled -> two dimmed, empty bars.
    @MainActor static func image(for store: UsageStore) -> NSImage {
        var bars: [Double?] = store.enabled.map { p in
            if case .ok(let s) = store.states[p] ?? .off { return (s.fiveHour?.percent ?? 0) / 100 }
            return 0
        }
        let dim = bars.isEmpty
        if dim { bars = [0, 0] }
        let img = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { rect in
            let h: CGFloat = 5, gap: CGFloat = 3
            let total = CGFloat(bars.count) * h + CGFloat(bars.count - 1) * gap
            var y = (rect.height + total) / 2 - h
            for fill in bars {
                let track = NSRect(x: 1, y: y, width: rect.width - 2, height: h)
                NSColor.black.withAlphaComponent(dim ? 0.2 : 0.35).setFill()
                NSBezierPath(roundedRect: track, xRadius: h / 2, yRadius: h / 2).fill()
                let f = max(0, min(1, fill ?? 0))
                if f > 0 {
                    var filled = track
                    filled.size.width = max(h, track.width * f)
                    NSColor.black.setFill()
                    NSBezierPath(roundedRect: filled, xRadius: h / 2, yRadius: h / 2).fill()
                }
                y -= h + gap
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
