import Foundation
import TimingBombCore
import TimingBombL10n

/// Owns in-flight runs: starts engine executions on background tasks,
/// persists finished records, supports waiting and cancellation.
/// dry-run uses a dedicated engine (no side effects); failed runs send a system notification per flow configuration.
/// When "record run history" is off, new runs are not persisted to the store and stay in memory only (for --wait retrieval, capped at 200).
public actor RunService {
    private let store: Store
    private let engine: FlowEngine
    private let dryEngine: FlowEngine
    private let notifier: any Notifying
    private var tasks: [String: (task: Task<Void, Never>, flowId: String)] = [:]
    private var recentRecords: [String: RunRecord] = [:]

    public init(store: Store, engine: FlowEngine, notifier: any Notifying = NullNotifier()) {
        self.store = store
        self.engine = engine
        self.notifier = notifier
        var dryConfig = FlowEngine.Config()
        dryConfig.dryRun = true
        self.dryEngine = FlowEngine(
            runner: engine.runner, actions: engine.actions, scripts: engine.scripts,
            config: dryConfig)
    }

    /// Registers a running row and kicks off the execution. Returns the run id.
    @discardableResult
    public func start(
        flow: FlowDefinition, trigger: TriggerInfo, dryRun: Bool = false
    ) async throws -> String {
        let runId = UUID().uuidString.lowercased()
        let logging = await store.loggingEnabled()
        if logging {
            let initial = RunRecord(
                id: runId, flowId: flow.id, flowName: flow.name,
                status: .running, trigger: trigger, startedAt: Date())
            try await store.saveRun(initial)
        }

        let engine = dryRun ? dryEngine : self.engine
        let notifyOnFailure = flow.notifyOnFailure ?? true
        let task = Task { [weak self] in
            guard let self else { return }
            let record = await engine.execute(flow: flow, runId: runId, trigger: trigger)
            if logging {
                try? await self.store.saveRun(record)
            }
            await self.finish(runId: runId, record: record)
            if !dryRun, notifyOnFailure,
                record.status == .failed || record.status == .timeout
            {
                let summary = record.error ?? String(describing: record.status)
                await self.notifier.notify(
                    title: L10n.t("TimingBomb · {name} failed", ["name": flow.name]),
                    body: "\(record.status.rawValue): \(summary)")
            }
        }
        tasks[runId] = (task, flow.id)
        return runId
    }

    /// Waits for a run to finish (if still running) and returns its record.
    public func wait(runId: String) async -> RunRecord? {
        if let entry = tasks[runId] {
            _ = await entry.task.value
        }
        if let record = recentRecords[runId] { return record }
        return try? await store.run(id: runId)
    }

    public func cancel(runId: String) async -> Bool {
        guard let entry = tasks[runId] else { return false }
        entry.task.cancel()
        return true
    }

    public func isRunning(runId: String) -> Bool {
        tasks[runId] != nil
    }

    /// Resumes execution from an approval breakpoint (continues with the same runId, timeline preserved).
    public func resume(
        flow: FlowDefinition, record: RunRecord, resume: FlowEngine.ResumeInfo
    ) async throws {
        guard !tasks.keys.contains(record.id) else {
            throw TBApiError(
                status: 400, code: "runAlreadyRunning",
                template: "run {runId} is already running", params: ["runId": record.id])
        }
        let runId = record.id
        let trigger = record.trigger
        let notifyOnFailure = flow.notifyOnFailure ?? true
        let logging = await store.loggingEnabled()
        let task = Task { [weak self] in
            guard let self else { return }
            let final = await self.engine.execute(
                flow: flow, runId: runId, trigger: trigger, resume: resume)
            if logging {
                try? await self.store.saveRun(final)
            }
            await self.finish(runId: runId, record: final)
            if notifyOnFailure,
                final.status == .failed || final.status == .timeout
            {
                let summary = final.error ?? String(describing: final.status)
            await self.notifier.notify(
                title: L10n.t("TimingBomb · {name} failed", ["name": flow.name]),
                body: "\(final.status.rawValue): \(summary)")
            }
        }
        tasks[runId] = (task, flow.id)
    }

    // MARK: Deleting run records

    /// Deletes a single run record; records of still-running tasks are refused (cancel first or wait for completion).
    public func deleteRun(id: String) async throws {
        if tasks[id] != nil {
            throw TBApiError(
                status: 400, code: "runStillRunning",
                template: "run {runId} is still running; cancel it or wait for it to finish",
                params: ["runId": id])
        }
        recentRecords.removeValue(forKey: id)
        _ = try await store.deleteRun(id: id)
    }

    /// Deletes run records of the given flow (nil = all); refused when any run in scope is still running.
    @discardableResult
    public func deleteRuns(flowId: String? = nil) async throws -> Int {
        let running = tasks.values.map(\.flowId)
        if let flowId {
            guard !running.contains(flowId) else {
                throw TBApiError(
                    status: 400, code: "flowHasRunningTasks",
                    template: "flow {flowId} has running tasks; cancel them or wait for them to finish",
                    params: ["flowId": flowId])
            }
        } else if !running.isEmpty {
            throw TBApiError(
                status: 400, code: "hasRunningTasks",
                template: "there are running tasks; cancel them or wait for them to finish")
        }
        if let flowId {
            recentRecords = recentRecords.filter { $0.value.flowId != flowId }
        } else {
            recentRecords.removeAll()
        }
        return try await store.deleteRuns(flowId: flowId)
    }

    private func finish(runId: String, record: RunRecord) {
        tasks.removeValue(forKey: runId)
        recentRecords[runId] = record
        if recentRecords.count > 200 {
            let overflow = recentRecords.count - 200
            for key in recentRecords.keys.sorted().prefix(overflow) {
                recentRecords.removeValue(forKey: key)
            }
        }
    }
}
