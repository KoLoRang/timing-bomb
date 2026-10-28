import Foundation
import TimingBombCore
import TimingBombL10n

// MARK: - DTOs

struct FlowItemDTO: Decodable, Identifiable {
    let flow: FlowDefinition
    let createdAt: Date
    let updatedAt: Date

    var id: String { flow.id }
}

struct FlowListDTO: Decodable {
    let flows: [FlowItemDTO]
}

struct RunListDTO: Decodable {
    let runs: [RunRecord]
}

struct RunDTO: Decodable {
    let run: RunRecord
}

struct RunStartedDTO: Decodable {
    let runId: String
    let status: String
}

struct APIClientError: Error {
    /// Daemon-locale rendering from the wire (`error` field); used as fallback.
    let message: String
    /// Stable machine code from the wire, when present.
    let code: String?
    /// English template with `{name}` placeholders, when present.
    let template: String?
    let params: [String: String]
    let issues: [ValidationIssue]

    init(
        message: String, code: String? = nil, template: String? = nil,
        params: [String: String] = [:], issues: [ValidationIssue] = []
    ) {
        self.message = message
        self.code = code
        self.template = template
        self.params = params
        self.issues = issues
    }

    /// Renders the error in this client's locale: server templates are
    /// re-rendered locally; plain messages are shown as-is.
    var rendered: String {
        L10n.renderError(template: template, params: params, fallback: message)
    }
}

// MARK: - Client

/// Client that talks to the local daemon (127.0.0.1); called directly by views.
enum TBAPIClient {
    static var baseURL: URL {
        URL(string: "http://127.0.0.1:\(TBPaths.defaultPort)")!
    }

    static var token: String {
        (try? String(contentsOf: TBPaths.tokenFileURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func request(
        _ method: String, _ path: String, body: Data? = nil, query: [String: String] = [:]
    ) async throws -> Data {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw decodeError(data, status: status)
            }
            return data
        } catch let error as APIClientError {
            throw error
        } catch let error as URLError
        where [.cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost]
            .contains(error.code)
        {
            throw APIClientError(
                message: L10n.t(
                    "cannot connect to daemon ({url}). Start it first: tb serve",
                    ["url": baseURL.absoluteString]),
                code: "daemonUnreachable",
                template: "cannot connect to daemon ({url}). Start it first: tb serve",
                params: ["url": baseURL.absoluteString])
        }
    }

    private static func decodeError(_ data: Data, status: Int) -> APIClientError {
        struct Body: Decodable {
            let error: String?
            let code: String?
            let template: String?
            let params: [String: String]?
            let issues: [ValidationIssue]?
        }
        let body = try? TBJSON.decodeData(Body.self, from: data)
        return APIClientError(
            message: body?.error ?? "HTTP \(status)",
            code: body?.code,
            template: body?.template,
            params: body?.params ?? [:],
            issues: body?.issues ?? [])
    }

    // MARK: Endpoints

    static func health() async throws -> String? {
        let data = try await request("GET", "healthz")
        let value = try? TBJSON.decodeData(JSONValue.self, from: data)
        guard value?["status"]?.stringValue == "ok" else { return nil }
        return value?["version"]?.stringValue
    }

    static func flows() async throws -> [FlowItemDTO] {
        let data = try await request("GET", "flows")
        return try TBJSON.decodeData(FlowListDTO.self, from: data).flows
    }

    @discardableResult
    static func saveFlow(_ flow: FlowDefinition) async throws -> FlowItemDTO {
        let body = try TBJSON.encodeData(flow)
        let data = try await request("POST", "flows", body: body)
        return try TBJSON.decodeData(FlowItemDTO.self, from: data)
    }

    static func deleteFlow(id: String) async throws {
        _ = try await request("DELETE", "flows/\(id)")
    }

    static func startRun(
        flowId: String, payload: JSONValue?, dryRun: Bool = false
    ) async throws -> String {
        let body = try TBJSON.encodeData(["payload": payload ?? .null])
        let query = dryRun ? ["dryRun": "1"] : [:]
        let data = try await request("POST", "flows/\(flowId)/run", body: body, query: query)
        return try TBJSON.decodeData(RunStartedDTO.self, from: data).runId
    }

    static func allowlist() async throws -> [String] {
        let data = try await request("GET", "allows")
        let value = try TBJSON.decodeData(JSONValue.self, from: data)
        guard case .array(let items)? = value["patterns"] else { return [] }
        return items.compactMap(\.stringValue)
    }

    static func saveAllowlist(_ patterns: [String]) async throws {
        let body = try TBJSON.encodeData(JSONValue.array(patterns.map { .string($0) }))
        _ = try await request("PUT", "allows", body: body)
    }

    static func loggingEnabled() async throws -> Bool {
        let data = try await request("GET", "settings")
        let value = try TBJSON.decodeData(JSONValue.self, from: data)
        return value["loggingEnabled"]?.boolValue ?? true
    }

    static func setLoggingEnabled(_ enabled: Bool) async throws {
        let body = try TBJSON.encodeData(
            JSONValue.object(["loggingEnabled": .bool(enabled)]))
        _ = try await request("PUT", "settings", body: body)
    }

    static func lanAccessEnabled() async throws -> Bool {
        let data = try await request("GET", "settings")
        let value = try TBJSON.decodeData(JSONValue.self, from: data)
        return value["lanAccess"]?.boolValue ?? false
    }

    static func setLanAccess(_ enabled: Bool) async throws {
        let body = try TBJSON.encodeData(
            JSONValue.object(["lanAccess": .bool(enabled)]))
        _ = try await request("PUT", "settings", body: body)
    }

    static func approvals() async throws -> [ApprovalRecord] {
        let data = try await request("GET", "approvals")
        let value = try TBJSON.decodeData(JSONValue.self, from: data)
        guard case .array(let items)? = value["approvals"] else { return [] }
        return items.compactMap { item in
            guard case .object = item else { return nil }
            return try? TBJSON.decodeData(
                ApprovalRecord.self, from: TBJSON.encodeData(item))
        }
    }

    @discardableResult
    static func decideApproval(id: String, approve: Bool, comment: String?) async throws
        -> ApprovalRecord
    {
        var body: JSONValue = .object([:])
        if let comment {
            body = .object(["comment": .string(comment)])
        }
        let data = try await request(
            "POST", "approvals/\(id)/\(approve ? "approve" : "reject")",
            body: try TBJSON.encodeData(body))
        let value = try TBJSON.decodeData(JSONValue.self, from: data)
        guard case .object(let object)? = value["approval"],
            let record = try? TBJSON.decodeData(
                ApprovalRecord.self, from: TBJSON.encodeData(JSONValue.object(object)))
        else {
            throw APIClientError(
                message: L10n.t("failed to decode approval response"),
                code: "approvalResponseDecodeFailed",
                template: "failed to decode approval response")
        }
        return record
    }

    static func deleteApproval(id: String) async throws {
        _ = try await request("DELETE", "approvals/\(id)")
    }

    static func clearApprovalHistory() async throws -> Int {
        let data = try await request("DELETE", "approvals")
        let value = try TBJSON.decodeData(JSONValue.self, from: data)
        return value["deleted"]?.intValue.map(Int.init) ?? 0
    }

    static func deleteRun(id: String) async throws {
        _ = try await request("DELETE", "runs/\(id)")
    }

    /// Deletes run records of the given flow (nil = all); returns the number deleted.
    static func deleteRuns(flowId: String?) async throws -> Int {
        let query = flowId.map { ["flowId": $0] } ?? [:]
        let data = try await request("DELETE", "runs", query: query)
        let value = try TBJSON.decodeData(JSONValue.self, from: data)
        return value["deleted"]?.intValue.map(Int.init) ?? 0
    }

    static func runs(flowId: String? = nil, limit: Int = 50) async throws -> [RunRecord] {
        var query = ["limit": String(limit)]
        if let flowId { query["flowId"] = flowId }
        let data = try await request("GET", "runs", query: query)
        return try TBJSON.decodeData(RunListDTO.self, from: data).runs
    }

    static func run(id: String) async throws -> RunRecord? {
        let data = try await request("GET", "runs/\(id)")
        return try TBJSON.decodeData(RunDTO.self, from: data).run
    }
}

// MARK: - Shared presentation helpers

extension RunRecord: Identifiable {}

enum Presentation {
    static func triggerName(_ type: String) -> String {
        switch type {
        case "manual": return L10n.t("Manual trigger")
        case "webhook": return L10n.t("Webhook trigger")
        case "schedule": return L10n.t("Scheduled trigger")
        case "fileWatch": return L10n.t("File watch trigger")
        case "dry-run": return L10n.t("Dry-run")
        default: return type
        }
    }

