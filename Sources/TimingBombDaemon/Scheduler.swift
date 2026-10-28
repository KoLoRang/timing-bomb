import Foundation
import TimingBombCore

/// cron scheduler: ticks periodically, scans all schedule-triggered flows, and starts runs.
///
/// Trigger decision model: each tick computes the cron's "latest hit time" (slot) within the past 26 hours;
/// if the slot is newer than the last fired slot, it is considered due. Default misfire=skip: a slot more than
/// 5 minutes late does not fire (only the record advances, avoiding a catch-up storm after wake from sleep); fireOnce catches up with one run.
public actor Scheduler {
    private let store: Store
    private let runs: RunService
    private let now: @Sendable () -> Date
    private var lastFired: [String: Date] = [:]
    private var timerTask: Task<Void, Never>?
    public var tickInterval: TimeInterval = 15

    public init(
        store: Store, runs: RunService, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.runs = runs
        self.now = now
    }

    public func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(nanoseconds: UInt64(self.tickInterval * 1_000_000_000))
            }
        }
    }

    public func tick() async {
        let nowDate = now()
        let metas = (try? await store.listFlows()) ?? []
        for meta in metas {
            guard let trigger = meta.flow.trigger, trigger.type == .schedule,
                let cron = trigger.cron,
                let slot = Self.latestSlot(onOrBefore: nowDate, expression: cron, timeZone: timeZone(trigger))
            else { continue }

            let flowId = meta.flow.id
            let last = lastFired[flowId] ?? .distantPast
            guard slot > last else { continue }
            lastFired[flowId] = slot

            let late = nowDate.timeIntervalSince(slot)
            let misfire = trigger.misfire ?? "skip"
            guard late <= 300 || misfire == "fireOnce" else { continue }

            _ = try? await runs.start(
                flow: meta.flow,
                trigger: TriggerInfo(
                    type: "schedule",
                    payload: .object([
                        "cron": .string(cron),
                        "fireAt": .double(slot.timeIntervalSince1970),
                    ])))
        }
    }

    private func timeZone(_ trigger: TriggerConfig) -> TimeZone {
        if let name = trigger.timezone, let tz = TimeZone(identifier: name) { return tz }
        return .current
    }

    /// The latest cron hit time within the past lookback window; nil if none.
    public static func latestSlot(
        onOrBefore date: Date, expression: String, timeZone: TimeZone,
        lookback: TimeInterval = 26 * 3600
    ) -> Date? {
        let slot = CronMatcher.nextFire(
            after: date.addingTimeInterval(-lookback), expression: expression, timeZone: timeZone,
            limit: date)
        guard let first = slot else { return nil }
        var latest = first
        while let next = CronMatcher.nextFire(
            after: latest, expression: expression, timeZone: timeZone, limit: date)
        {
            latest = next
        }
        return latest
    }
}
