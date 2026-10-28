import ArgumentParser
import Foundation
import TimingBombCore
import TimingBombL10n

/// `tb allow` — command allowlist management for shell / appleScript actions.
struct Allow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "allow",
        abstract: L10n.t("Manage the shell/appleScript allowlist"),
        subcommands: [List.self, Add.self, Remove.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("List allowlist rules"))

        func run() async throws {
            do {
                let client = try APIClient.load()
                let data = try await client.get("allows")
                let value = try CLI.decode(JSONValue.self, data)
                guard case .array(let items)? = value["patterns"] else {
                    print(L10n.t("(no rules)"))
                    return
                }
                let patterns = items.compactMap(\.stringValue)
                if patterns.isEmpty {
                    print(L10n.t("(no rules)"))
                } else {
                    for pattern in patterns {
                        print(pattern)
                    }
                }
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("Add an allowlist rule"))

        @Argument(
            help: ArgumentHelp(
                L10n.t("rule: `git status` matches exactly; `git *` matches by prefix; `*` allows everything")
            )
        ) var pattern: String

        func run() async throws {
            do {
                let client = try APIClient.load()
                let current = try await Allow.loadPatterns(client)
                let rule = pattern.trimmingCharacters(in: .whitespaces)
                guard !rule.isEmpty else {
                    throw TBApiError(status: 400, code: "emptyRule", template: "rule cannot be empty")
                }
                guard !current.contains(rule) else {
                    print(L10n.t("already exists: {rule}", ["rule": rule]))
                    return
                }
                try await Allow.savePatterns(current + [rule], client)
                print(L10n.t("✓ added: {rule}", ["rule": rule]))
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rm", abstract: L10n.t("Remove an allowlist rule"))

        @Argument(help: ArgumentHelp(L10n.t("rule to remove (exact text)"))) var pattern: String

        func run() async throws {
            do {
                let client = try APIClient.load()
                let current = try await Allow.loadPatterns(client)
                guard current.contains(pattern) else {
                    throw TBApiError(
                        status: 400, code: "ruleNotFound",
                        template: "rule not found: {rule}", params: ["rule": pattern])
                }
                try await Allow.savePatterns(current.filter { $0 != pattern }, client)
                print(L10n.t("✓ removed: {rule}", ["rule": pattern]))
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    static func loadPatterns(_ client: APIClient) async throws -> [String] {
        let data = try await client.get("allows")
        let value = try CLI.decode(JSONValue.self, data)
        guard case .array(let items)? = value["patterns"] else { return [] }
        return items.compactMap(\.stringValue)
    }

    static func savePatterns(_ patterns: [String], _ client: APIClient) async throws {
        let body = try TBJSON.encodeData(JSONValue.array(patterns.map { .string($0) }))
        _ = try await client.request("PUT", "allows", body: body)
    }
}
