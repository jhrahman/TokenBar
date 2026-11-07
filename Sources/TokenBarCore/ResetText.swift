import Foundation

public enum ResetText {
    /// 5h window: relative countdown.
    public static func fiveHour(resetsAt: Date?, now: Date = Date()) -> String {
        guard let resetsAt else { return "reset time unavailable" }
        let secs = resetsAt.timeIntervalSince(now)
        if secs <= 0 { return "resetting now" }
        if secs < 60 { return "resetting in <1 min" }
        if secs < 3600 { return "resetting in \(Int((secs / 60).rounded())) min" }
        return "resetting in \(String(format: "%.1f", secs / 3600))h"
    }

    /// Weekly window: exact date/time in the Mac's time zone, 12-hour clock.
    public static func weekly(resetsAt: Date?, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        guard let resetsAt else { return "reset time unavailable" }
        if resetsAt <= now { return "resetting now" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hasMinutes = cal.component(.minute, from: resetsAt) != 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = hasMinutes ? "EEE, d MMM, h:mm a" : "EEE, d MMM, h a"
        return "resetting " + f.string(from: resetsAt)
    }
}
