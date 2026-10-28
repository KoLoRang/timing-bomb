import Foundation

// MARK: - Ports

public struct CodeOutcome: Sendable, Equatable {
    public var value: JSONValue
    public var logs: [String]

    public init(value: JSONValue, logs: [String] = []) {
        self.value = value
        self.logs = logs
    }
}

/// Executes code nodes / condition expressions. Production: JSRunner; tests: mocks.
public protocol CodeRunning: Sendable {
    /// Runs a code node source. `ctx` is the JSON view of the run context.
    func run(code: String, ctx: JSONValue, timeoutMs: Int, dryRun: Bool) async throws -> CodeOutcome
    /// Evaluates a condition (expression or body containing `return`) to a boolean.
    func evaluate(condition: String, ctx: JSONValue, timeoutMs: Int) async throws -> Bool
}

public extension CodeRunning {
    func run(code: String, ctx: JSONValue, timeoutMs: Int) async throws -> CodeOutcome {
        try await run(code: code, ctx: ctx, timeoutMs: timeoutMs, dryRun: false)
    }
}

/// Executes built-in action nodes.
public protocol ActionExecuting: Sendable {
    var knownActions: [String] { get }
    func execute(
        action: String, params: JSONValue, ctx: JSONValue, dryRun: Bool
    ) async throws -> JSONValue
}

// MARK: - Engine

public final class FlowEngine: Sendable {
    public struct Config: Sendable {
        public var defaultNodeTimeoutMs: Int = 60_000
        public var conditionTimeoutMs: Int = 5_000
        public var defaultRetries: Int = 0
        public var maxConcurrency: Int = 32
        public var defaultMaxIterations: Int = 1_000
        public var hardMaxIterations: Int = 100_000
        public var outputJsonBudget: Int = 256 * 1024
        /// Size cap for each node execution's input snapshot (clipped when exceeded, to keep loops from amplifying storage)
        public var inputJsonBudget: Int = 128 * 1024
        /// Dry-run mode: tools/actions produce no real side effects
        public var dryRun: Bool = false

        public init() {}
    }

    enum LoopSignal: Sendable {
        case breakLoop
        case continueLoop
    }

    public let runner: CodeRunning
    public let actions: ActionExecuting
    /// Executor for non-JS code nodes (python/shell); when nil, non-JS nodes fail outright
    public let scripts: ScriptRunning?
    /// Approval ticketing: the host persists/notifies and returns the approval id; when nil, approval nodes are unavailable
    public let approvalSink: ApprovalSink?
    public let config: Config

    public typealias ApprovalSink = @Sendable (ApprovalRequest) async throws -> String

    /// Info about the run currently executing (used for approval ticketing), passed via TaskLocal
    @TaskLocal static var runContext: (runId: String, flowId: String, flowName: String)?

    /// Information needed to resume from an approval-node checkpoint
    public struct ResumeInfo: Sendable {
        public let context: JSONValue
        /// Index path of the approval node (root array index → [node index, branch number, ...])
        public let path: [Int]
        public let priorNodeRuns: [NodeRunRecord]
        public let startedAt: Date

        public init(context: JSONValue, path: [Int], priorNodeRuns: [NodeRunRecord], startedAt: Date) {
            self.context = context
            self.path = path
            self.priorNodeRuns = priorNodeRuns
            self.startedAt = startedAt
        }
    }

    public init(
        runner: CodeRunning, actions: ActionExecuting, scripts: ScriptRunning? = nil,
        approvalSink: ApprovalSink? = nil, config: Config = Config()
    ) {
        self.runner = runner
        self.actions = actions
        self.scripts = scripts
        self.approvalSink = approvalSink
        self.config = config
    }

    // MARK: Entry

