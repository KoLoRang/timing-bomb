import ArgumentParser
import Foundation
import TimingBombCore
import TimingBombL10n

// MARK: - DTOs

struct FlowItemDTO: Decodable {
    let flow: FlowDefinition
    let createdAt: Date
    let updatedAt: Date
}

struct FlowListDTO: Decodable {
    let flows: [FlowItemDTO]
}

struct ValidateDTO: Decodable {
    let valid: Bool
    let issues: [ValidationIssue]
}

// MARK: - tb flow

struct Flow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flow",
        abstract: L10n.t("Manage flows"),
        subcommands: [List.self, Show.self, Create.self, Remove.self, Validate.self]
    )

    // MARK: list

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("List flows"))

        @Flag(name: .long, help: ArgumentHelp(L10n.t("Output as JSON"))) var json = false

        func run() async throws {
            do {
                let client = try APIClient.load()
                let data = try await client.get("flows")
                if json {
                    CLI.printJSON(data)
                    return
                }
                let body = try CLI.decode(FlowListDTO.self, data)
                if body.flows.isEmpty {
                    print(L10n.t("no flows yet. Create one with `tb flow create --file <flow.json>`."))
                    return
                }
                print(
                    CLI.row(
                        "ID", 24, L10n.t("NAME"), 20, L10n.t("NODES"), 6,
                        L10n.t("TRIGGER"), 14, L10n.t("UPDATED"), 12))
                for item in body.flows {
                    let trigger = item.flow.trigger.flatMap { trigger in
                        if let cron = trigger.cron { return cron }
                        return trigger.type?.rawValue ?? "manual"
                    } ?? "manual"
                    print(
                        CLI.row(
                            item.flow.id, 24, item.flow.name, 20,
                            String(item.flow.nodes.count), 6, trigger, 14,
                            CLI.fmt(item.updatedAt), 12))
                }
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    // MARK: show

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("Show a flow definition"))

        @Argument(help: ArgumentHelp(L10n.t("flow id"))) var flowId: String
        @Flag(name: .long, help: ArgumentHelp(L10n.t("Output as JSON"))) var json = false

        func run() async throws {
            do {
                let client = try APIClient.load()
                let data = try await client.get("flows/\(flowId)")
                if json {
                    CLI.printJSON(data)
                    return
                }
                let item = try CLI.decode(FlowItemDTO.self, data)
                let encoded = try TBJSON.prettyEncoder.encode(item.flow)
                print(String(decoding: encoded, as: UTF8.self))
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    // MARK: create

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: L10n.t("Create/update a flow (pass JSON via --file or stdin)"))

        @Option(help: ArgumentHelp(L10n.t("path to the flow JSON file"))) var file: String?
        @Flag(name: .long, help: ArgumentHelp(L10n.t("Output as JSON"))) var json = false

        func run() async throws {
            do {
                let source = try CLI.readFlowSource(file)
                // Decode locally first for a clearer error.
                _ = try TBJSON.decodeData(FlowDefinition.self, from: source)
                let client = try APIClient.load()
                let data = try await client.post("flows", body: source)
                if json {
                    CLI.printJSON(data)
                    return
                }
                let item = try CLI.decode(FlowItemDTO.self, data)
                print(
                    L10n.t(
                        "✓ saved flow {id} ({name}, {count} node(s))",
                        [
                            "id": item.flow.id,
                            "name": item.flow.name,
                            "count": String(item.flow.nodes.count),
                        ]))
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    // MARK: remove

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rm", abstract: L10n.t("Delete a flow"))

        @Argument(help: ArgumentHelp(L10n.t("flow id"))) var flowId: String

        func run() async throws {
            do {
                let client = try APIClient.load()
                _ = try await client.delete("flows/\(flowId)")
                print(L10n.t("✓ deleted flow {id}", ["id": flowId]))
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    // MARK: validate

    struct Validate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: L10n.t("Validate a flow (without saving)"))

        @Option(help: ArgumentHelp(L10n.t("path to the flow JSON file"))) var file: String?

        func run() async throws {
            do {
                let source = try CLI.readFlowSource(file)
                let client = try APIClient.load()
                let data = try await client.post("validate", body: source)
                let body = try CLI.decode(ValidateDTO.self, data)
                if body.valid {
                    print(L10n.t("✓ validation passed"))
                } else {
                    print(L10n.t("✗ validation failed:"))
                }
                for issue in body.issues {
                    let mark = issue.level == .error ? "error" : "warn "
                    print("  [\(mark)] \(issue.path): \(issue.localizedMessage)")
                }
                if !body.valid { throw ExitCode(1) }
            } catch {
                throw CLI.clean(error)
            }
        }
    }
}
