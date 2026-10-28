import ArgumentParser
import Foundation
import TimingBombCore
import TimingBombL10n

// MARK: - DTOs

struct RunStartedDTO: Decodable {
    let runId: String
    let status: String
}

struct RunDTO: Decodable {
    let run: RunRecord
}

struct RunListDTO: Decodable {
    let runs: [RunRecord]
}

// MARK: - tb run

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: L10n.t("Trigger a flow run"))

    @Argument(help: ArgumentHelp(L10n.t("flow id"))) var flowId: String
    @Option(help: ArgumentHelp(L10n.t("input payload (JSON string); injected as ctx.trigger.payload")))
    var input: String?
    @Flag(name: .long, help: ArgumentHelp(L10n.t("wait for the run to finish and print the result")))
    var wait = false
    @Flag(name: .long, help: ArgumentHelp(L10n.t("dry-run: no real side effects (http/commands/file writes are skipped)")))
    var dryRun = false
    @Flag(name: .long, help: ArgumentHelp(L10n.t("Output as JSON"))) var json = false

    func run() async throws {
        do {
            var payload: JSONValue? = nil
            if let input {
                guard let value = try? TBJSON.decode(JSONValue.self, from: input) else {
                    throw TBApiError(
                        status: 400, code: "invalidInputJSON",
                        template: "--input is not valid JSON: {detail}",
                        params: ["detail": String(input.prefix(100))])
                }
                payload = value
            }
            let body = try TBJSON.encodeData(["payload": payload ?? JSONValue.null])
            let client = try APIClient.load()
            var query = wait ? ["wait": "1"] : [:]
            if dryRun { query["dryRun"] = "1" }
            let data = try await client.post("flows/\(flowId)/run", body: body, query: query)
            if json {
                CLI.printJSON(data)
                return
            }
            if wait {
                let record = try CLI.decode(RunDTO.self, data).run
                PrintRun.summary(record)
            } else {
                let started = try CLI.decode(RunStartedDTO.self, data)
                print(
                    dryRun
                        ? L10n.t(
                            "dry-run started: runId={runId} (no side effects; check `tb runs show {runId}`)",
                            ["runId": started.runId])
                        : L10n.t(
                            "started: runId={runId} (check `tb runs show {runId}` for progress)",
                            ["runId": started.runId]))
            }
        } catch {
            throw CLI.clean(error)
        }
    }
}

// MARK: - tb runs

