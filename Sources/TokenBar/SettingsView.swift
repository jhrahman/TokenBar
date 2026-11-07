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
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude plan purchase or renewal date")
                DateFields(date: $store.purchaseDate)
                Picker("Billing", selection: $store.yearlyPlan) {
                    Text("Monthly").tag(false); Text("Yearly").tag(true)
                }
                .pickerStyle(.segmented)
                Text("Next renewal: \(CostMath.nextRenewal(purchase: store.purchaseDate, yearly: store.yearlyPlan, now: Date()).formatted(date: .abbreviated, time: .omitted)). Pick the purchase date, any past payment date, or the upcoming renewal date.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)   // wrap instead of truncating with "…"
            }
            .onChange(of: store.purchaseDate) { _ in show("Claude renewal date updated") }
            .onChange(of: store.yearlyPlan) { show("Claude plan billed \($0 ? "yearly" : "monthly")") }

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
        .frame(width: 400, height: 480, alignment: .topLeading)   // fixed size: the window must not grow with its content
        .contentShape(Rectangle())
        .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }   // clicking empty space leaves the text fields
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

/// Plain DD / MM / YYYY text fields. A valid date is saved as you type; an invalid one is flagged and not saved.
struct DateFields: View {
    @Binding var date: Date
    @State private var day = ""
    @State private var month = ""
    @State private var year = ""
    @FocusState private var focus: Field?
    private enum Field { case day, month, year }
    private let cal = Calendar.current

    /// nil unless all three fields form a real calendar date.
    private var parsed: Date? {
        guard let d = Int(day), let m = Int(month), let y = Int(year),
              (1...12).contains(m), (2000...2100).contains(y), year.count == 4,
              let first = cal.date(from: DateComponents(year: y, month: m, day: 1)),
              (1...cal.range(of: .day, in: .month, for: first)!.count).contains(d) else { return nil }
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))   // midday keeps the day stable across DST
    }
    private var invalid: Bool { !(day.isEmpty && month.isEmpty && year.isEmpty) && parsed == nil }

    private func load() {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        day = String(c.day ?? 1); month = String(c.month ?? 1); year = String(c.year ?? 2026)
    }
    private func digits(_ s: inout String, max: Int) { s = String(s.filter(\.isNumber).prefix(max)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("DD", text: $day).frame(width: 52).focused($focus, equals: .day)
                Text("/").foregroundStyle(.secondary)
                TextField("MM", text: $month).frame(width: 52).focused($focus, equals: .month)
                Text("/").foregroundStyle(.secondary)
                TextField("YYYY", text: $year).frame(width: 72).focused($focus, equals: .year)
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            HStack(spacing: 8) {
                Text("Day").frame(width: 52)
                Spacer().frame(width: 12)
                Text("Month").frame(width: 52)
                Spacer().frame(width: 12)
                Text("Year").frame(width: 72)
            }
            .font(.caption2).foregroundStyle(.secondary)
            if invalid { Text("Enter a real date, e.g. 02 / 11 / 2026").font(.caption).foregroundStyle(.red) }
        }
        .onAppear(perform: load)
        .onChange(of: day) { _ in digits(&day, max: 2); if let p = parsed { date = p } }
        .onChange(of: month) { _ in digits(&month, max: 2); if let p = parsed { date = p } }
        .onChange(of: year) { _ in digits(&year, max: 4); if let p = parsed { date = p } }
        .onChange(of: focus) { f in if f == nil, invalid { load() } }   // leaving the fields with a bad date restores the saved one
    }
}
