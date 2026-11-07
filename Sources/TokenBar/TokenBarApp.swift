import SwiftUI
import TokenBarCore

let ember = Color(red: 0xE8 / 255, green: 0x60 / 255, blue: 0x3C / 255)
let mint = Color(red: 0x2F / 255, green: 0xBF / 255, blue: 0x9F / 255)

@main
struct TokenBarApp: App {
    @StateObject private var store = UsageStore.shared

    init() {
        NSApp?.setActivationPolicy(.accessory)   // no Dock icon (build.sh also sets LSUIElement)
        UsageStore.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: store))
        }
        .menuBarExtraStyle(.window)
    }
}

struct PopoverView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.enabled.isEmpty {
                Text("Nothing to monitor. Turn on Claude or Codex in Settings.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.enabled) { ProviderRow(provider: $0, state: store.states[$0] ?? .off, note: store.notes[$0], cost: $0 == .claude ? store.costReport : nil) }
            Divider()
            HStack {
                Button("Settings…") { SettingsWindow.show() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { store.refresh() }
    }
}

struct ProviderRow: View {
    let provider: Provider
    let state: ProviderState
    var note: String?
    var cost: CostReport?
    var tint: Color { provider == .claude ? ember : mint }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                ProviderLogo(provider: provider, size: 20)
                Text(provider.displayName).font(.headline).foregroundStyle(tint)
            }
            switch state {
            case .off, .loading:
                Text("Loading…").foregroundStyle(.secondary)
            case .failed(let msg):
                Text(msg).foregroundStyle(.secondary)
            case .ok(let snap):
                // Recomputed every minute so the countdown stays fresh without any network call.
                TimelineView(.periodic(from: .now, by: 60)) { ctx in
                    VStack(alignment: .leading, spacing: 8) {
                        if let w = snap.fiveHour {
                            line("5h", w, ResetText.fiveHour(resetsAt: w.resetsAt, now: ctx.date), dollars: cost?.fiveHour)
                        }
                        if let w = snap.weekly {
                            line("Weekly", w, ResetText.weekly(resetsAt: w.resetsAt, now: ctx.date), dollars: cost?.weekly)
                        }
                    }
                }
            }
            if let cost {
                Button { CostWindow.show() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                        Text("This cycle on this Mac: \(Money.format(cost.cycle))")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Open cost details")
            }
            if let note { Text(note).font(.caption).foregroundStyle(.orange) }
        }
    }

    func line(_ name: String, _ w: UsageWindow, _ reset: String, dollars: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(name) · \(Int(w.percent.rounded()))% · \(reset)").font(.callout)
            ProgressView(value: min(max(w.percent, 0), 100), total: 100).tint(tint)
            if let dollars { Text("\u{2248} \(Money.format(dollars)) on this Mac (API value)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
