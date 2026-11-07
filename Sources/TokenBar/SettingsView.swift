import SwiftUI
import AppKit
import ServiceManagement
import TokenBarCore

enum SettingsWindow {
    @MainActor static func show() {
        GlassWindow.show(key: "settings", size: NSSize(width: 400, height: 480)) { SettingsView(store: .shared) }
    }
}

struct Toast: Equatable {
    var text: String
    var isError = false
}

let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var revertingLogin = false
    @State private var toast: Toast?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("TokenBar").font(.title2.bold()).padding(.top, 24)

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { on in
                    if revertingLogin { revertingLogin = false; return }
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        show(on ? "TokenBar will launch at login" : "TokenBar won\u{2019}t launch at login")
                    } catch {
                        revertingLogin = true
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                        show("Couldn\u{2019}t change launch at login", error: true)
                    }
                }

            providerSection(.claude, isOn: $store.monitorClaude, detected: ClaudeSource.isInstalled)
                .onChange(of: store.monitorClaude) { show("Claude monitoring \($0 ? "on" : "off")") }
            HStack {
                Text("Claude plan renews on day")
                Spacer()
                Stepper(value: $store.renewalDay, in: 1...31) { Text("\(store.renewalDay)").monospacedDigit() }
            }
            .onChange(of: store.renewalDay) { show("Billing cycle starts on day \($0)") }

            providerSection(.codex, isOn: $store.monitorCodex, detected: CodexSource.isInstalled)
                .onChange(of: store.monitorCodex) { show("Codex monitoring \($0 ? "on" : "off")") }

            Picker("Refresh every", selection: $store.intervalMinutes) {
                Text("5 min").tag(5); Text("15 min").tag(15); Text("30 min").tag(30)
            }
            .pickerStyle(.segmented)
            .onChange(of: store.intervalMinutes) { show("Refreshing every \($0) min") }

            Spacer()
            Text("Changes save automatically.  \u{00B7}  TokenBar v\(appVersion)").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? Color.red : mint)
                    Text(toast.text).font(.callout.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .padding(.bottom, 44)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Slide-up confirmation that fades after ~2s; a newer change replaces it.
    func show(_ text: String, error: Bool = false) {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = Toast(text: text, isError: error) }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { toast = nil }
        }
    }

    func providerSection(_ p: Provider, isOn: Binding<Bool>, detected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Monitor \(p.displayName)", isOn: isOn)
            Group {
                Text("Source: Local app (\(detected ? "login found" : "login not found"))")
                Text("Browser sign-in: coming soon")
            }
            .font(.caption).foregroundStyle(.secondary)
            .opacity(isOn.wrappedValue ? 1 : 0.4)
        }
    }
}
