import Foundation
import TokenBarCore

enum CodexSource {
    static var authPath: String { NSHomeDirectory() + "/.codex/auth.json" }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: authPath) }

    /// Local app: reads ~/.codex/auth.json (read-only, never refreshed). Endpoint is UNVERIFIED.
    static func fetch() async throws -> UsageSnapshot {
        guard let d = FileManager.default.contents(atPath: authPath),
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String else { throw UsageError.notLoggedIn }
        var headers = ["Authorization": "Bearer \(access)"]
        if let acct = tokens["account_id"] as? String { headers["ChatGPT-Account-Id"] = acct }
        let data = try await HTTP.get("https://chatgpt.com/backend-api/wham/usage", headers: headers)
        return try UsageParser.codex(data)
    }
}
