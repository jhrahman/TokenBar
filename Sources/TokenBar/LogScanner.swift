import Foundation
import TokenBarCore

/// Reads Claude Code's local session logs (~/.claude/projects/**/*.jsonl), read-only, and turns token counts into
/// estimated dollars at API list prices. Unchanged files are served from an in-memory cache.
actor LogScanner {
    private struct Raw { let key: String; let date: Date; let model: String; let usage: TokenUsage }
    private struct Cached { let mtime: Date; let size: Int; let rows: [Raw] }
    private var cache: [String: Cached] = [:]

    func entries(since: Date, root: String = NSHomeDirectory() + "/.claude/projects") -> (entries: [CostEntry], unpriced: [String]) {
        var best: [String: Raw] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        if let en = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys) {
            for case let url as URL in en where url.pathExtension == "jsonl" {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), let m = v.contentModificationDate, m >= since else { continue }
                let size = v.fileSize ?? 0
                let rows: [Raw]
                if let c = cache[url.path], c.mtime == m, c.size == size { rows = c.rows }
                else { rows = Self.parse(url, since: since); cache[url.path] = Cached(mtime: m, size: size, rows: rows) }
                // A message is logged several times while streaming; keep the copy with the most output tokens.
                for r in rows where (best[r.key]?.usage.output ?? -1) < r.usage.output { best[r.key] = r }
            }
        }
        var out: [CostEntry] = [], unpriced = Set<String>()
        for r in best.values where r.date >= since {
            if let c = Pricing.cost(r.usage, model: r.model) { out.append(CostEntry(date: r.date, model: r.model, cost: c)) }
            else { unpriced.insert(r.model) }
        }
        return (out, unpriced.sorted())
    }

    private static func parse(_ url: URL, since: Date) -> [Raw] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let marker = Data("\"output_tokens\"".utf8)
        var rows: [Raw] = []
        for line in data.split(separator: 10) where line.range(of: marker) != nil {
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let m = o["message"] as? [String: Any], let u = m["usage"] as? [String: Any],
                  let model = m["model"] as? String, model != "<synthetic>",
                  let ts = o["timestamp"] as? String, let date = UsageParser.parseISO(ts) else { continue }
            func n(_ d: [String: Any]?, _ k: String) -> Int { (d?[k] as? NSNumber)?.intValue ?? 0 }
            let cc = u["cache_creation"] as? [String: Any]
            let w5 = cc == nil ? n(u, "cache_creation_input_tokens") : n(cc, "ephemeral_5m_input_tokens")
            let w1 = n(cc, "ephemeral_1h_input_tokens")
            let key = "\(m["id"] as? String ?? "")|\(o["requestId"] as? String ?? o["uuid"] as? String ?? "")"
            rows.append(Raw(key: key, date: date, model: model,
                            usage: TokenUsage(input: n(u, "input_tokens"), output: n(u, "output_tokens"),
                                              cacheRead: n(u, "cache_read_input_tokens"), cacheWrite5m: w5, cacheWrite1h: w1)))
        }
        return rows
    }
}
