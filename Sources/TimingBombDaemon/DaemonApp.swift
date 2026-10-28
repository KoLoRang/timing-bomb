import Foundation
import Security
import TimingBombCore
import TimingBombL10n
import TimingBombRunner

// MARK: - Response payloads

struct HealthResponse: Codable {
    let status: String
    let version: String
}

struct ValidateResponse: Codable {
    let valid: Bool
    let issues: [ValidationIssue]
}

struct RunStartedResponse: Codable {
    let runId: String
    let status: String
}

struct RunResponse: Codable {
    let run: RunRecord
}

struct RunListResponse: Codable {
    let runs: [RunRecord]
}

struct FlowListResponse: Codable {
    let flows: [Store.FlowMeta]
}

struct FlowItemResponse: Codable {
    let flow: FlowDefinition
    let createdAt: Date
    let updatedAt: Date
}

struct OKResponse: Codable {
    let ok: Bool

    init() {
        ok = true
    }
}

// MARK: - Daemon application

public final class DaemonApp: @unchecked Sendable {
    /// Reads CFBundleShortVersionString from the enclosing .app bundle (set by
    /// scripts/make-app.sh from TB_VERSION, i.e. the release tag on CI);
    /// falls back for bare SPM runs (`swift run`), where there is no bundle.
    public static let version =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0-dev"

    public let store: Store
    public let engine: FlowEngine
    public let runs: RunService
    public let approvals: ApprovalService
    public let scheduler: Scheduler
    public let fileWatch: FileWatchHub
    public let token: String
    public let configuredPort: UInt16
    private var router: Router? = nil
    private var currentServer: MiniHTTPServer? = nil

    init(
        store: Store, engine: FlowEngine, runs: RunService, approvals: ApprovalService,
        scheduler: Scheduler, fileWatch: FileWatchHub, token: String, port: UInt16
    ) {
        self.store = store
        self.engine = engine
        self.runs = runs
        self.approvals = approvals
        self.scheduler = scheduler
        self.fileWatch = fileWatch
        self.token = token
        self.configuredPort = port
    }

    public static func bootstrap() async throws -> DaemonApp {
        try TBPaths.ensureHome()
        let store = try Store(path: TBPaths.databaseURL.path)

        var token = ProcessInfo.processInfo.environment["TIMINGBOMB_TOKEN"]
        if token == nil || token?.isEmpty == true {
            token = try await store.setting("apiToken")
        }
        let resolvedToken: String
        if let token, !token.isEmpty {
            writeTokenFile(token)
            resolvedToken = token
        } else {
            let generated = generateToken()
            try await store.setSetting("apiToken", generated)
            writeTokenFile(generated)
            resolvedToken = generated
        }

        let notifier = OsascriptNotifier()
        let allowlistProvider: @Sendable () async -> Allowlist = { await store.allowlist() }
        let actions = BuiltinActions(
            allowlistProvider: allowlistProvider,
            notifier: notifier)
        let engine = FlowEngine(
            runner: JSRunner(allowlistProvider: allowlistProvider),
            actions: actions,
            scripts: SubprocessScriptRunner(),
            approvalSink: { request in
                let record = ApprovalRecord(
                    id: UUID().uuidString.lowercased(),
                    runId: request.runId, flowId: request.flowId, flowName: request.flowName,
                    nodeId: request.nodeId, nodeName: request.nodeName, message: request.message)
                try await store.insertApproval(record)
                await notifier.notify(
                    title: L10n.t(
                        "TimingBomb · {name} is waiting for approval", ["name": request.flowName]),
                    body: request.message ?? L10n.t("Open the Approvals page to handle it"))
                return record.id
            })
        let runs = RunService(store: store, engine: engine, notifier: notifier)
        let approvalsService = ApprovalService(store: store, runs: runs, notifier: notifier)
        let scheduler = Scheduler(store: store, runs: runs)
        let fileWatch = FileWatchHub(store: store, runs: runs)
        return DaemonApp(
            store: store, engine: engine, runs: runs, approvals: approvalsService,
            scheduler: scheduler,
            fileWatch: fileWatch, token: resolvedToken, port: TBPaths.defaultPort)
    }

    // MARK: Lifecycle

