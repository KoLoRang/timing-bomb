import CoreServices
import Foundation
import TimingBombCore

/// File watch trigger: sets up a recursive FSEvents directory monitor for flows with trigger.type == fileWatch;
/// events are debounced per flow for 2.5s, aggregated, then fire a single run with the event list injected into the payload.
public final class FileWatchHub: @unchecked Sendable {
    private let store: Store
    private let runs: RunService
    private let queue = DispatchQueue(label: "tb.filewatch")
    private let lock = NSLock()
    private var streams: [String: FSEventStreamRef] = [:]
    private var watchBoxes: [String: WatchBox] = [:]
    private var pendingEvents: [String: [(path: String, event: String)]] = [:]
    private var pendingTasks: [String: Task<Void, Never>] = [:]

    public init(store: Store, runs: RunService) {
        self.store = store
        self.runs = runs
    }

    /// Called after flows are added/removed/updated: diffs the current watch set.
    public func reload() async {
        let metas = (try? await store.listFlows()) ?? []
        var wanted: [String: String] = [:]
        for meta in metas {
            guard meta.flow.trigger?.type == .fileWatch,
                let rawPath = meta.flow.trigger?.path
            else { continue }
            let expanded = (rawPath as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
                isDirectory.boolValue
            {
                wanted[meta.flow.id] = expanded
            }
        }

        let current = currentStreams()
        for (flowId, stream) in current where wanted[flowId] == nil {
            stopStream(flowId: flowId, stream: stream)
        }
        for (flowId, path) in wanted where current[flowId] == nil {
            startStream(flowId: flowId, path: path)
        }
    }

    // MARK: FSEvents (synchronous section, avoids holding the lock in an async context)

    final class WatchBox {
        let hub: FileWatchHub
        let flowId: String
        init(hub: FileWatchHub, flowId: String) {
            self.hub = hub
            self.flowId = flowId
        }
    }

    private func currentStreams() -> [String: FSEventStreamRef] {
        lock.lock()
        defer { lock.unlock() }
        return streams
    }

    private func startStream(flowId: String, path: String) {
        let box = WatchBox(hub: self, flowId: flowId)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, rawInfo, count, rawPaths, rawFlags, _ in
            guard let rawInfo else { return }
            let box = Unmanaged<WatchBox>.fromOpaque(rawInfo).takeUnretainedValue()
            let paths = rawPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
            let pathList = (0..<count).map { String(cString: paths[$0]!) }
            let flagList = (0..<count).map { rawFlags[$0] }
            box.hub.handleEvents(flowId: box.flowId, paths: pathList, flags: flagList)
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
        else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        lock.lock()
        streams[flowId] = stream
        watchBoxes[flowId] = box
        lock.unlock()
    }

    private func stopStream(flowId: String, stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        lock.lock()
        streams.removeValue(forKey: flowId)
        watchBoxes.removeValue(forKey: flowId)
        lock.unlock()
    }

    // MARK: Event handling (FSEvents callback thread)

    private func handleEvents(flowId: String, paths: [String], flags: [UInt32]) {
        var collected: [(path: String, event: String)] = []
        for (index, path) in paths.enumerated() {
            collected.append((path, Self.eventName(flagRaw: flags[index]) ?? "modified"))
        }
        guard !collected.isEmpty else { return }
        enqueueEvents(flowId: flowId, events: collected)
    }

    private static func eventName(flagRaw: UInt32) -> String? {
        if flagRaw & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { return "created" }
        if flagRaw & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 { return "removed" }
        if flagRaw & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 { return "renamed" }
        if flagRaw & UInt32(kFSEventStreamEventFlagItemModified) != 0 { return "modified" }
        return nil
    }

    /// Records events and (re)schedules the debounced trigger.
    private func enqueueEvents(flowId: String, events: [(path: String, event: String)]) {
        lock.lock()
        pendingEvents[flowId, default: []].append(contentsOf: events)
        pendingTasks[flowId]?.cancel()
        let store = self.store
        let runs = self.runs
        pendingTasks[flowId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            let drained = self.drainEvents(flowId: flowId)
            guard !drained.isEmpty, let flow = try? await store.flow(id: flowId) else { return }
            _ = try? await runs.start(
                flow: flow,
                trigger: TriggerInfo(
                    type: "fileWatch",
                    payload: .object([
                        "events": .array(
                            drained.map { event in
                                .object(["path": .string(event.path), "event": .string(event.event)])
                            })
                    ])))
        }
        lock.unlock()
    }

    private func drainEvents(flowId: String) -> [(path: String, event: String)] {
        lock.lock()
        defer { lock.unlock() }
        pendingTasks.removeValue(forKey: flowId)
        return pendingEvents.removeValue(forKey: flowId) ?? []
    }
}