    static func triggerBadge(_ flow: FlowDefinition) -> (text: String, detail: String?) {
        guard let trigger = flow.trigger else { return (L10n.t("Manual trigger"), nil) }
        switch trigger.type ?? .manual {
        case .schedule:
            return (L10n.t("Scheduled trigger"), trigger.cron ?? nil)
        case .webhook:
            return (L10n.t("Webhook trigger"), "/hooks/\(flow.id)")
        case .fileWatch:
            return (
                L10n.t("File watch trigger"),
                trigger.path.map { ($0 as NSString).lastPathComponent }
            )
        case .manual:
            return (L10n.t("Manual trigger"), nil)
        }
    }

    static func prettyJSON(_ value: JSONValue) -> String {
        (try? TBJSON.prettyEncoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
            ?? value.displayString
    }

    static func format(durationMs: Double?) -> String {
        guard let durationMs else { return "-" }
        if durationMs < 1000 { return String(format: "%.0fms", durationMs) }
        return String(format: "%.1fs", durationMs / 1000)
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()
}

// MARK: - Node tree helpers

enum FlowTree {
    static func find(in nodes: [FlowNode], id: String) -> FlowNode? {
        for node in nodes {
            if node.id == id { return node }
            for child in childBlocks(of: node) {
                if let found = find(in: child, id: id) { return found }
            }
        }
        return nil
    }

    static func replace(in nodes: inout [FlowNode], id: String, with updated: FlowNode) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == id {
                nodes[index] = updated
                return true
            }
            if var thenNodes = nodes[index].thenNodes,
                replace(in: &thenNodes, id: id, with: updated)
            {
                nodes[index].thenNodes = thenNodes
                return true
            }
            if var elseNodes = nodes[index].elseNodes,
                replace(in: &elseNodes, id: id, with: updated)
            {
                nodes[index].elseNodes = elseNodes
                return true
            }
            if var body = nodes[index].body, replace(in: &body, id: id, with: updated) {
                nodes[index].body = body
                return true
            }
        }
        return false
    }

    static func childBlocks(of node: FlowNode) -> [[FlowNode]] {
        var blocks: [[FlowNode]] = []
        if let thenNodes = node.thenNodes { blocks.append(thenNodes) }
        if let elseNodes = node.elseNodes { blocks.append(elseNodes) }
        if let body = node.body { blocks.append(body) }
        return blocks
    }
}