    public func start() async throws {
        let server = try await startServer()

        await scheduler.start()
        await fileWatch.reload()

        let flowCount = (try? await store.listFlows().count) ?? 0
        let lanAccess = await store.lanAccessEnabled()
        print(
            L10n.t(
                "TimingBomb v{version} — listening on http://{host}:{port}",
                [
                    "version": Self.version,
                    "host": lanAccess ? "0.0.0.0" : "127.0.0.1",
                    "port": String(server.port),
                ]))
        if lanAccess {
            print(
                L10n.t(
                    "LAN access enabled — the API is reachable from the local network (token still required)"
                ))
        }
        print(
            L10n.t(
                "data dir: {path} ({count} flow(s) registered)",
                ["path": TBPaths.homeDir.path, "count": String(flowCount)]))

        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
        }
    }

    /// Starts the HTTP server and returns it (does not block). Used by `start()`, tests,
    /// and the LAN-access toggle (which restarts the listener on the new bind address).
    @discardableResult
    public func startServer() async throws -> MiniHTTPServer {
        let router = buildRouter()
        self.router = router

        let allowLAN = await store.lanAccessEnabled()
        let server = try MiniHTTPServer(port: configuredPort, allowLAN: allowLAN) { [weak self] request in
            guard let self else { return .error(500, code: "daemonShuttingDown", template: "daemon is shutting down") }
            return await self.handle(request)
        }
        try await server.start()
        currentServer = server
        return server
    }

    /// Rebinds the listener after the LAN-access flag changed: the old server is
    /// stopped first (same port), with a short grace so the socket fully closes.
    /// On failure the previous flag is restored so the API stays reachable.
    public func restartServer(previousLAN: Bool? = nil) async throws {
        let old = currentServer
        old?.stop()
        if old != nil {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        do {
            _ = try await startServer()
        } catch {
            if let previousLAN {
                try? await store.setSetting("lanAccess", previousLAN ? "true" : "false")
                _ = try? await startServer()
            }
            throw error
        }
    }

    // MARK: Request handling

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        if request.path != "/healthz" && !isAuthorized(request) {
            return .error(
                401, code: "unauthorized", template: "unauthorized: missing or invalid token")
        }
        guard let router else { return .error(500, code: "daemonNotReady", template: "daemon is not ready") }
        return await router.handle(request)
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        guard let header = request.headers["authorization"] else { return false }
        return header == "Bearer \(token)"
    }

    // MARK: Routes

    private func buildRouter() -> Router {
        let router = Router()

        router.add("GET", "healthz") { _ in
            .json(HealthResponse(status: "ok", version: Self.version))
        }

        router.add("GET", "flows") { [weak self] _ in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let metas = try await self.store.listFlows()
                return .json(FlowListResponse(flows: metas))
            }
        }

        router.add("POST", "flows") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let flow = try Self.decodeBody(FlowDefinition.self, request)
                let issues = FlowValidator.validate(flow, knownActions: self.engine.actions.knownActions)
                let errors = issues.filter { $0.level == .error }
                if !errors.isEmpty {
                    return .error(
                        400, code: "flowValidationFailed",
                        template: "flow validation failed ({count} error(s))",
                        params: ["count": String(errors.count)], issues: issues)
                }
                let meta = try await self.store.upsertFlow(flow)
                await self.fileWatch.reload()
                return .json(
                    FlowItemResponse(flow: meta.flow, createdAt: meta.createdAt, updatedAt: meta.updatedAt))
            }
        }

        router.add("GET", "flows/:id") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                guard let id = request.parameters["id"],
                    let meta = try await self.store.flowMeta(id: id)
                else { return .error(404, code: "flowNotFound", template: "flow not found") }
                return .json(
                    FlowItemResponse(flow: meta.flow, createdAt: meta.createdAt, updatedAt: meta.updatedAt))
            }
        }

        router.add("DELETE", "flows/:id") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                guard let id = request.parameters["id"], try await self.store.deleteFlow(id: id) else {
                    return .error(404, code: "flowNotFound", template: "flow not found")
                }
                await self.fileWatch.reload()
                return .json(OKResponse())
            }
        }

        router.add("GET", "allows") { [weak self] _ in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let list = await self.store.allowlist()
                return .json(
                    JSONValue.object(["patterns": .array(list.patterns.map { .string($0) })]))
            }
        }

        router.add("PUT", "allows") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let body = try Self.decodeBody(JSONValue.self, request)
                let patterns: [String]
                if case .array(let items) = body {
                    patterns = items.compactMap(\.stringValue)
                } else if case .object(let object) = body,
                    case .array(let items)? = object["patterns"]
                {
                    patterns = items.compactMap(\.stringValue)
                } else {
                    throw TBError.invalidRequest("body must be [pattern] or {\"patterns\": [...]}")
                }
                try await self.store.saveAllowlist(Allowlist(patterns: patterns))
                return .json(
                    JSONValue.object(["patterns": .array(patterns.map { .string($0) })]))
            }
        }

        router.add("POST", "validate") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let flow = try Self.decodeBody(FlowDefinition.self, request)
                let issues = FlowValidator.validate(flow, knownActions: self.engine.actions.knownActions)
                return .json(
                    ValidateResponse(valid: !issues.contains { $0.level == .error }, issues: issues))
            }
        }

        let runHandler: @Sendable (DaemonApp, HTTPRequest, String) async -> HTTPResponse = {
            app, request, triggerType in
            await app.responding {
                guard let flowId = request.parameters["id"], let flow = try await app.store.flow(id: flowId)
                else { return .error(404, code: "flowNotFound", template: "flow not found") }
                let payload = Self.extractPayload(request)
                let dryRun = ["1", "true"].contains(request.query["dryRun"] ?? "")
                let runId = try await app.runs.start(
                    flow: flow, trigger: TriggerInfo(type: triggerType, payload: payload),
                    dryRun: dryRun)
                if request.query["wait"] == "1" || request.query["wait"] == "true" {
                    guard let record = await app.runs.wait(runId: runId) else {
                        return .error(
                            500, code: "runNoRecord", template: "run {runId} produced no record",
                            params: ["runId": runId])
                    }
                    return .json(RunResponse(run: record))
                }
                return .json(RunStartedResponse(runId: runId, status: dryRun ? "dry-running" : "running"))
            }
        }

        router.add("POST", "flows/:id/run") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await runHandler(self, request, "manual")
        }

        router.add("POST", "hooks/:id") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await runHandler(self, request, "webhook")
        }

        router.add("GET", "runs") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let flowId = request.query["flowId"]
                let limit = Int(request.query["limit"] ?? "50") ?? 50
                let records = try await self.store.listRuns(flowId: flowId, limit: min(max(limit, 1), 500))
                return .json(RunListResponse(runs: records))
            }
        }

        router.add("GET", "runs/:id") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                guard let id = request.parameters["id"] else { return .error(400, code: "missingParam", template: "missing {name}", params: ["name": "run id"]) }
                if let record = await self.runs.wait(runId: id) {
                    return .json(RunResponse(run: record))
                }
                guard let record = try await self.store.run(id: id) else {
                    return .error(404, code: "runNotFound", template: "run not found")
                }
                return .json(RunResponse(run: record))
            }
        }

        router.add("DELETE", "runs/:id") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                guard let id = request.parameters["id"] else { return .error(400, code: "missingParam", template: "missing {name}", params: ["name": "run id"]) }
                try await self.runs.deleteRun(id: id)
                return .json(OKResponse())
            }
        }

        router.add("DELETE", "runs") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let flowId = request.query["flowId"].flatMap { $0.isEmpty ? nil : $0 }
                let deleted = try await self.runs.deleteRuns(flowId: flowId)
                return .json(JSONValue.object(["deleted": .int(Int64(deleted))]))
            }
        }

        router.add("GET", "approvals") { [weak self] _ in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let records = try await self.store.listApprovals()
                return .json(
                    JSONValue.object([
                        "approvals": .array(records.map { Self.approvalJSON($0) })
                    ]))
            }
        }

        router.add("POST", "approvals/:id/approve") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                guard let id = request.parameters["id"] else { return .error(400, code: "missingParam", template: "missing {name}", params: ["name": "id"]) }
                let comment = Self.stringBody(request, key: "comment")
                let record = try await self.approvals.decide(
                    approvalId: id, decision: .approve, comment: comment)
                return .json(
                    JSONValue.object(["approval": Self.approvalJSON(record)]))
            }
        }

        router.add("POST", "approvals/:id/reject") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                guard let id = request.parameters["id"] else { return .error(400, code: "missingParam", template: "missing {name}", params: ["name": "id"]) }
                let comment = Self.stringBody(request, key: "comment")
                let record = try await self.approvals.decide(
                    approvalId: id, decision: .reject, comment: comment)
                return .json(
                    JSONValue.object(["approval": Self.approvalJSON(record)]))
            }
        }

        router.add("DELETE", "approvals/:id") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                guard let id = request.parameters["id"] else { return .error(400, code: "missingParam", template: "missing {name}", params: ["name": "id"]) }
                guard let record = try await self.store.approval(id: id) else {
                    return .error(404, code: "approvalNotFound", template: "approval not found")
                }
                guard !record.isPending else {
                    return .error(
                        400, code: "pendingApprovalNotDeletable",
                        template: "pending approval cannot be deleted; handle it first")
                }
                _ = try await self.store.deleteApproval(id: id)
                return .json(OKResponse())
            }
        }

        router.add("DELETE", "approvals") { [weak self] _ in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let deleted = try await self.store.deleteDecidedApprovals()
                return .json(JSONValue.object(["deleted": .int(Int64(deleted))]))
            }
        }

        router.add("GET", "settings") { [weak self] _ in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let logging = await self.store.loggingEnabled()
                let lanAccess = await self.store.lanAccessEnabled()
                return .json(
                    JSONValue.object([
                        "loggingEnabled": .bool(logging),
                        "lanAccess": .bool(lanAccess),
                    ]))
            }
        }

        router.add("PUT", "settings") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                let body = try Self.decodeBody(JSONValue.self, request)
                if let value = body["loggingEnabled"] {
                    guard let enabled = value.boolValue else {
                        throw TBError.invalidRequest("loggingEnabled must be a boolean")
                    }
                    try await self.store.setSetting("loggingEnabled", enabled ? "true" : "false")
                }
                if let value = body["lanAccess"] {
                    guard let enabled = value.boolValue else {
                        throw TBError.invalidRequest("lanAccess must be a boolean")
                    }
                    let previousLAN = await self.store.lanAccessEnabled()
                    try await self.store.setSetting("lanAccess", enabled ? "true" : "false")
                    do {
                        try await self.restartServer(previousLAN: previousLAN)
                    } catch {
                        throw TBError.internalError(
                            "failed to rebind the listener: \(error.localizedDescription)")
                    }
                }
                let logging = await self.store.loggingEnabled()
                let lanAccess = await self.store.lanAccessEnabled()
                return .json(
                    JSONValue.object([
                        "loggingEnabled": .bool(logging),
                        "lanAccess": .bool(lanAccess),
                    ]))
            }
        }

        router.add("POST", "runs/:id/cancel") { [weak self] request in
            guard let self else { return .error(500, code: "daemonUnavailable", template: "daemon unavailable") }
            return await self.responding {
                guard let id = request.parameters["id"] else { return .error(400, code: "missingParam", template: "missing {name}", params: ["name": "run id"]) }
                // Unknown runs are indistinguishable from already-finished ones; ok either way.
                _ = await self.runs.cancel(runId: id)
                return .json(OKResponse())
            }
        }

        return router
    }

    // MARK: Helpers

    private func responding(_ block: () async throws -> HTTPResponse) async -> HTTPResponse {
        do {
            return try await block()
        } catch let error as TBApiError {
            return .error(error.status, code: error.code, template: error.template,
                          params: error.params, issues: error.issues)
        } catch let error as TBError {
            let api = error.api
            return .error(api.status, code: api.code, template: api.template,
                          params: api.params, issues: api.issues)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            if message.contains("Decoder") || message.contains("keyNotFound")
                || message.contains("typeMismatch") || message.contains("dataCorrupted")
            {
                return .error(
                    400, code: "invalidJSONBody", template: "invalid JSON body: {detail}",
                    params: ["detail": message])
            }
            return .error(
                500, code: "internalError", template: "internal error: {message}",
                params: ["message": message])
        }
    }

    static func decodeBody<T: Decodable>(_ type: T.Type, _ request: HTTPRequest) throws -> T {
        guard !request.body.isEmpty else {
            throw TBError.invalidRequest("request body is empty")
        }
        do {
            return try TBJSON.decodeData(type, from: request.body)
        } catch {
            throw TBError.invalidRequest("invalid JSON body: \(String(decoding: request.body.prefix(500), as: UTF8.self)) — \(error.localizedDescription)")
        }
    }

    static func approvalJSON(_ record: ApprovalRecord) -> JSONValue {
        .object([
            "id": .string(record.id),
            "runId": .string(record.runId),
            "flowId": .string(record.flowId),
            "flowName": .string(record.flowName),
            "nodeId": .string(record.nodeId),
            "nodeName": record.nodeName.map { .string($0) } ?? .null,
            "message": record.message.map { .string($0) } ?? .null,
            "status": .string(record.status),
            "comment": record.comment.map { .string($0) } ?? .null,
            "createdAt": .double(record.createdAt.timeIntervalSince1970),
            "decidedAt": record.decidedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
        ])
    }

    static func stringBody(_ request: HTTPRequest, key: String) -> String? {
        guard !request.body.isEmpty,
            let value = try? TBJSON.decodeData(JSONValue.self, from: request.body)
        else { return nil }
        guard case .object(let object) = value, let text = object[key]?.stringValue else {
            return nil
        }
        return text.isEmpty ? nil : text
    }

    /// Body is `{"payload": <value>}` or the raw value itself; empty body → nil.
    static func extractPayload(_ request: HTTPRequest) -> JSONValue? {
        guard !request.body.isEmpty else { return nil }
        guard let value = try? TBJSON.decodeData(JSONValue.self, from: request.body) else { return nil }
        if case .object(let object) = value, let payload = object["payload"], object.count == 1 {
            return payload
        }
        return value
    }

    // MARK: Token

    private static func writeTokenFile(_ token: String) {
        let url = TBPaths.tokenFileURL
        let data = Data(token.utf8)
        if FileManager.default.createFile(atPath: url.path, contents: data, attributes: [
            .posixPermissions: 0o600
        ]) {
            return
        }
        try? data.write(to: url)
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        if status != errSecSuccess {
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: 0...255)
            }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
