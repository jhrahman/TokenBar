import Foundation

public struct UsageWindow: Equatable, Codable {
    public var percent: Double
    public var resetsAt: Date?
    public init(percent: Double, resetsAt: Date?) { self.percent = percent; self.resetsAt = resetsAt }
}

public struct UsageSnapshot: Equatable, Codable {
    public var fiveHour: UsageWindow?
    public var weekly: UsageWindow?
    public init(fiveHour: UsageWindow?, weekly: UsageWindow?) { self.fiveHour = fiveHour; self.weekly = weekly }
}

public enum UsageError: Error, Equatable {
    case notLoggedIn, expired, offline, badResponse, declined, http(Int), rateLimited(retryAfter: TimeInterval?)

    public func message(for p: Provider) -> String {
        switch self {
        case .notLoggedIn: return "Not logged in. Sign in to \(p.displayName) first."
        case .expired: return "Open \(p.displayName) once to renew login"
        case .offline: return "Offline"
        case .rateLimited: return "Rate limited by \(p.displayName)"
        case .http(let c): return "\(p.displayName) returned HTTP \(c)"
        case .declined: return "Keychain access not allowed yet. Open TokenBar again to retry."
        case .badResponse: return "Unexpected response from \(p.displayName)"
        }
    }
}

/// Pure JSON -> snapshot parsing (network code lives in the app target).
public enum UsageParser {
    /// Claude: `{"five_hour":{"utilization":4.0,"resets_at":"2026-11-07T12:00:00.09+00:00"},"seven_day":{...}}`
    public static func claude(_ data: Data) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageError.badResponse }
        func window(_ key: String) -> UsageWindow? {
            guard let w = root[key] as? [String: Any], let pct = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return UsageWindow(percent: pct, resetsAt: (w["resets_at"] as? String).flatMap(parseISO))
        }
        let snap = UsageSnapshot(fiveHour: window("five_hour"), weekly: window("seven_day"))
        if snap.fiveHour == nil && snap.weekly == nil { throw UsageError.badResponse }
        return snap
    }

    /// Codex (unverified, from memory of ChatGPT's backend):
    /// `{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_at":1730000000,"reset_after_seconds":900},"secondary_window":{...}}}`
    /// Windows are told apart by length (<= 6h is the 5h window, otherwise weekly); falls back to primary/secondary order.
    public static func codex(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = root["rate_limit"] as? [String: Any] else { throw UsageError.badResponse }
        func parse(_ key: String) -> (UsageWindow, Double?)? {
            guard let w = rl[key] as? [String: Any], let pct = (w["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            var reset: Date?
            if let at = (w["reset_at"] as? NSNumber)?.doubleValue { reset = Date(timeIntervalSince1970: at) }
            else if let after = (w["reset_after_seconds"] as? NSNumber)?.doubleValue { reset = now.addingTimeInterval(after) }
            return (UsageWindow(percent: pct, resetsAt: reset), (w["limit_window_seconds"] as? NSNumber)?.doubleValue)
        }
        let p = parse("primary_window"), s = parse("secondary_window")
        var snap = UsageSnapshot(fiveHour: p?.0, weekly: s?.0)
        if let p, let s, let pl = p.1, let sl = s.1, pl > sl { snap = UsageSnapshot(fiveHour: s.0, weekly: p.0) }
        else if let p, s == nil, let pl = p.1, pl > 6 * 3600 { snap = UsageSnapshot(fiveHour: nil, weekly: p.0) }
        if snap.fiveHour == nil && snap.weekly == nil { throw UsageError.badResponse }
        return snap
    }

    /// Handles "2026-11-07T12:00:00.090498+00:00" (microseconds) and plain forms.
    public static func parseISO(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
