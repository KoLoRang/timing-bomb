import Foundation
import GRDB

// MARK: - Rows

struct FlowRow: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "flows"
    var id: String
    var name: String
    var definitionJson: String
    var createdAt: Date
    var updatedAt: Date

    init(flow: FlowDefinition, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = flow.id
        self.name = flow.name
        let encoded = try? TBJSON.encode(flow)
        self.definitionJson = encoded ?? "{}"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var definition: FlowDefinition? {
        definitionJson.data(using: .utf8).flatMap { try? TBJSON.decodeData(FlowDefinition.self, from: $0) }
    }
}

struct RunRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "runs"
    var id: String
    var flowId: String
    var flowName: String
    var status: String
    var triggerJson: String
    var contextJson: String?
    var error: String?
    var startedAt: Date
    var endedAt: Date?
    var resumePathJson: String?
}

struct NodeRunRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "nodeRuns"
    var id: String
    var runId: String
    var nodeId: String
    var nodeType: String
    var iteration: Int?
    var status: String
    var startedAt: Date
    var endedAt: Date?
    var inputJson: String?
    var outputJson: String?
    var error: String?
    var logsJson: String
}

struct SettingRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "settings"
    var key: String
    var value: String
}

struct ApprovalRow: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "approvals"
    var id: String
    var runId: String
    var flowId: String
    var flowName: String
    var nodeId: String
    var nodeName: String?
    var message: String?
    var status: String
    var comment: String?
    var createdAt: Date
    var decidedAt: Date?
}

// MARK: - Store

