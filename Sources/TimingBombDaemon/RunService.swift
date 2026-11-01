import Foundation
import TimingBombCore
import TimingBombL10n

/// Owns in-flight runs: starts engine executions on background tasks,
/// persists finished records, supports waiting and cancellation.
/// dry-run uses a dedicated engine (no side effects); failed runs send a system notification per flow configuration.
/// Terminal history is redacted and retained for 30 days. Approval checkpoints
/// retain private execution state only until a decision completes the run.
/// With history off, terminal results remain redacted in memory for one hour
/// (up to 200 records); approval checkpoints still persist to allow recovery.
public actor RunService {
    public static let historyRetention: TimeInterval = 30 * 24 * 60 * 60
    private static let memoryRetention: TimeInterval = 60 * 60
    private let store: Store
    private let engine: FlowEngine
    private let dryEngine: FlowEngine
    private let notifier: any Notifying
    private var tasks: [String: (task: Task<Void, Never>, flowId: String)] = [:]
    private var recentRecords: [String: RunRecord] = [:]
    private var memoryCleanupTask: Task<Void, Never>?

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

    deinit {
        memoryCleanupTask?.cancel()
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
            try await store.saveRun(SensitiveData.redacted(initial))
        }

        let engine = dryRun ? dryEngine : self.engine
        let notifyOnFailure = flow.notifyOnFailure ?? true
        let task = Task { [weak self] in
            guard let self else { return }
            let record = await engine.execute(flow: flow, runId: runId, trigger: trigger)
            await self.complete(record: record, logging: logging)
            if !dryRun, notifyOnFailure,
                record.status == .failed || record.status == .timeout
            {
                await self.notifier.notify(
                    title: L10n.t("A TimingBomb workflow failed"),
                    body: L10n.t("Open the Runs page to view details."))
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
        pruneMemory()
        if let record = recentRecords[runId] { return record }
        return (try? await store.run(id: runId)).map(SensitiveData.redacted)
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
            await self.complete(record: final, logging: logging)
            if notifyOnFailure,
                final.status == .failed || final.status == .timeout
            {
                await self.notifier.notify(
                    title: L10n.t("A TimingBomb workflow failed"),
                    body: L10n.t("Open the Runs page to view details."))
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
        scheduleMemoryPrune()
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
        scheduleMemoryPrune()
        return try await store.deleteRuns(flowId: flowId)
    }

    /// Rejection must also erase the raw approval checkpoint and invalidate the
    /// cached awaiting-approval response, even when ordinary history is off.
    public func completeApprovalRejection(_ record: RunRecord) async throws {
        let logging = await store.loggingEnabled()
        try await persist(record: record, logging: logging)
        finish(runId: record.id, record: record)
        try await store.pruneRunHistory(olderThan: Date().addingTimeInterval(-Self.historyRetention))
    }

    private func complete(record: RunRecord, logging: Bool) async {
        try? await persist(record: record, logging: logging)
        finish(runId: record.id, record: record)
        _ = try? await store.pruneRunHistory(olderThan: Date().addingTimeInterval(-Self.historyRetention))
    }

    private func persist(record: RunRecord, logging: Bool) async throws {
        if record.status == .awaitingApproval {
            // Only private state required to resume remains raw; all display
            // fields (including node snapshots and logs) are already redacted.
            var checkpoint = SensitiveData.redacted(record)
            checkpoint.context = record.context
            checkpoint.trigger = record.trigger
            try await store.saveRun(checkpoint)
        } else if logging {
            try await store.saveRun(SensitiveData.redacted(record))
        } else {
            // A prior approval may have persisted a checkpoint while history
            // was disabled. Remove it as soon as execution completes.
            _ = try await store.deleteRun(id: record.id)
        }
    }

    private func finish(runId: String, record: RunRecord) {
        tasks.removeValue(forKey: runId)
        recentRecords[runId] = SensitiveData.redacted(record)
        pruneMemory()
        if recentRecords.count > 200 {
            let oldest = recentRecords.values.sorted { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
            for record in oldest.prefix(recentRecords.count - 200) {
                recentRecords.removeValue(forKey: record.id)
            }
        }
        scheduleMemoryPrune()
    }

    private func pruneMemory() {
        let cutoff = Date().addingTimeInterval(-Self.memoryRetention)
        recentRecords = recentRecords.filter { ($0.value.endedAt ?? $0.value.startedAt) >= cutoff }
    }

    private func scheduleMemoryPrune() {
        memoryCleanupTask?.cancel()
        guard let oldest = recentRecords.values.map({ $0.endedAt ?? $0.startedAt }).min() else {
            memoryCleanupTask = nil
            return
        }
        let delay = max(0.01, oldest.addingTimeInterval(Self.memoryRetention).timeIntervalSinceNow)
        memoryCleanupTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            await self?.expireRecentRecords()
        }
    }

    private func expireRecentRecords() {
        pruneMemory()
        scheduleMemoryPrune()
    }
}
