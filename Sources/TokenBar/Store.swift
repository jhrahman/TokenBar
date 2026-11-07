import Foundation
import SwiftUI
import TokenBarCore

enum ProviderState {
    case off, loading, ok(UsageSnapshot), failed(String)
}

extension Provider: Identifiable { public var id: String { rawValue } }

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var states: [Provider: ProviderState] = [.claude: .off, .codex: .off]
    @Published var monitorClaude: Bool { didSet { save("monitorClaude", monitorClaude); sync() } }
    @Published var monitorCodex: Bool { didSet { save("monitorCodex", monitorCodex); sync() } }
    /// When the Claude plan was first bought (or any past renewal date). Renewals are counted forward from it.
    @Published var purchaseDate: Date { didSet { save("purchaseDate", purchaseDate); updateCosts() } }
    @Published var yearlyPlan: Bool { didSet { save("yearlyPlan", yearlyPlan) } }
    /// Day of month the monthly usage cycle starts on (the purchase day).
    var renewalDay: Int { Calendar.current.component(.day, from: purchaseDate) }
    /// Estimated $ (API list prices) from Claude Code's local logs; nil until first computed.
    @Published private(set) var costReport: CostReport?
    private let scanner = LogScanner()
    @Published var intervalMinutes: Int { didSet { save("intervalMinutes", intervalMinutes); restartTimer() } }

    private var timer: Timer?
    private var inFlight: Set<Provider> = []
    private var lastFetch: [Provider: Date] = [:]
    private var backoffUntil: [Provider: Date] = [:]
    private var failStreak: [Provider: Int] = [:]
    /// Shown under a provider when the latest refresh failed but older numbers are still displayed.
    @Published private(set) var notes: [Provider: String] = [:]
    private let d = UserDefaults.standard

    var enabled: [Provider] { providersToPoll(monitorClaude: monitorClaude, monitorCodex: monitorCodex) }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: "monitorClaude") == nil {
            // First run: enable what's detected locally; if nothing is, enable both so the user sees "Not logged in".
            let c = ClaudeSource.isInstalled, x = CodexSource.isInstalled
            let none = !c && !x
            d.set(c || none, forKey: "monitorClaude")
            d.set(x || none, forKey: "monitorCodex")
        }
        monitorClaude = d.bool(forKey: "monitorClaude")
        monitorCodex = d.bool(forKey: "monitorCodex")
        if let p = d.object(forKey: "purchaseDate") as? Date { purchaseDate = p }
        else {
            // Migrate the old "renews on day N" setting into a purchase date.
            let rd = d.integer(forKey: "renewalDay")
            purchaseDate = CostMath.cycleRange(renewalDay: (1...31).contains(rd) ? rd : 1, now: Date()).start
        }
        yearlyPlan = d.bool(forKey: "yearlyPlan")
        let i = d.integer(forKey: "intervalMinutes")
        intervalMinutes = [5, 15, 30].contains(i) ? i : 5   // 1 min was dropped: the usage endpoints rate-limit
    }

    func start() {
        loadCached()
        sync(); updateCosts()
        refresh(force: true)
    }

    // MARK: last known values survive restarts, so a rate limit or offline start still shows numbers
    private func cacheKey(_ p: Provider) -> String { "lastSnapshot.\(p.rawValue)" }

    private func saveCached(_ p: Provider, _ s: UsageSnapshot) {
        if let data = try? JSONEncoder().encode(s) { d.set(data, forKey: cacheKey(p)); d.set(Date(), forKey: cacheKey(p) + ".at") }
    }

    private func loadCached() {
        for p in Provider.allCases { backoffUntil[p] = d.object(forKey: "backoff.\(p.rawValue)") as? Date }
        for p in enabled {
            guard let data = d.data(forKey: cacheKey(p)), let s = try? JSONDecoder().decode(UsageSnapshot.self, from: data) else { continue }
            states[p] = .ok(s)
            if let at = d.object(forKey: cacheKey(p) + ".at") as? Date {
                let f = DateFormatter(); f.dateFormat = "h:mm a"
                notes[p] = (backoffUntil[p].map { $0 > Date() } ?? false)
                    ? "Showing saved values from \(f.string(from: at)). Rate limited, next try at \(f.string(from: backoffUntil[p]!))."
                    : "Showing saved values from \(f.string(from: at)). Updating…"
            }
        }
    }

    private func save(_ key: String, _ value: Any) { d.set(value, forKey: key) }

    /// Apply the on/off choices instantly: clear disabled providers, fetch newly enabled ones.
    private func sync() {
        for p in Provider.allCases {
            if enabled.contains(p) {
                if case .off = states[p] ?? .off { fetch(p) }
            } else {
                states[p] = .off; notes[p] = nil
                if p == .claude { costReport = nil }
            }
        }
        restartTimer()
    }

    /// `force` is for the timer; opening the popover only refreshes data older than 60s (avoids rate limits).
    func refresh(force: Bool = false) {
        for p in enabled where force || Date().timeIntervalSince(lastFetch[p] ?? .distantPast) > 60 { fetch(p) }
    }

    private func fetch(_ p: Provider) {
        if let until = backoffUntil[p], until > Date() { return }   // still cooling down after a rate limit
        guard inFlight.insert(p).inserted else { return }
        lastFetch[p] = Date()   // never run two reads of the same provider at once
        if case .ok = states[p] ?? .off {} else { states[p] = .loading }
        Task {
            let result: Result<UsageSnapshot, UsageError>
            do {
                result = .success(try await (p == .claude ? ClaudeSource.fetch() : CodexSource.fetch()))
            } catch {
                result = .failure((error as? UsageError) ?? .badResponse)
            }
            inFlight.remove(p)
            guard enabled.contains(p) else { return }   // disabled while in flight
            switch result {
            case .success(let s): states[p] = .ok(s); notes[p] = nil; failStreak[p] = 0; backoffUntil[p] = nil; d.removeObject(forKey: "backoff.\(p.rawValue)"); saveCached(p, s); if p == .claude { updateCosts() }
            case .failure(let e):
                var e = e
                if case .rateLimited(let after) = e {
                    // Honor Retry-After; otherwise back off 5, 10, 20, 30 min. Never hammer the endpoint.
                    let n = failStreak[p, default: 0]; failStreak[p] = n + 1
                    let wait = max(after ?? 0, min(1800, 300 * pow(2, Double(n))))
                    backoffUntil[p] = Date().addingTimeInterval(wait)
                    d.set(backoffUntil[p], forKey: "backoff.\(p.rawValue)")
                    let f = DateFormatter(); f.dateFormat = "h:mm a"
                    notes[p] = nil
                    states[p] = { if case .ok = states[p] ?? .off { return states[p]! } else { return .loading } }()
                    e = .rateLimited(retryAfter: wait)
                    let msg = "Rate limited by \(p.displayName). Next try at \(f.string(from: Date().addingTimeInterval(wait)))."
                    if case .ok = states[p] ?? .off { notes[p] = msg } else { states[p] = .failed(msg) }
                    return
                }
                if case .ok = states[p] ?? .off { notes[p] = "Couldn't refresh: " + e.message(for: p) }   // keep last good numbers
                else { states[p] = .failed(e.message(for: p)) }
            }
        }
    }

    /// Recompute dollars for the current 5h / weekly windows and billing cycle (off the main thread; cached per file).
    func updateCosts() {
        guard monitorClaude else { costReport = nil; return }
        var snap: UsageSnapshot?
        if case .ok(let s) = states[.claude] ?? .off { snap = s }
        let now = Date(), day = renewalDay
        let cycle = CostMath.cycleRange(renewalDay: day, now: now)
        let weekEnd = snap?.weekly?.resetsAt, fiveEnd = snap?.fiveHour?.resetsAt
        let since = min(cycle.start, weekEnd.map { $0.addingTimeInterval(-7 * 86400) } ?? cycle.start)
        Task {
            let r = await scanner.entries(since: since)
            guard monitorClaude else { return }
            costReport = CostReport.make(entries: r.entries, fiveHourEnd: fiveEnd, weeklyEnd: weekEnd,
                                         renewalDay: day, now: now, unpriced: r.unpriced)
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard !enabled.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Double(intervalMinutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: true) }
        }
    }
}
