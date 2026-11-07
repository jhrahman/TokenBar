import XCTest
@testable import TokenBarCore

final class CoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func testFiveHour() {
        XCTAssertEqual(ResetText.fiveHour(resetsAt: now.addingTimeInterval(78 * 60), now: now), "resetting in 1.3h")
        XCTAssertEqual(ResetText.fiveHour(resetsAt: now.addingTimeInterval(30 * 60), now: now), "resetting in 30 min")
        XCTAssertEqual(ResetText.fiveHour(resetsAt: now.addingTimeInterval(30), now: now), "resetting in <1 min")
        XCTAssertEqual(ResetText.fiveHour(resetsAt: now.addingTimeInterval(-5), now: now), "resetting now")
        XCTAssertEqual(ResetText.fiveHour(resetsAt: nil, now: now), "reset time unavailable")
    }

    func testWeekly() {
        let dhaka = TimeZone(identifier: "Asia/Dhaka")!
        let f = ISO8601DateFormatter()
        XCTAssertEqual(ResetText.weekly(resetsAt: f.date(from: "2029-11-26T16:00:00Z")!, now: now, timeZone: dhaka), "resetting Mon, 26 Nov, 10 PM")
        XCTAssertEqual(ResetText.weekly(resetsAt: f.date(from: "2029-11-26T16:30:00Z")!, now: now, timeZone: dhaka), "resetting Mon, 26 Nov, 10:30 PM")
    }

    func testProviders() {
        XCTAssertEqual(providersToPoll(monitorClaude: true, monitorCodex: true), [.claude, .codex])
        XCTAssertEqual(providersToPoll(monitorClaude: true, monitorCodex: false), [.claude])
        XCTAssertEqual(providersToPoll(monitorClaude: false, monitorCodex: true), [.codex])
        XCTAssertEqual(providersToPoll(monitorClaude: false, monitorCodex: false), [])
    }

    func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func testClaudeParser() throws {
        let s = try UsageParser.claude(fixture("claude-usage.json"))
        XCTAssertNotNil(s.fiveHour?.resetsAt)
        XCTAssertNotNil(s.weekly?.resetsAt)
        XCTAssertThrowsError(try UsageParser.claude(Data("{}".utf8)))
    }

    func testCodexParser() throws {
        let s = try UsageParser.codex(fixture("codex-usage.SYNTHETIC.json"))
        XCTAssertEqual(s.fiveHour?.percent, 12)
        XCTAssertEqual(s.weekly?.percent, 41)
        XCTAssertEqual(s.weekly?.resetsAt, Date(timeIntervalSince1970: 1893700000))
        XCTAssertThrowsError(try UsageParser.codex(Data("{}".utf8)))
    }
}

final class CostTests: XCTestCase {
    func testCost() {
        // 1M input + 1M output on Sonnet 5.5 = $2 + $10
        let u = TokenUsage(input: 1_000_000, output: 1_000_000)
        XCTAssertEqual(Pricing.cost(u, model: "claude-sonnet-5-5")!, 12, accuracy: 0.0001)
        // cache: 1M read ($0.20) + 1M 1h write (2x $4 = $8) on Opus 5.5
        let c = TokenUsage(cacheRead: 1_000_000, cacheWrite1h: 1_000_000)
        XCTAssertEqual(Pricing.cost(c, model: "claude-opus-5-5")!, 8.2, accuracy: 0.0001)
        XCTAssertNil(Pricing.cost(u, model: "mystery-model"))
        XCTAssertEqual(Pricing.displayName("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(Pricing.displayName("claude-sonnet-5"), "Sonnet 5")
    }

    func testCycle() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-11-07T10:00:00Z")!
        let r = CostMath.cycleRange(renewalDay: 3, now: now, calendar: cal)
        XCTAssertEqual(r.start, ISO8601DateFormatter().date(from: "2026-11-03T00:00:00Z"))
        XCTAssertEqual(r.end, ISO8601DateFormatter().date(from: "2026-12-03T00:00:00Z"))
        let r2 = CostMath.cycleRange(renewalDay: 20, now: now, calendar: cal)   // not yet this month -> started last month
        XCTAssertEqual(r2.start, ISO8601DateFormatter().date(from: "2026-10-20T00:00:00Z"))
        let r3 = CostMath.cycleRange(renewalDay: 31, now: now, calendar: cal)   // clamps to 30 days in Nov
        XCTAssertEqual(r3.end, ISO8601DateFormatter().date(from: "2026-11-30T00:00:00Z"))
    }

    func testBuckets() {
        let s = Date(timeIntervalSince1970: 0)
        let e = [CostEntry(date: s.addingTimeInterval(10), model: "a", cost: 1),
                 CostEntry(date: s.addingTimeInterval(3700), model: "b", cost: 2)]
        let b = CostMath.buckets(e, range: DateRange(start: s, end: s.addingTimeInterval(7200)), step: 3600)
        XCTAssertEqual(b.map(\.total), [1, 2])
    }
}