    public func execute(
        flow: FlowDefinition, runId: String, trigger: TriggerInfo,
        resume: ResumeInfo? = nil
    ) async -> RunRecord {
        var context = resume?.context
            ?? Self.initialContext(flow: flow, runId: runId, trigger: trigger)
        let collector = TimelineCollector(records: resume?.priorNodeRuns ?? [])
        let startedAt = resume?.startedAt ?? Date()

        var status = RunStatus.success
        var errorMessage: String? = nil
        var resumePath: [Int]? = nil

        do {
            try await Self.$runContext.withValue((runId, flow.id, flow.name)) {
                if let resume {
                    _ = try await resumeBlock(
                        flow.nodes, prefix: [], path: resume.path,
                        ctx: &context, collector: collector, depth: 0)
                } else {
                    _ = try await executeBlock(
                        flow.nodes, ctx: &context, collector: collector,
                        iteration: nil, depth: 0)
                }
            }
        } catch let pause as ApprovalPause {
            status = .awaitingApproval
            resumePath = pause.path
        } catch let error as TBError {
            switch error {
            case .timeout:
                status = .timeout
                errorMessage = error.errorDescription
            case .cancelled:
                status = .cancelled
                errorMessage = "run cancelled"
            case .nodeFailed(let nodeId, let message):
                status = .failed
                errorMessage = "node '\(nodeId)' failed: \(message)"
            default:
                status = .failed
                errorMessage = error.errorDescription ?? String(describing: error)
            }
        } catch {
            if Task.isCancelled || error is CancellationError {
                status = .cancelled
                errorMessage = "run cancelled"
            } else {
                status = .failed
                errorMessage = String(describing: error)
            }
        }

        context.remove(atPath: "loop")
        return RunRecord(
            id: runId,
            flowId: flow.id,
            flowName: flow.name,
            status: status,
            trigger: trigger,
            startedAt: startedAt,
            endedAt: status == .awaitingApproval ? nil : Date(),
            error: errorMessage,
            context: context.clipping(jsonBudget: config.outputJsonBudget),
            nodeRuns: collector.all,
            resumePath: resumePath
        )
    }

    public static func initialContext(flow: FlowDefinition, runId: String, trigger: TriggerInfo) -> JSONValue {
        .object([
            "config": .object([
                "flowId": .string(flow.id),
                "flowName": .string(flow.name),
                "runId": .string(runId),
            ]),
            "trigger": .object([
                "type": .string(trigger.type),
                "payload": trigger.payload ?? .null,
            ]),
            "nodes": .object([:]),
        ])
    }

    // MARK: Blocks

    /// Executes nodes in order. Returns a loop signal that must bubble to the nearest loop.
    /// `prefix` is the index-path prefix of the current block within the whole tree; `from` resumes from the siblings after a checkpoint.
    private func executeBlock(
        _ nodes: [FlowNode], ctx: inout JSONValue, collector: TimelineCollector,
        iteration: Int?, depth: Int, prefix: [Int] = [], from: Int = 0
    ) async throws -> LoopSignal? {
        for index in from..<nodes.count {
            if Task.isCancelled { throw TBError.cancelled }
            let node = nodes[index]
            if let signal = try await executeNode(
                node, ctx: &ctx, collector: collector, iteration: iteration, depth: depth,
                path: prefix + [index])
            {
                return signal
            }
        }
        return nil
    }

    /// Approval pause signal (internal error type used to carry the checkpoint path back to the execute root)
    private struct ApprovalPause: Error {
        let path: [Int]
    }

    /// Resumes execution: `path` points to the approved approval node; runs the remaining siblings in its block,
    /// then continues up the parent chain (approval nodes are not allowed inside loop bodies, so no iteration state needs restoring).
    private func resumeBlock(
        _ nodes: [FlowNode], prefix: [Int], path: [Int],
        ctx: inout JSONValue, collector: TimelineCollector, depth: Int
    ) async throws -> LoopSignal? {
        guard let index = path.first, index < nodes.count else { return nil }
        if path.count == 1 {
            let node = nodes[index]
            if node.type == .approval {
                collector.append(
                    NodeRunRecord(
                        id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                        iteration: nil, status: .success, startedAt: Date(), endedAt: Date(),
                        input: ctx.clipping(jsonBudget: config.inputJsonBudget),
                        output: .object(["state": .string("approved")])))
            }
            return try await executeBlock(
                nodes, ctx: &ctx, collector: collector, iteration: nil,
                depth: depth, prefix: prefix, from: index + 1)
        }

        let node = nodes[index]
        let branch = path[1]
        let childPath = Array(path.dropFirst(2))
        let branchPrefix = prefix + [index, branch]
        let branchNodes: [FlowNode]
        switch node.type {
        case .ifNode:
            branchNodes = branch == 0 ? (node.thenNodes ?? []) : (node.elseNodes ?? [])
        case .loop:
            branchNodes = node.body ?? []
        default:
            throw TBError.internalError("invalid resume path at node '\(node.id)'")
        }
        if !branchNodes.isEmpty {
            _ = try await resumeBlock(
                branchNodes, prefix: branchPrefix, path: childPath,
                ctx: &ctx, collector: collector, depth: depth + 1)
        }
        return try await executeBlock(
            nodes, ctx: &ctx, collector: collector, iteration: nil,
            depth: depth, prefix: prefix, from: index + 1)
    }