public final class Store: Sendable {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try Self.migrate(dbQueue)
    }

    private static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "flows") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("definitionJson", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "runs") { t in
                t.column("id", .text).primaryKey()
                t.column("flowId", .text).notNull().indexed()
                t.column("flowName", .text).notNull()
                t.column("status", .text).notNull()
                t.column("triggerJson", .text).notNull()
                t.column("contextJson", .text)
                t.column("error", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
            }
            try db.create(table: "nodeRuns") { t in
                t.column("id", .text).primaryKey()
                t.column("runId", .text).notNull().indexed()
                t.column("nodeId", .text).notNull()
                t.column("nodeType", .text).notNull()
                t.column("iteration", .integer)
                t.column("status", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("outputJson", .text)
                t.column("error", .text)
                t.column("logsJson", .text).notNull()
            }
            try db.create(table: "settings") { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
            }
        }
        migrator.registerMigration("v2_approvals") { db in
            try db.create(table: "approvals") { t in
                t.column("id", .text).primaryKey()
                t.column("runId", .text).notNull().indexed()
                t.column("flowId", .text).notNull()
                t.column("flowName", .text).notNull()
                t.column("nodeId", .text).notNull()
                t.column("nodeName", .text)
                t.column("message", .text)
                t.column("status", .text).notNull()
                t.column("comment", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("decidedAt", .datetime)
            }
            try db.alter(table: "runs") { t in
                t.add(column: "resumePathJson", .text)
            }
        }
        migrator.registerMigration("v3_node_run_input") { db in
            try db.alter(table: "nodeRuns") { t in
                t.add(column: "inputJson", .text)
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: Flows

    public struct FlowMeta: Codable, Sendable {
        public var flow: FlowDefinition
        public var createdAt: Date
        public var updatedAt: Date
    }

    @discardableResult
    public func upsertFlow(_ flow: FlowDefinition) async throws -> FlowMeta {
        let now = Date()
        try await dbQueue.write { db in
            var row = FlowRow(flow: flow, updatedAt: now)
            if let existing = try FlowRow.fetchOne(
                db, sql: "SELECT * FROM flows WHERE id = ?", arguments: [flow.id])
            {
                row.createdAt = existing.createdAt
            }
            try row.save(db)
        }
        guard let meta = try await flowMeta(id: flow.id) else {
            throw TBError.internalError("flow \(flow.id) disappeared after save")
        }
        return meta
    }

    public func flowMeta(id: String) async throws -> FlowMeta? {
        try await dbQueue.read { db in
            guard let row = try FlowRow.fetchOne(
                db, sql: "SELECT * FROM flows WHERE id = ?", arguments: [id])
            else { return nil }
            guard let flow = row.definition else {
                throw TBError.internalError("stored flow '\(id)' is not decodable")
            }
            return FlowMeta(flow: flow, createdAt: row.createdAt, updatedAt: row.updatedAt)
        }
    }

    public func flow(id: String) async throws -> FlowDefinition? {
        try await flowMeta(id: id)?.flow
    }

    public func listFlows() async throws -> [FlowMeta] {
        try await dbQueue.read { db in
            let rows = try FlowRow.order(Column("name")).fetchAll(db)
            return rows.compactMap { row in
                row.definition.map {
                    FlowMeta(flow: $0, createdAt: row.createdAt, updatedAt: row.updatedAt)
                }
            }
        }
    }

    @discardableResult
    public func deleteFlow(id: String) async throws -> Bool {
        try await dbQueue.write { db in
            try FlowRow.deleteOne(db, key: id)
        }
    }

    // MARK: Runs

    public func saveRun(_ record: RunRecord) async throws {
        try await dbQueue.write { db in
            var row = RunRow(
                id: record.id, flowId: record.flowId, flowName: record.flowName,
                status: record.status.rawValue,
                triggerJson: (try? TBJSON.encode(record.trigger)) ?? "{}",
                contextJson: record.context.flatMap { try? TBJSON.encode($0) },
                error: record.error, startedAt: record.startedAt, endedAt: record.endedAt,
                resumePathJson: record.resumePath.flatMap {
                    (try? TBJSON.encode($0 as [Int]))
                })
            try row.save(db)
            try db.execute(
                sql: "DELETE FROM nodeRuns WHERE runId = ?", arguments: [record.id])
            for nodeRun in record.nodeRuns {
                var nodeRow = NodeRunRow(
                    id: nodeRun.id, runId: record.id, nodeId: nodeRun.nodeId,
                    nodeType: nodeRun.nodeType, iteration: nodeRun.iteration,
                    status: nodeRun.status.rawValue, startedAt: nodeRun.startedAt,
                    endedAt: nodeRun.endedAt,
                    inputJson: nodeRun.input.flatMap { try? TBJSON.encode($0) },
                    outputJson: nodeRun.output.flatMap { try? TBJSON.encode($0) },
                    error: nodeRun.error,
                    logsJson: (try? TBJSON.encode(nodeRun.logs)) ?? "[]"
                )
                try nodeRow.insert(db)
            }
        }
    }

    public func listRuns(flowId: String? = nil, limit: Int = 50) async throws -> [RunRecord] {
        try await dbQueue.read { db in
            var request = RunRow.order(Column("startedAt").desc).limit(limit)
            if let flowId {
                request = RunRow
                    .filter(Column("flowId") == flowId)
                    .order(Column("startedAt").desc).limit(limit)
            }
            let rows = try request.fetchAll(db)
            return rows.map(Self.runRecord(from:))
        }
    }

    public func run(id: String) async throws -> RunRecord? {
        try await dbQueue.read { db in
            guard let row = try RunRow.fetchOne(
                db, sql: "SELECT * FROM runs WHERE id = ?", arguments: [id])
            else { return nil }
            var record = Self.runRecord(from: row)
            let nodeRows = try NodeRunRow
                .filter(Column("runId") == id)
                .order(Column("startedAt"))
                .fetchAll(db)
            record.nodeRuns = nodeRows.map { nodeRow in
                NodeRunRecord(
                    id: nodeRow.id, nodeId: nodeRow.nodeId, nodeType: nodeRow.nodeType,
                    iteration: nodeRow.iteration,
                    status: NodeRunStatus(rawValue: nodeRow.status) ?? .failed,
                    startedAt: nodeRow.startedAt, endedAt: nodeRow.endedAt,
                    input: nodeRow.inputJson.flatMap {
                        $0.data(using: .utf8).flatMap { try? TBJSON.decodeData(JSONValue.self, from: $0) }
                    },
                    output: nodeRow.outputJson.flatMap {
                        $0.data(using: .utf8).flatMap { try? TBJSON.decodeData(JSONValue.self, from: $0) }
                    },
                    error: nodeRow.error,
                    logs: nodeRow.logsJson.data(using: .utf8).flatMap {
                        try? TBJSON.decodeData([String].self, from: $0)
                    } ?? [])
            }
            return record
        }
    }

    private static func runRecord(from row: RunRow) -> RunRecord {
        RunRecord(
            id: row.id, flowId: row.flowId, flowName: row.flowName,
            status: RunStatus(rawValue: row.status) ?? .failed,
            trigger: row.triggerJson.data(using: .utf8).flatMap {
                try? TBJSON.decodeData(TriggerInfo.self, from: $0)
            } ?? TriggerInfo(type: "unknown"),
            startedAt: row.startedAt, endedAt: row.endedAt, error: row.error,
            context: row.contextJson.flatMap {
                $0.data(using: .utf8).flatMap { try? TBJSON.decodeData(JSONValue.self, from: $0) }
            },
            nodeRuns: [],
            resumePath: row.resumePathJson.flatMap {
                $0.data(using: .utf8).flatMap { try? TBJSON.decodeData([Int].self, from: $0) }
            })
    }

    // MARK: Settings

    public func setting(_ key: String) async throws -> String? {
        try await dbQueue.read { db in
            try SettingRow.fetchOne(db, key: key)?.value
        }
    }

    public func setSetting(_ key: String, _ value: String) async throws {
        try await dbQueue.write { db in
            var row = SettingRow(key: key, value: value)
            try row.save(db)
        }
    }

    // MARK: Approvals

    public func insertApproval(_ record: ApprovalRecord) async throws {
        try await dbQueue.write { db in
            var row = ApprovalRow(
                id: record.id, runId: record.runId, flowId: record.flowId,
                flowName: record.flowName, nodeId: record.nodeId, nodeName: record.nodeName,
                message: record.message, status: record.status, comment: record.comment,
                createdAt: record.createdAt, decidedAt: record.decidedAt)
            try row.insert(db)
        }
    }

    public func approval(id: String) async throws -> ApprovalRecord? {
        try await dbQueue.read { db in
            try ApprovalRow.fetchOne(db, key: id).map(Self.approvalRecord(from:))
        }
    }

    /// Pending items first, then newest first
    public func listApprovals(limit: Int = 200) async throws -> [ApprovalRecord] {
        try await dbQueue.read { db in
            let rows = try ApprovalRow
                .order(sql: "CASE WHEN status = 'pending' THEN 0 ELSE 1 END, createdAt DESC")
                .limit(limit)
                .fetchAll(db)
            return rows.map(Self.approvalRecord)
        }
    }

    public func decideApproval(
        id: String, status: String, comment: String?
    ) async throws -> ApprovalRecord? {
        try await dbQueue.write { db in
            guard var row = try ApprovalRow.fetchOne(db, key: id) else { return nil }
            row.status = status
            row.comment = comment
            row.decidedAt = Date()
            try row.update(db)
            return Self.approvalRecord(from: row)
        }
    }

    @discardableResult
    public func deleteApproval(id: String) async throws -> Bool {
        try await dbQueue.write { db in
            try ApprovalRow.deleteOne(db, key: id)
        }
    }

    /// Clears all decided approvals (history); pending ones are kept. Returns the number deleted.
    public func deleteDecidedApprovals() async throws -> Int {
        try await dbQueue.write { db in
            try ApprovalRow.filter(Column("status") != "pending").deleteAll(db)
        }
    }

    private static func approvalRecord(from row: ApprovalRow) -> ApprovalRecord {
        ApprovalRecord(
            id: row.id, runId: row.runId, flowId: row.flowId, flowName: row.flowName,
            nodeId: row.nodeId, nodeName: row.nodeName, message: row.message,
            status: row.status, comment: row.comment, createdAt: row.createdAt,
            decidedAt: row.decidedAt)
    }

    /// Whether run history is recorded (on by default)
    public func loggingEnabled() async -> Bool {
        ((try? await setting("loggingEnabled")) ?? nil).map { $0 == "true" } ?? true
    }

    // MARK: Deleting run records

    @discardableResult
    public func deleteRun(id: String) async throws -> Bool {
        try await dbQueue.write { db in
            let deleted = try RunRow.deleteOne(db, key: id)
            try db.execute(sql: "DELETE FROM nodeRuns WHERE runId = ?", arguments: [id])
            return deleted
        }
    }

    /// Deletes run records of the given flow (all flows when flowId is nil); returns the number deleted.
    public func deleteRuns(flowId: String? = nil) async throws -> Int {
        try await dbQueue.write { db in
            let ids: [String]
            if let flowId {
                ids = try RunRow.filter(Column("flowId") == flowId)
                    .fetchAll(db).map(\.id)
            } else {
                ids = try RunRow.fetchAll(db).map(\.id)
            }
            guard !ids.isEmpty else { return 0 }
            _ = try RunRow.deleteAll(db, keys: ids)
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM nodeRuns WHERE runId IN (\(placeholders))",
                arguments: StatementArguments(ids))
            return ids.count
        }
    }
}
