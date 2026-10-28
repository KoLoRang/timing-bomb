import ArgumentParser
import Foundation
import TimingBombCore
import TimingBombL10n

/// `tb logging` — run history logging toggle.
struct Logging: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logging",
        abstract: L10n.t("Run history logging toggle (off: new runs are not written to the log)"),
        subcommands: [Status.self, On.self, Off.self]
    )

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("Show current state"))

        func run() async throws {
            do {
                let client = try APIClient.load()
                let data = try await client.get("settings")
                let value = try CLI.decode(JSONValue.self, data)
                let enabled = value["loggingEnabled"]?.boolValue ?? true
                print(
                    enabled
                        ? L10n.t("run logging: on")
                        : L10n.t("run logging: off (new runs are not written to the log)"))
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    struct On: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("Enable run logging"))

        func run() async throws {
            try await set(true)
        }
    }

    struct Off: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("Disable run logging"))

        func run() async throws {
            try await set(false)
        }
    }

    private static func set(_ enabled: Bool) async throws {
        do {
            let client = try APIClient.load()
            let body = try TBJSON.encodeData(
                JSONValue.object(["loggingEnabled": .bool(enabled)]))
            _ = try await client.request("PUT", "settings", body: body)
            print(
                enabled
                    ? L10n.t("✓ run logging enabled")
                    : L10n.t("✓ run logging disabled (new runs are not written to the log)"))
        } catch {
            throw CLI.clean(error)
        }
    }
}