    // MARK: Nodes

    private func executeNode(
        _ node: FlowNode, ctx: inout JSONValue, collector: TimelineCollector,
        iteration: Int?, depth: Int, path: [Int]
    ) async throws -> LoopSignal? {
        if let skipIf = node.skipIf, !skipIf.isEmpty {
            let inputSnapshot = ctx
            let keep = try await runner.evaluate(
                condition: skipIf, ctx: ctx, timeoutMs: config.conditionTimeoutMs)
            if !keep {
                collector.append(
                    .init(
                        id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                        iteration: iteration, status: .skipped, startedAt: Date(), endedAt: Date(),
                        input: inputSnapshot.clipping(jsonBudget: config.inputJsonBudget),
                        output: .null, error: nil, logs: ["skipped by skipIf"]))
                return nil
            }
        }

        switch node.type {
        case .code:
            return try await executeCodeNode(node, ctx: &ctx, collector: collector, iteration: iteration)
        case .ifNode:
            return try await executeIfNode(node, ctx: &ctx, collector: collector, iteration: iteration, depth: depth, path: path)
        case .loop:
            return try await executeLoopNode(node, ctx: &ctx, collector: collector, iteration: iteration, depth: depth, path: path)
        case .action:
            return try await executeActionNode(node, ctx: &ctx, collector: collector, iteration: iteration)
        case .approval:
            return try await executeApprovalNode(node, ctx: ctx, collector: collector, iteration: iteration, path: path)
        }
    }

    /// Approval node: issues a ticket to the host, then suspends the run (throws ApprovalPause to end this phase).
    private func executeApprovalNode(
        _ node: FlowNode, ctx: JSONValue, collector: TimelineCollector,
        iteration: Int?, path: [Int]
    ) async throws -> LoopSignal? {
        guard let sink = approvalSink else {
            throw TBError.nodeFailed(nodeId: node.id, message: "approval sink unavailable on this engine")
        }
        guard let context = Self.runContext else {
            throw TBError.internalError("approval node executed outside run context")
        }
        let message = node.message.map {
            JSONValue.render(template: $0, in: ctx).displayString
        }
        let request = ApprovalRequest(
            runId: context.runId, flowId: context.flowId, flowName: context.flowName,
            nodeId: node.id, nodeName: node.name, message: message)
        let approvalId = try await sink(request)
        collector.append(
            NodeRunRecord(
                id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                iteration: iteration, status: .success, startedAt: Date(), endedAt: Date(),
                input: ctx.clipping(jsonBudget: config.inputJsonBudget),
                output: .object([
                    "approvalId": .string(approvalId),
                    "state": .string("awaitingApproval"),
                ])))
        throw ApprovalPause(path: path)
    }

    private func executeCodeNode(
        _ node: FlowNode, ctx: inout JSONValue, collector: TimelineCollector, iteration: Int?
    ) async throws -> LoopSignal? {
        let source = node.code ?? ""
        let snapshot = ctx
        let language = SubprocessScriptRunner.normalize(node.language)
        let scripts = self.scripts

        let output = try await performNode(node, collector: collector, iteration: iteration, input: snapshot) {
            if language == "js" {
                return try await self.runner.run(
                    code: source, ctx: snapshot,
                    timeoutMs: node.timeoutMs ?? self.config.defaultNodeTimeoutMs,
                    dryRun: self.config.dryRun)
            }
            guard let scripts else {
                throw TBError.validation(
                    "script language '\(language)' is not enabled on this daemon")
            }
            return try await scripts.run(
                language: language, script: source, ctx: snapshot,
                timeoutMs: node.timeoutMs ?? self.config.defaultNodeTimeoutMs,
                dryRun: self.config.dryRun)
        } mapping: { outcome in
            (outcome.value, outcome.logs)
        }

        var value = output
        var signal: LoopSignal? = nil
        if case .object(let object) = value, case .string(let command)? = object["$loop"] {
            if command == "break" { signal = .breakLoop }
            if command == "continue" { signal = .continueLoop }
            var stripped = object
            stripped.removeValue(forKey: "$loop")
            value = .object(stripped)
        }
        ctx.set(value: value, atPath: "nodes.\(node.id).output")
        return signal
    }

