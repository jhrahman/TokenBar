import SwiftUI
import TokenBarCore

/// Simplified marks drawn in code (not the official artwork): a radial spark for Claude, a six-petal knot for Codex.
struct ProviderLogo: View {
    let provider: Provider
    var size: CGFloat = 18

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let s = min(sz.width, sz.height)
            if provider == .claude {
                for i in 0..<12 {
                    let a = Double(i) * .pi / 6
                    let outer = s * (i % 2 == 0 ? 0.48 : 0.36)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + cos(a) * s * 0.1, y: c.y + sin(a) * s * 0.1))
                    p.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
                    ctx.stroke(p, with: .color(ember), style: StrokeStyle(lineWidth: s * 0.1, lineCap: .round))
                }
            } else {
                for i in 0..<6 {
                    let petal = Path(roundedRect: CGRect(x: -s * 0.15, y: -s * 0.46, width: s * 0.3, height: s * 0.62),
                                     cornerRadius: s * 0.15)
                    let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: Double(i) * .pi / 3)
                    ctx.stroke(petal.applying(t), with: .color(mint), lineWidth: s * 0.075)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
