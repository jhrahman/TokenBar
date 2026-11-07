import Foundation

public struct TokenUsage: Equatable {
    public var input = 0, output = 0, cacheRead = 0, cacheWrite5m = 0, cacheWrite1h = 0
    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input; self.output = output; self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m; self.cacheWrite1h = cacheWrite1h
    }
}

/// USD per million tokens. Cache writes: 5 min = 1.25x input, 1 hour = 2x input.
public struct ModelPrice {
    public var input: Double, output: Double, cacheRead: Double
}

public enum Pricing {
    // Prices as published Oct 2026 (Anthropic API list prices). Longest prefix first. Estimates only.
    static let table: [(String, ModelPrice)] = [
        ("claude-opus-5-5", .init(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", .init(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-opus-4-1", .init(input: 15, output: 75, cacheRead: 1.50)),
        ("claude-opus-4-2", .init(input: 15, output: 75, cacheRead: 1.50)),   // dated Opus 4 snapshots
        ("claude-opus-4", .init(input: 5, output: 25, cacheRead: 0.50)),
        ("claude-sonnet-5", .init(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-4", .init(input: 3, output: 15, cacheRead: 0.30)),
        ("claude-haiku-5", .init(input: 0.10, output: 0.50, cacheRead: 0.01)),
        ("claude-haiku-4", .init(input: 1, output: 5, cacheRead: 0.10)),
        ("claude-fable-5", .init(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5", .init(input: 10, output: 50, cacheRead: 0.25)),
    ]

    public static func price(for model: String) -> ModelPrice? { table.first { model.hasPrefix($0.0) }?.1 }

    /// nil when the model isn't in the table (reported to the user instead of guessing).
    public static func cost(_ u: TokenUsage, model: String) -> Double? {
        guard let p = price(for: model) else { return nil }
        let m = 1_000_000.0
        return (Double(u.input) * p.input + Double(u.output) * p.output + Double(u.cacheRead) * p.cacheRead
            + Double(u.cacheWrite5m) * p.input * 1.25 + Double(u.cacheWrite1h) * p.input * 2) / m
    }

    /// "claude-opus-5-5" -> "Opus 5.5"
    public static func displayName(_ model: String) -> String {
        let parts = model.split(separator: "-").dropFirst()
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().filter { $0.count < 8 && Int($0) != nil }.joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}

public struct CostEntry: Equatable {
    public var date: Date, model: String, cost: Double
    public init(date: Date, model: String, cost: Double) { self.date = date; self.model = model; self.cost = cost }
}

public struct DateRange: Equatable {
    public var start: Date, end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

public struct CostBucket: Identifiable {
    public var start: Date, end: Date
    public var perModel: [String: Double]
    public var id: Date { start }
    public var total: Double { perModel.values.reduce(0, +) }
}

public struct CostReport {
    public var fiveHour: Double?, weekly: Double?, cycle: Double
    public var fiveRange: DateRange?, weekRange: DateRange?, cycleRange: DateRange
    public var entries: [CostEntry]
    public var unpriced: [String]

    public static func make(entries: [CostEntry], fiveHourEnd: Date?, weeklyEnd: Date?, renewalDay: Int,
                            now: Date = Date(), unpriced: [String] = [], calendar: Calendar = .current) -> CostReport {
        func range(_ end: Date?, _ length: TimeInterval) -> DateRange? {
            guard let end, end > now else { return nil }   // window already reset: nothing counted yet
            return DateRange(start: end.addingTimeInterval(-length), end: end)
        }
        let five = range(fiveHourEnd, 5 * 3600), week = range(weeklyEnd, 7 * 86400)
        let cycle = CostMath.cycleRange(renewalDay: renewalDay, now: now, calendar: calendar)
        return CostReport(fiveHour: five.map { CostMath.sum(entries, in: $0) },
                          weekly: week.map { CostMath.sum(entries, in: $0) },
                          cycle: CostMath.sum(entries, in: cycle),
                          fiveRange: five, weekRange: week, cycleRange: cycle,
                          entries: entries, unpriced: unpriced)
    }
}

public enum CostMath {
    public static func sum(_ e: [CostEntry], in r: DateRange) -> Double {
        e.filter { $0.date >= r.start && $0.date < r.end }.reduce(0) { $0 + $1.cost }
    }

    /// Current billing cycle: from the most recent renewal day (clamped to short months) to the next one.
    public static func cycleRange(renewalDay: Int, now: Date, calendar: Calendar = .current) -> DateRange {
        func renewal(monthOffset: Int) -> Date {
            let base = calendar.date(byAdding: .month, value: monthOffset, to: now)!
            var c = calendar.dateComponents([.year, .month], from: base)
            let days = calendar.range(of: .day, in: .month, for: base)!.count
            c.day = min(max(renewalDay, 1), days)
            return calendar.date(from: c)!
        }
        let thisMonth = renewal(monthOffset: 0)
        if thisMonth <= now { return DateRange(start: thisMonth, end: renewal(monthOffset: 1)) }
        return DateRange(start: renewal(monthOffset: -1), end: thisMonth)
    }

    public static func buckets(_ entries: [CostEntry], range: DateRange, step: TimeInterval) -> [CostBucket] {
        let n = max(1, Int(ceil(range.end.timeIntervalSince(range.start) / step)))
        var out = (0..<n).map { i in
            CostBucket(start: range.start.addingTimeInterval(Double(i) * step),
                       end: min(range.end, range.start.addingTimeInterval(Double(i + 1) * step)), perModel: [:])
        }
        for e in entries where e.date >= range.start && e.date < range.end {
            let i = min(n - 1, Int(e.date.timeIntervalSince(range.start) / step))
            out[i].perModel[e.model, default: 0] += e.cost
        }
        return out
    }
}

public enum Money {
    /// "$0.42", "$12.30", "$1,234" (whole dollars once large)
    public static func format(_ v: Double) -> String {
        if v >= 1000 { return "$" + String(format: "%.0f", v).replacingOccurrences(of: #"(\d)(?=(\d{3})+$)"#, with: "$1,", options: .regularExpression) }
        return String(format: "$%.2f", v)
    }
}