    private func executeIfNode(
        _ node: FlowNode, ctx: inout JSONValue, collector: TimelineCollector,
        iteration: Int?, depth: Int, path: [Int]
    ) async throws -> LoopSignal? {
        let source = node.condition ?? "false"
        let snapshot = ctx
        let branch = try await performNode(node, collector: collector, iteration: iteration, input: snapshot) {
            try await self.runner.evaluate(
                condition: source, ctx: snapshot,
                timeoutMs: node.timeoutMs ?? self.config.conditionTimeoutMs)
        } mapping: { taken in
            (.object(["branch": .string(taken ? "then" : "else")]), [])
        }

        let taken: Bool
        if case .object(let o) = branch, case .string(let b)? = o["branch"] {
            taken = b == "then"
        } else {
            taken = false
        }
        ctx.set(value: .object(["branch": .string(taken ? "then" : "else")]), atPath: "nodes.\(node.id).output")
        let branchNodes = taken ? (node.thenNodes ?? []) : (node.elseNodes ?? [])
        let branchPrefix = path + [taken ? 0 : 1]
        return try await executeBlock(
            branchNodes, ctx: &ctx, collector: collector, iteration: iteration,
            depth: depth + 1, prefix: branchPrefix)
    }

    private func executeLoopNode(
        _ node: FlowNode, ctx: inout JSONValue, collector: TimelineCollector,
        iteration: Int?, depth: Int, path: [Int]
    ) async throws -> LoopSignal? {
        let start = Date()
        let inputSnapshot = ctx.clipping(jsonBudget: config.inputJsonBudget)
        do {
            let output = try await executeLoop(node, ctx: &ctx, collector: collector, depth: depth, path: path)
            collector.append(
                .init(
                    id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                    iteration: iteration, status: .success, startedAt: start, endedAt: Date(),
                    input: inputSnapshot,
                    output: output.clipping(jsonBudget: config.outputJsonBudget)))
            ctx.set(value: output, atPath: "nodes.\(node.id).output")
            return nil
        } catch {
            let status: NodeRunStatus
            if error is CancellationError || Task.isCancelled {
                status = .cancelled
            } else if case TBError.timeout = error {
                status = .timeout
            } else {
                status = .failed
            }
            collector.append(
                .init(
                    id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                    iteration: iteration, status: status, startedAt: start, endedAt: Date(),
                    input: inputSnapshot,
                    output: .null,
                    error: (error as? LocalizedError)?.errorDescription ?? String(describing: error)))
            throw error
        }
    }

