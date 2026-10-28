import Foundation

/// Allowlist for sensitive commands (shell / appleScript).
///
/// Rules: `git status` allows that command itself and its argument forms (git status -s); `git *` allows any
/// git subcommand; `*` lets everything through (at your own risk). Leading/trailing whitespace is stripped before matching.
public struct Allowlist: Codable, Equatable, Sendable {
    public var patterns: [String]

    public init(patterns: [String] = []) {
        self.patterns = patterns
    }

    public func matches(_ command: String) -> Bool {
        let target = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        for pattern in patterns {
            let rule = pattern.trimmingCharacters(in: .whitespaces)
            if rule == "*" { return true }
            if rule.hasSuffix("*") {
                // Keep the trailing space as a command boundary: the "git *" prefix is "git ", which will not match "gitx"
                let prefix = String(rule.dropLast())
                if !prefix.isEmpty && target.hasPrefix(prefix) { return true }
            } else if target == rule || target.hasPrefix(rule + " ") {
                return true
            }
        }
        return false
    }
}

// MARK: - Storage (settings table, key = "allowlist")

extension Store {
    public func allowlist() async -> Allowlist {
        guard let text = try? await setting("allowlist"),
            let data = text.data(using: .utf8),
            let list = try? TBJSON.decodeData(Allowlist.self, from: data)
        else { return Allowlist() }
        return list
    }

    public func saveAllowlist(_ list: Allowlist) async throws {
        try await setSetting("allowlist", TBJSON.encode(list))
    }
}
