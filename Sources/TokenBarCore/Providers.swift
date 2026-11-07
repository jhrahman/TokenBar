import Foundation

public enum Provider: String, CaseIterable {
    case claude, codex
    public var displayName: String { self == .claude ? "Claude" : "Codex" }
}

/// Which providers should be polled right now.
public func providersToPoll(monitorClaude: Bool, monitorCodex: Bool) -> [Provider] {
    var p: [Provider] = []
    if monitorClaude { p.append(.claude) }
    if monitorCodex { p.append(.codex) }
    return p
}