    private func executeLoop(
        _ node: FlowNode, ctx: inout JSONValue, collector: TimelineCollector, depth: Int,
        path: [Int]
    ) async throws -> JSONValue {
        let mode = node.mode ?? .count
        let maxIterations = min(
            node.maxIterations ?? config.defaultMaxIterations, config.hardMaxIterations)
        let concurrency = min(max(node.concurrency ?? 1, 1), config.maxConcurrency)
        let body = node.body ?? []

        var sequence: [JSONValue] = []
        if mode == .count || mode == .forEach {
            guard let over = node.over, !over.isEmpty else {
                throw TBError.nodeFailed(nodeId: node.id, message: "missing 'over'")
            }
            var resolved = JSONValue.render(template: over, in: ctx)
            if case .string(let text) = resolved {
                // Literal `over` values: a plain number or a JSON array.
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if let number = Int64(trimmed) {
                    resolved = .int(number)
                } else if trimmed.hasPrefix("["),
                    let data = trimmed.data(using: .utf8),
                    let parsed = try? TBJSON.decodeData(JSONValue.self, from: data)
                {
                    resolved = parsed
                }
            }
            switch (mode, resolved) {
            case (.count, .int(let n)) where n >= 0:
                sequence = (0..<min(n, Int64(maxIterations))).map { .int($0) }
            case (.forEach, .array(let items)):
                guard items.count <= maxIterations else {
                    throw TBError.nodeFailed(
                        nodeId: node.id,
                        message: "forEach source has \(items.count) items, exceeding maxIterations \(maxIterations)")
                }
                sequence = items
            default:
                let expected = mode == .count ? "a number" : "an array"
                throw TBError.nodeFailed(
                    nodeId: node.id,
                    message: "\(mode.rawValue) loop 'over' resolved to \(resolved.displayString); expected \(expected)")
            }
        }
        if mode == .whileLoop && concurrency > 1 {
            throw TBError.nodeFailed(nodeId: node.id, message: "while loops do not support concurrency > 1")
        }

        func iterationContext(index: Int, item: JSONValue, base: JSONValue) -> JSONValue {
            var iterCtx = base
            iterCtx.set(value: .object(["item": item, "index": .int(Int64(index))]), atPath: "loop")
            return iterCtx
        }

        var iterationOutputs: [JSONValue] = []
        var breakSeen = false

        if concurrency <= 1 {
            var index = 0
            while true {
                if Task.isCancelled { throw TBError.cancelled }
                if mode == .whileLoop {
                    if index >= maxIterations {
                        throw TBError.nodeFailed(
                            nodeId: node.id, message: "while loop exceeded maxIterations (\(maxIterations))")
                    }
                    let condCtx = iterationContext(index: index, item: .null, base: ctx)
                    let keep = try await runner.evaluate(
                        condition: node.condition ?? "false", ctx: condCtx,
                        timeoutMs: node.timeoutMs ?? config.conditionTimeoutMs)
                    if !keep { break }
                } else {
                    if index >= sequence.count { break }
                }

                let item = mode == .whileLoop ? .null : sequence[index]
                var iterCtx = iterationContext(index: index, item: item, base: ctx)
                let signal = try await executeBlock(
                    body, ctx: &iterCtx, collector: collector, iteration: index,
                    depth: depth + 1, prefix: path + [0, index])
                mergeNodeOutputs(from: iterCtx, into: &ctx)
                iterationOutputs.append(lastOutput(of: body, in: iterCtx))

                if let signal, case .breakLoop = signal { breakSeen = true; break }
                index += 1
            }
        } else {
            var cursor = 0
            while cursor < sequence.count && !breakSeen {
                if Task.isCancelled { throw TBError.cancelled }
                let batchEnd = min(cursor + concurrency, sequence.count)
                let batch = Array(sequence[cursor..<batchEnd])
                let base = ctx

                struct IterationResult: Sendable {
                    let index: Int
                    let signal: LoopSignal?
                    let lastOutput: JSONValue
                    let context: JSONValue
                }

                let batchResults = try await withThrowingTaskGroup(of: IterationResult.self) { group in
                    for (offset, item) in batch.enumerated() {
                        let index = cursor + offset
                        group.addTask {
                            var iterCtx = iterationContext(index: index, item: item, base: base)
                            let signal = try await self.executeBlock(
                                body, ctx: &iterCtx, collector: collector, iteration: index,
                                depth: depth + 1, prefix: path + [0, index])
                            return IterationResult(
                                index: index, signal: signal,
                                lastOutput: self.lastOutput(of: body, in: iterCtx), context: iterCtx)
                        }
                    }
                    var results: [IterationResult] = []
                    for try await result in group { results.append(result) }
                    return results.sorted { $0.index < $1.index }
                }

                for result in batchResults {
                    mergeNodeOutputs(from: result.context, into: &ctx)
                    iterationOutputs.append(result.lastOutput)
                    if let signal = result.signal, case .breakLoop = signal { breakSeen = true }
                }
                cursor = batchEnd
            }
        }

        ctx.remove(atPath: "loop")
        return .object([
            "count": .int(Int64(iterationOutputs.count)),
            "results": .array(iterationOutputs),
        ])
    }

    private func executeActionNode(
        _ node: FlowNode, ctx: inout JSONValue, collector: TimelineCollector, iteration: Int?
    ) async throws -> LoopSignal? {
        let actionName = node.action ?? ""
        let rendered = (node.params ?? .object([:])).renderingTemplates(in: ctx)
        let snapshot = ctx
        let output = try await performNode(
            node, collector: collector, iteration: iteration,
            input: .object(["action": .string(actionName), "params": rendered])
        ) {
            try await self.actions.execute(
                action: actionName, params: rendered, ctx: snapshot, dryRun: self.config.dryRun)
        }
        ctx.set(value: output, atPath: "nodes.\(node.id).output")
        return nil
    }