struct Runs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runs",
        abstract: L10n.t("Run history"),
        subcommands: [List.self, Show.self, Cancel.self, Remove.self, Clear.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("List run history"))

        @Option(help: ArgumentHelp(L10n.t("filter by flow id"))) var flowId: String?
        @Option(help: ArgumentHelp(L10n.t("number of records to return"))) var limit: Int = 20
        @Flag(name: .long, help: ArgumentHelp(L10n.t("Output as JSON"))) var json = false

        func run() async throws {
            do {
                let client = try APIClient.load()
                var query = ["limit": String(limit)]
                if let flowId { query["flowId"] = flowId }
                let data = try await client.get("runs", query: query)
                if json {
                    CLI.printJSON(data)
                    return
                }
                let body = try CLI.decode(RunListDTO.self, data)
                if body.runs.isEmpty {
                    print(L10n.t("no run records yet"))
                    return
                }
                print(
                    CLI.row(
                        "RUN ID", 38, L10n.t("FLOW"), 18, L10n.t("STATUS"), 9,
                        L10n.t("DURATION"), 10, L10n.t("STARTED"), 12))
                for record in body.runs {
                    let duration = record.endedAt.map { $0.timeIntervalSince(record.startedAt) * 1000 }
                    print(
                        CLI.row(
                            record.id, 38, record.flowId, 18, record.status.rawValue, 9,
                            CLI.fmtDuration(duration), 10, CLI.fmt(record.startedAt), 12))
                }
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: L10n.t("Show run details (node timeline / logs)"))

        @Argument(help: ArgumentHelp(L10n.t("run id"))) var runId: String
        @Flag(name: .long, help: ArgumentHelp(L10n.t("Output as JSON"))) var json = false

        func run() async throws {
            do {
                let client = try APIClient.load()
                let data = try await client.get("runs/\(runId)")
                if json {
                    CLI.printJSON(data)
                    return
                }
                let record = try CLI.decode(RunDTO.self, data).run
                PrintRun.detail(record)
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    struct Cancel: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("Cancel a running run"))

        @Argument(help: ArgumentHelp(L10n.t("run id"))) var runId: String

        func run() async throws {
            do {
                let client = try APIClient.load()
                _ = try await client.post("runs/\(runId)/cancel")
                print(L10n.t("✓ cancel request sent (runId={runId})", ["runId": runId]))
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rm", abstract: L10n.t("Delete one run record"))

        @Argument(help: ArgumentHelp(L10n.t("run id"))) var runId: String

        func run() async throws {
            do {
                let client = try APIClient.load()
                _ = try await client.delete("runs/\(runId)")
                print(L10n.t("✓ deleted run record {runId}", ["runId": runId]))
            } catch {
                throw CLI.clean(error)
            }
        }
    }

    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: L10n.t("Clear run records"))

        @Option(help: ArgumentHelp(L10n.t("only clear the given flow (default: all flows)")))
        var flowId: String?
        @Flag(name: .long, help: ArgumentHelp(L10n.t("skip confirmation"))) var yes = false

        func run() async throws {
            do {
                let scope =
                    flowId.map { L10n.t("flow {id}", ["id": $0]) }
                    ?? L10n.t("all flows")
                if !yes {
                    print(
                        L10n.t(
                            "This will delete all run records for {scope}; it cannot be undone. Re-run with --yes to confirm.",
                            ["scope": scope]))
                    throw ExitCode(1)
                }
                let client = try APIClient.load()
                var query: [String: String] = [:]
                if let flowId { query["flowId"] = flowId }
                let data = try await client.request("DELETE", "runs", query: query)
                let value = try CLI.decode(JSONValue.self, data)
                let deleted = value["deleted"]?.intValue ?? 0
                print(
                    L10n.t(
                        "✓ deleted {count} run record(s) for {scope}",
                        ["count": String(deleted), "scope": scope]))
            } catch {
                throw CLI.clean(error)
            }
        }
    }
}

// MARK: - Rendering

enum PrintRun {
    static let statusMark: [RunStatus: String] = [
        .success: "✓", .failed: "✗", .timeout: "⏱", .cancelled: "⊘", .running: "…",
        .pending: "…", .awaitingApproval: "⏸",
    ]

    static func summary(_ record: RunRecord) {
        let mark = statusMark[record.status] ?? "?"
        let duration = record.endedAt.map { $0.timeIntervalSince(record.startedAt) * 1000 }
        print(
            L10n.t(
                "{mark} run {runId} — {status} ({duration})",
                [
                    "mark": mark,
                    "runId": record.id,
                    "status": record.status.rawValue,
                    "duration": CLI.fmtDuration(duration),
                ]))
        if let error = record.error, !record.status.isSuccess {
            print(L10n.t("  Error: {detail}", ["detail": error]))
        }
    }

    static func detail(_ record: RunRecord) {
        summary(record)
        print(L10n.t("  Trigger: {type}", ["type": record.trigger.type]))
        print(L10n.t("  Node timeline:"))
        for nodeRun in record.nodeRuns {
            let duration = nodeRun.endedAt.map { $0.timeIntervalSince(nodeRun.startedAt) * 1000 }
            let iteration = nodeRun.iteration.map { "#\($0) " } ?? ""
            print(
                "    \(statusMark[mapStatus(nodeRun.status)] ?? "?") \(iteration)\(nodeRun.nodeId) (\(nodeRun.nodeType), \(CLI.fmtDuration(duration)))"
            )
            if let error = nodeRun.error {
                print(L10n.t("        Error: {detail}", ["detail": error]))
            }
            for log in nodeRun.logs {
                print(L10n.t("        Log: {detail}", ["detail": log]))
            }
        }
        if let context = record.context {
            let encoded = (try? TBJSON.prettyEncoder.encode(["context": context]))
                .map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            print(L10n.t("  Final context:"))
            for line in encoded.split(separator: "\n") {
                print("    \(line)")
            }
        }
    }

    private static func mapStatus(_ status: NodeRunStatus) -> RunStatus {
        switch status {
        case .success: return .success
        case .failed: return .failed
        case .timeout: return .timeout
        case .cancelled: return .cancelled
        case .skipped: return .pending
        }
    }
}

extension RunStatus {
    var isSuccess: Bool { self == .success }
}
