import Foundation

// MARK: - Flow definition

public enum NodeType: String, Codable, Sendable, Equatable {
    case code
    case ifNode = "if"
    case loop
    case action
    case approval
}

public enum OnErrorPolicy: String, Codable, Sendable, Equatable {
    case abort
    case continueOn = "continue"
}

public enum LoopMode: String, Codable, Sendable, Equatable {
    case count
    case forEach
    case whileLoop = "while"
}

public enum TriggerType: String, Codable, Sendable, Equatable {
    case manual
    case schedule
    case webhook
    case fileWatch = "fileWatch"
}

public struct TriggerConfig: Codable, Equatable, Sendable {
    public var type: TriggerType?
    public var cron: String?
    public var timezone: String?
    /// "skip" | "fireOnce"
    public var misfire: String?
    /// fileWatch trigger: the watched directory (~ supported)
    public var path: String?

    public init(
        type: TriggerType? = nil, cron: String? = nil,
        timezone: String? = nil, misfire: String? = nil, path: String? = nil
    ) {
        self.type = type
        self.cron = cron
        self.timezone = timezone
        self.misfire = misfire
        self.path = path
    }
}

/// A flow node. The struct is intentionally flat and permissive: per-type
/// required fields are enforced by `FlowValidator`, not by decoding.
public struct FlowNode: Codable, Equatable, Sendable {
    public var id: String
    public var type: NodeType
    public var name: String?
    public var timeoutMs: Int?
    public var onError: OnErrorPolicy?
    public var retries: Int?
    /// Condition expression/body; node is skipped when it evaluates to false.
    public var skipIf: String?

    // code node
    /// "js" (default) | "python" | "shell" — non-JS runs via a system interpreter subprocess
    public var language: String?
    public var code: String?

    // if node
    public var condition: String?
    public var thenNodes: [FlowNode]?
    public var elseNodes: [FlowNode]?

    // loop node
    public var mode: LoopMode?
    /// Template or literal: iteration count (count mode) or array source (forEach).
    public var over: String?
    public var concurrency: Int?
    public var maxIterations: Int?
    public var body: [FlowNode]?

    // action node
    public var action: String?
    public var params: JSONValue?

    // approval node: explanation shown to the approver
    public var message: String?

    public init(
        id: String,
        type: NodeType,
        name: String? = nil,
        timeoutMs: Int? = nil,
        onError: OnErrorPolicy? = nil,
        retries: Int? = nil,
        skipIf: String? = nil,
        language: String? = nil,
        code: String? = nil,
        condition: String? = nil,
        thenNodes: [FlowNode]? = nil,
        elseNodes: [FlowNode]? = nil,
        mode: LoopMode? = nil,
        over: String? = nil,
        concurrency: Int? = nil,
        maxIterations: Int? = nil,
        body: [FlowNode]? = nil,
        action: String? = nil,
        params: JSONValue? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.timeoutMs = timeoutMs
        self.onError = onError
        self.retries = retries
        self.skipIf = skipIf
        self.language = language
        self.code = code
        self.condition = condition
        self.thenNodes = thenNodes
        self.elseNodes = elseNodes
        self.mode = mode
        self.over = over
        self.concurrency = concurrency
        self.maxIterations = maxIterations
        self.body = body
        self.action = action
        self.params = params
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, timeoutMs, onError, retries, skipIf
        case language, code, condition
        case thenNodes = "then", elseNodes = "else"
        case mode, over, concurrency, maxIterations, body
        case action, params, message
    }
}

public struct FlowDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: Int?
    public var description: String?
    public var trigger: TriggerConfig?
    /// Whether to send a system notification on run failure/timeout (default true)
    public var notifyOnFailure: Bool?
    public var nodes: [FlowNode]

    public init(
        id: String, name: String, version: Int? = nil, description: String? = nil,
        trigger: TriggerConfig? = nil, notifyOnFailure: Bool? = nil, nodes: [FlowNode] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.trigger = trigger
        self.notifyOnFailure = notifyOnFailure
        self.nodes = nodes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        version = try c.decodeIfPresent(Int.self, forKey: .version)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        trigger = try c.decodeIfPresent(TriggerConfig.self, forKey: .trigger)
        notifyOnFailure = try c.decodeIfPresent(Bool.self, forKey: .notifyOnFailure)
        nodes = try c.decodeIfPresent([FlowNode].self, forKey: .nodes) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(trigger, forKey: .trigger)
        try c.encodeIfPresent(notifyOnFailure, forKey: .notifyOnFailure)
        try c.encode(nodes, forKey: .nodes)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, version, description, trigger, notifyOnFailure, nodes
    }
}

// MARK: - Run records

public enum RunStatus: String, Codable, Sendable, Equatable {
    case pending, running, success, failed, cancelled, timeout
    case awaitingApproval = "awaitingApproval"
}

public enum NodeRunStatus: String, Codable, Sendable, Equatable {
    case success, failed, skipped, timeout, cancelled
}

public struct TriggerInfo: Codable, Sendable, Equatable {
    public var type: String
    public var payload: JSONValue?

    public init(type: String, payload: JSONValue? = nil) {
        self.type = type
        self.payload = payload
    }
}

public struct NodeRunRecord: Codable, Sendable, Equatable {
    public var id: String
    public var nodeId: String
    public var nodeType: String
    public var iteration: Int?
    public var status: NodeRunStatus
    public var startedAt: Date
    public var endedAt: Date?
    /// Input snapshot taken when the node starts executing (code/if/loop/approval = the context at that moment; action = the rendered params)
    public var input: JSONValue?
    public var output: JSONValue?
    public var error: String?
    public var logs: [String]

    public init(
        id: String, nodeId: String, nodeType: String, iteration: Int?,
        status: NodeRunStatus, startedAt: Date, endedAt: Date? = nil,
        input: JSONValue? = nil, output: JSONValue? = nil, error: String? = nil,
        logs: [String] = []
    ) {
        self.id = id
        self.nodeId = nodeId
        self.nodeType = nodeType
        self.iteration = iteration
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.input = input
        self.output = output
        self.error = error
        self.logs = logs
    }
}

public struct RunRecord: Codable, Sendable, Equatable {
    public var id: String
    public var flowId: String
    public var flowName: String
    public var status: RunStatus
    public var trigger: TriggerInfo
    public var startedAt: Date
    public var endedAt: Date?
    public var error: String?
    public var context: JSONValue?
    public var nodeRuns: [NodeRunRecord]
    /// While suspended awaiting approval, the approval node's index path (used to resume execution)
    public var resumePath: [Int]?

    public init(
        id: String, flowId: String, flowName: String, status: RunStatus,
        trigger: TriggerInfo, startedAt: Date, endedAt: Date? = nil,
        error: String? = nil, context: JSONValue? = nil, nodeRuns: [NodeRunRecord] = [],
        resumePath: [Int]? = nil
    ) {
        self.id = id
        self.flowId = flowId
        self.flowName = flowName
        self.status = status
        self.trigger = trigger
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.error = error
        self.context = context
        self.nodeRuns = nodeRuns
        self.resumePath = resumePath
    }
}
