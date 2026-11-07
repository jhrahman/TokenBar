import AppKit
import Foundation
import TokenBarCore

enum HTTP {
    static func get(_ url: String, headers: [String: String]) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!)
        req.timeoutInterval = 15
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw UsageError.offline }
        let http = resp as? HTTPURLResponse
        switch http?.statusCode ?? 0 {
        case 200: return data
        case 429: throw UsageError.rateLimited(retryAfter: http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        case 401, 403: throw UsageError.expired
        case let c: throw UsageError.http(c)
        }
    }
}

/// Keeps the token in memory so the Keychain (and its permission prompt) is read once per launch,
/// not on every refresh. Cleared when the token expires or the server rejects it.
private actor TokenCache {
    var token: String?
    var expires: Date?
    func get() -> String? {
        guard let token, let expires, expires > Date().addingTimeInterval(30) else { return nil }
        return token
    }
    func set(_ t: String, _ e: Date) { token = t; expires = e }
    func clear() { token = nil; expires = nil }
}

enum ClaudeSource {
    static let service = "Claude Code-credentials"
    static var isInstalled: Bool { Keychain.exists(service: service) }
    private static let cache = TokenCache()

    /// Local app: reads Claude Code's saved login (read-only, never refreshed).
    static func fetch() async throws -> UsageSnapshot {
        let tok = try await loadToken()
        do {
            return try await request(tok)
        } catch UsageError.expired {
            // Claude Code may have renewed its login since we cached it: re-read once.
            await cache.clear()
            return try await request(try await loadToken())
        }
    }

    private static func request(_ token: String) async throws -> UsageSnapshot {
        let data = try await HTTP.get("https://api.anthropic.com/api/oauth/usage", headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
        ])
        return try UsageParser.claude(data)
    }

    private static func loadToken() async throws -> String {
        if let t = await cache.get() { return t }
        guard await explainKeychain() else { throw UsageError.declined }
        guard let blob = Keychain.read(service: service),
              let json = try? JSONSerialization.jsonObject(with: blob) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { throw UsageError.notLoggedIn }
        let exp = ((oauth["expiresAt"] as? NSNumber)?.doubleValue).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantFuture
        if exp < Date() { throw UsageError.expired }
        await cache.set(token, exp)
        return token
    }

    /// One-time heads-up shown before macOS asks for the password. Not shown again once accepted.
    @MainActor private static func explainKeychain() -> Bool {
        // macOS asks for the password again whenever the app binary changes, so remember which build we explained for.
        let key = "keychainExplainedFor"
        let build = ((try? FileManager.default.attributesOfItem(atPath: Bundle.main.executablePath ?? ""))?[.modificationDate] as? Date)?
            .timeIntervalSince1970.description ?? "unknown"
        if UserDefaults.standard.string(forKey: key) == build { return true }
        let a = NSAlert()
        a.messageText = "TokenBar needs to read your Claude login"
        a.informativeText = """
        Next, macOS will ask for your Mac password. That's because Claude Code keeps its login in your Keychain, and macOS asks before any app reads it.

        \u{2022} Nothing is taken away or changed. TokenBar only reads it; it never edits or deletes it.
        \u{2022} Your password goes to macOS. TokenBar never sees or stores it.
        \u{2022} The login is used only to ask Anthropic for your usage numbers. It is kept in memory, not saved or sent anywhere else.

        Tip: choose \u{201C}Always Allow\u{201D} so you're not asked again.
        """
        a.addButton(withTitle: "Continue")
        a.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        UserDefaults.standard.set(build, forKey: key)
        return true
    }
}