    // MARK: Shared node execution (timeout / retries / onError / recording)

    private func performNode<T>(
        _ node: FlowNode, collector: TimelineCollector, iteration: Int?,
        input: JSONValue,
        work: @escaping @Sendable () async throws -> T,
        mapping: @escaping @Sendable (T) -> (JSONValue, [String]) = { value in
            if let json = value as? JSONValue { return (json, []) }
            return (.string(String(describing: value)), [])
        }
    ) async throws -> JSONValue {
        let timeoutMs = node.timeoutMs ?? config.defaultNodeTimeoutMs
        let retries = max(node.retries ?? config.defaultRetries, 0)
        let policy = node.onError ?? .abort
        let clippedInput = input.clipping(jsonBudget: config.inputJsonBudget)

        var attempt = 0
        while true {
            attempt += 1
            let start = Date()
            do {
                if Task.isCancelled { throw TBError.cancelled }
                let result = try await withTimeoutMs(timeoutMs, label: node.id) {
                    try await work()
                }
                let (output, logs) = mapping(result)
                collector.append(
                    .init(
                        id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                        iteration: iteration, status: .success, startedAt: start, endedAt: Date(),
                        input: clippedInput,
                        output: output.clipping(jsonBudget: config.outputJsonBudget), logs: logs))
                return output
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                if cancelled {
                    collector.append(
                        .init(
                            id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                            iteration: iteration, status: .cancelled, startedAt: start, endedAt: Date(),
                            input: clippedInput,
                            output: .null, error: "cancelled"))
                    throw TBError.cancelled
                }
                var isTimeout = false
                if case TBError.timeout = error { isTimeout = true }
                let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)

                if attempt <= retries {
                    collector.append(
                        .init(
                            id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                            iteration: iteration, status: .failed, startedAt: start, endedAt: Date(),
                            input: clippedInput,
                            output: .null,
                            error: "attempt \(attempt)/\(retries + 1) failed: \(message); retrying"))
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 300_000_000)
                    continue
                }

                if case .continueOn = policy {
                    collector.append(
                        .init(
                            id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                            iteration: iteration, status: .failed, startedAt: start, endedAt: Date(),
                            input: clippedInput,
                            output: .null, error: "\(message) [onError=continue]"))
                    return .null
                }

                collector.append(
                    .init(
                        id: UUID().uuidString, nodeId: node.id, nodeType: node.type.rawValue,
                        iteration: iteration, status: isTimeout ? .timeout : .failed,
                        startedAt: start, endedAt: Date(), input: clippedInput,
                        output: .null, error: message))
                if isTimeout {
                    throw TBError.timeout("node '\(node.id)'")
                }
                throw TBError.nodeFailed(nodeId: node.id, message: message)
            }
        }
    }

    // MARK: Helpers

    private func mergeNodeOutputs(from iterationCtx: JSONValue, into ctx: inout JSONValue) {
        guard case .object(let nodes)? = iterationCtx["nodes"] else { return }
        for (nodeId, value) in nodes {
            ctx.set(value: value, atPath: "nodes.\(nodeId)")
        }
    }

    private func lastOutput(of body: [FlowNode], in ctx: JSONValue) -> JSONValue {
        guard let last = body.last else { return .null }
        return ctx["nodes.\(last.id).output"] ?? .null
    }

    func withTimeoutMs<T: Sendable>(
        _ ms: Int, label: String, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(clamping: ms) * 1_000_000)
                throw TBError.timeout(label)
            }
            guard let first = try await group.next() else {
                throw TBError.internalError("timeout group produced no result")
            }
            group.cancelAll()
            return first
        }
    }
}

// MARK: - Timeline collector

final class TimelineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [NodeRunRecord] = []

    init(records: [NodeRunRecord] = []) {
        self.records = records
    }

    func append(_ record: NodeRunRecord) {
        lock.lock()
        records.append(record)
        lock.unlock()
    }

    var all: [NodeRunRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}
