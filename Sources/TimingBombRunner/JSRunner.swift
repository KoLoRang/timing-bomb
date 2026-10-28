import Foundation
import JavaScriptCore
import TimingBombCore

// MARK: - Subprocess protocol

public struct JSRunnerRequest: Codable, Sendable {
    public var code: String
    public var ctxJSON: String
    public var timeoutMs: Int
    public var dryRun: Bool
    /// The shell allowlist resolved by the host (the exec tool admits commands against it)
    public var allowlist: [String]?

    public init(
        code: String, ctxJSON: String, timeoutMs: Int, dryRun: Bool, allowlist: [String]? = nil
    ) {
        self.code = code
        self.ctxJSON = ctxJSON
        self.timeoutMs = timeoutMs
        self.dryRun = dryRun
        self.allowlist = allowlist
    }
}

public struct JSRunnerResponse: Codable, Sendable {
    public var ok: Bool
    public var valueJSON: String?
    public var logs: [String]
    public var error: String?

    public init(ok: Bool, valueJSON: String?, logs: [String], error: String?) {
        self.ok = ok
        self.valueJSON = valueJSON
        self.logs = logs
        self.error = error
    }
}

/// For the jsrunner executable: reads a JSON request from stdin, executes once, and returns a JSON response.
public enum JSRunnerProtocol {
    public static func handle(input: Data) async -> Data {
        guard let request = try? TBJSON.decodeData(JSRunnerRequest.self, from: input),
            let ctx = try? TBJSON.decode(JSONValue.self, from: request.ctxJSON)
        else {
            let response = JSRunnerResponse(ok: false, valueJSON: nil, logs: [], error: "bad request payload")
            return (try? TBJSON.encodeData(response)) ?? Data("{}".utf8)
        }
        let execution = JSExecution(
            mode: .code, source: request.code, ctx: ctx,
            timeoutMs: request.timeoutMs, dryRun: request.dryRun,
            allowlist: Allowlist(patterns: request.allowlist ?? []))
        do {
            let value = try await execution.execute()
            let response = JSRunnerResponse(
                ok: true, valueJSON: try? TBJSON.encode(value), logs: execution.logs, error: nil)
            return try TBJSON.encodeData(response)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let response = JSRunnerResponse(
                ok: false, valueJSON: nil, logs: execution.logs, error: message)
            return (try? TBJSON.encodeData(response)) ?? Data("{}".utf8)
        }
    }
}

// MARK: - JSRunner

/// Entry point for code execution. Prefers a dedicated jsrunner subprocess (synchronous infinite loops can be hard-killed);
/// falls back to in-process JSCore when the subprocess executable cannot be found.
/// allowlistProvider: the shell allowlist for the exec tool (resolved on each execution and sent along with the request).
public final class JSRunner: CodeRunning, @unchecked Sendable {
    private let allowlistProvider: @Sendable () async -> Allowlist

    public init(allowlistProvider: @escaping @Sendable () async -> Allowlist = { Allowlist() }) {
        self.allowlistProvider = allowlistProvider
    }

    public func run(
        code: String, ctx: JSONValue, timeoutMs: Int, dryRun: Bool
    ) async throws -> CodeOutcome {
        let allowlist = await allowlistProvider()
        if let executable = Self.subprocessExecutable() {
            do {
                return try await JSProcessRunner.run(
                    executable: executable, code: code, ctx: ctx,
                    timeoutMs: timeoutMs, dryRun: dryRun, allowlist: allowlist)
            } catch let error as TBError {
                // Script errors/timeouts reported by the subprocess itself: propagate as-is
                throw error
            } catch {
                // spawn/IO failure: fall back to in-process execution
                return try await inProcessRun(
                    code: code, ctx: ctx, timeoutMs: timeoutMs, dryRun: dryRun,
                    allowlist: allowlist)
            }
        }
        return try await inProcessRun(
            code: code, ctx: ctx, timeoutMs: timeoutMs, dryRun: dryRun, allowlist: allowlist)
    }

    public func evaluate(condition: String, ctx: JSONValue, timeoutMs: Int) async throws -> Bool {
        try CodeStaticChecker.requireValid(condition, kind: .condition)
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        // Conditions may use top-level keys directly (e.g. nodes.a.output.x) or ctx.get(...)
        let source: String
        if trimmed.contains("return") || trimmed.contains(";") {
            source = """
            async function run(ctx) {
              const { config, trigger, nodes, loop } = ctx;
            \(trimmed)
            }
            """
        } else {
            source = """
            async function run(ctx) {
              const { config, trigger, nodes, loop } = ctx;
              return (\(trimmed));
            }
            """
        }
        let execution = JSExecution(mode: .condition, source: source, ctx: ctx, timeoutMs: timeoutMs, dryRun: false)
        let value = try await execution.execute()
        guard let bool = value.boolValue else {
            throw TBError.scriptError(
                "condition did not evaluate to a boolean (got \(value.displayString))")
        }
        return bool
    }

    private func inProcessRun(
        code: String, ctx: JSONValue, timeoutMs: Int, dryRun: Bool, allowlist: Allowlist
    ) async throws -> CodeOutcome {
        try CodeStaticChecker.requireValid(code, kind: .code)
        let execution = JSExecution(
            mode: .code, source: code, ctx: ctx, timeoutMs: timeoutMs, dryRun: dryRun,
            allowlist: allowlist)
        let value = try await execution.execute()
        return CodeOutcome(value: value, logs: execution.logs)
    }

    /// jsrunner executable lookup: environment variable → App bundle → same directory as this executable.
    static func subprocessExecutable() -> URL? {
        let fileManager = FileManager.default
        if let path = ProcessInfo.processInfo.environment["TIMINGBOMB_JS_RUNNER"],
            fileManager.fileExists(atPath: path)
        {
            return URL(fileURLWithPath: path)
        }
        let inBundle = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/jsrunner")
        if fileManager.fileExists(atPath: inBundle.path) { return inBundle }
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("jsrunner")
        if fileManager.fileExists(atPath: sibling.path) { return sibling }
        return nil
    }
}

// MARK: - Subprocess execution

enum JSProcessRunner {
    static func run(
        executable: URL, code: String, ctx: JSONValue, timeoutMs: Int, dryRun: Bool,
        allowlist: Allowlist
    ) async throws -> CodeOutcome {
        let request = JSRunnerRequest(
            code: code, ctxJSON: try TBJSON.encode(ctx), timeoutMs: timeoutMs, dryRun: dryRun,
            allowlist: allowlist.patterns)
        let payload = try TBJSON.encodeData(request)

        let process = Process()
        process.executableURL = executable
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()
        try stdinPipe.fileHandleForWriting.write(contentsOf: payload)
        try? stdinPipe.fileHandleForWriting.close()

        // Reads and timeout are separated: the timeout task kills the process; once dead, pipes hit EOF and the read task returns naturally.
        // (If the kill lived in the timeout catch, the group would first wait on the forever-blocked readToEnd — deadlock.)
        let readTask = Task.detached(priority: .utility) { () -> String in
            if let data = try? stdoutPipe.fileHandleForReading.readToEnd() {
                return String(decoding: data, as: UTF8.self)
            }
            return ""
        }
        let killerTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(clamping: timeoutMs + 2_000) * 1_000_000)
            guard !Task.isCancelled, process.isRunning else { return }
            process.terminate()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        let text = await readTask.value
        killerTask.cancel()
        // Skip waitUntilExit: after a bare kill() the child occasionally never returns (Foundation race);
        // EOF already arrived, so the process is surely dead — just poll with a timeout
        var waitedNanos = 0
        while process.isRunning, waitedNanos < 2_000_000_000 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waitedNanos += 50_000_000
        }

        guard !text.isEmpty, let data = text.data(using: .utf8),
            let response = try? TBJSON.decodeData(JSRunnerResponse.self, from: data)
        else {
            throw TBError.timeout("js subprocess (killed at \(timeoutMs)ms)")
        }
        if let error = response.error {
            throw TBError.scriptError(error)
        }
        let value = response.valueJSON.flatMap { try? TBJSON.decode(JSONValue.self, from: $0) } ?? .null
        return CodeOutcome(value: value, logs: response.logs)
    }
}

// MARK: - Single execution (in-process)

final class JSExecution: @unchecked Sendable {
    enum Mode {
        case code
        case condition
    }

    let mode: Mode
    let source: String
    let ctxValue: JSONValue
    let timeoutMs: Int
    let dryRun: Bool
    let allowlist: Allowlist
    let queue = DispatchQueue(label: "tb.js.execution")
    let box = StateBox()
    var jsContext: JSContext? = nil

    init(
        mode: Mode, source: String, ctx: JSONValue, timeoutMs: Int, dryRun: Bool = false,
        allowlist: Allowlist = Allowlist()
    ) {
        self.mode = mode
        self.source = source
        self.ctxValue = ctx
        self.timeoutMs = timeoutMs
        self.dryRun = dryRun
        self.allowlist = allowlist
    }

    var logs: [String] { box.takeLogs() }

    // MARK: State

    final class StateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _settled = false
        private var _cancelled = false
        private var _successJSON: String? = nil
        private var _failureMessage: String? = nil
        private var _logs: [String] = []
        private var _droppedLogs = 0
        private var _nextOpId = 0

        var isSettled: Bool {
            lock.lock(); defer { lock.unlock() }
            return _settled
        }

        var isActive: Bool {
            lock.lock(); defer { lock.unlock() }
            return !_settled && !_cancelled
        }

        var failureMessage: String? {
            lock.lock(); defer { lock.unlock() }
            return _failureMessage
        }

        var successJSON: String? {
            lock.lock(); defer { lock.unlock() }
            return _successJSON
        }

        func settle(ok: Bool, json: String) {
            lock.lock(); defer { lock.unlock() }
            guard !_settled, !_cancelled else { return }
            _settled = true
            if ok { _successJSON = json } else { _failureMessage = json }
        }

        func markCancelled() {
            lock.lock(); defer { lock.unlock() }
            _cancelled = true
        }

        func allocateOpId() -> Int {
            lock.lock(); defer { lock.unlock() }
            _nextOpId += 1
            return _nextOpId
        }

        func appendLog(_ line: String) {
            lock.lock(); defer { lock.unlock() }
            if _logs.count < 1000 {
                _logs.append(line)
            } else {
                _droppedLogs += 1
            }
        }

        func takeLogs() -> [String] {
            lock.lock(); defer { lock.unlock() }
            if _droppedLogs > 0 {
                return _logs + ["... \(_droppedLogs) more log lines dropped"]
            }
            return _logs
        }
    }

    // MARK: Bootstrap JS

    static let bootstrapJS = #"""
        globalThis.__tbCallbacks = {};
        globalThis.__tbCall = function(op, argsJson) {
            return new Promise(function(resolve, reject) {
                var id = __tbBegin(op, argsJson);
                if (id < 0) { reject(new Error("runner is shutting down")); return; }
                __tbCallbacks[id] = { resolve: resolve, reject: reject };
            });
        };
        globalThis.__tbFinish = function(id, ok, json) {
            var cb = __tbCallbacks[id];
            if (!cb) { return; }
            delete __tbCallbacks[id];
            if (ok) { cb.resolve(JSON.parse(json)); }
            else { cb.reject(new Error(json)); }
        };
        globalThis.ctx = null;
        """#

    static let toolsJS = #"""
        ctx.tools = {
            log: function() {
                try { __tbBegin("log", JSON.stringify(Array.prototype.slice.call(arguments))); } catch (e) {}
            },
            sleep: function(ms) { return __tbCall("sleep", JSON.stringify([ms])); },
            fail: function(message) { throw new Error(String(message)); },
            http: {
                fetch: function(url, opts) {
                    return __tbCall("http.fetch", JSON.stringify([url, opts || {}])).then(function(r) {
                        r.json = function() { return JSON.parse(this.body); };
                        return r;
                    });
                }
            },
            exec: function(command, opts) {
                return __tbCall("exec", JSON.stringify([command, opts || {}]));
            }
        };
        ctx.get = function(path) {
            return String(path).split(".").reduce(function(o, k) { return o == null ? undefined : o[k]; }, ctx);
        };
        globalThis.console = {
            log: ctx.tools.log, warn: ctx.tools.log,
            error: ctx.tools.log, info: ctx.tools.log
        };
        """#

    static let invokeJS = #"""
        (async function() {
            try {
                var v = await run(ctx);
                __tbSettle(true, JSON.stringify({ value: v === undefined ? null : v }));
            } catch (e) {
                __tbSettle(false, String((e && e.message) || e));
            }
        })();
        """#

    // MARK: Execution

    func execute() async throws -> JSONValue {
        queue.async { [weak self] in
            self?.prepare()
        }

        let deadline = Date().addingTimeInterval(TimeInterval(max(1, timeoutMs)) / 1000)
        while true {
            if box.isSettled { break }
            if Task.isCancelled {
                box.markCancelled()
                throw CancellationError()
            }
            if Date() >= deadline {
                box.markCancelled()
                throw TBError.timeout("script exceeded \(timeoutMs)ms")
            }
            queue.async { [weak self] in
                self?.pump()
            }
            try await Task.sleep(nanoseconds: 4_000_000)
        }

        if let failure = box.failureMessage {
            throw TBError.scriptError(failure)
        }
        let payload = box.successJSON ?? "null"
        guard let data = payload.data(using: .utf8),
            let envelope = try? TBJSON.decodeData(JSONValue.self, from: data)
        else {
            throw TBError.internalError("runner returned an undecodable result")
        }
        return envelope["value"] ?? .null
    }

    private func prepare() {
        guard let js = JSContext() else {
            box.settle(ok: false, json: "cannot create JSContext")
            return
        }
        jsContext = js
        js.exceptionHandler = { [weak self] _, exception in
            guard let self else { return }
            let message = exception?.toString() ?? "unknown JS exception"
            if self.box.isActive {
                self.box.settle(ok: false, json: "uncaught exception: \(message)")
            }
        }

        let begin: @convention(block) (String, String) -> Int = { [weak self] op, argsJSON in
            guard let self else { return -1 }
            return self.beginOp(op, argsJSON)
        }
        let settle: @convention(block) (Bool, String) -> Void = { [weak self] ok, json in
            self?.box.settle(ok: ok, json: json)
        }
        js.setObject(begin, forKeyedSubscript: "__tbBegin" as NSString)
        js.setObject(settle, forKeyedSubscript: "__tbSettle" as NSString)

        guard evaluate(js, Self.bootstrapJS, context: "bootstrap") else { return }
        guard let ctxText = try? TBJSON.encode(ctxValue) else {
            box.settle(ok: false, json: "context is not encodable")
            return
        }
        guard evaluate(js, "globalThis.ctx = JSON.parse(\(Self.jsStringLiteral(ctxText)));", context: "context")
        else { return }
        guard evaluate(js, Self.toolsJS, context: "tools") else { return }
        guard evaluate(js, source, context: "user script") else { return }
        guard evaluate(js, Self.invokeJS, context: "invoke") else { return }
    }

    @discardableResult
    private func evaluate(_ js: JSContext, _ script: String, context: String) -> Bool {
        _ = js.evaluateScript(script)
        if let exception = js.exception {
            js.exception = nil
            box.settle(ok: false, json: "\(context): \(exception.toString() ?? "<exception>")")
            return false
        }
        return true
    }

    /// Drains the promise microtask queue (any script evaluation triggers a checkpoint).
    private func pump() {
        guard let js = jsContext else { return }
        _ = js.evaluateScript("0")
        if let exception = js.exception {
            js.exception = nil
            if box.isActive {
                box.settle(ok: false, json: "uncaught exception: \(exception.toString() ?? "<exception>")")
            }
        }
    }

    // MARK: Tools

    private func beginOp(_ op: String, _ argsJSON: String) -> Int {
        let id = box.allocateOpId()
        // dry-run: side-effecting tools return placeholder results directly
        // (exec and log fall through to the normal path below: exec must pass the allowlist before returning a placeholder)
        if dryRun {
            switch op {
            case "log", "exec":
                break
            case "sleep":
                finish(id, ok: true, jsonText: "null")
                return id
            case "http.fetch":
                let mock: JSONValue = .object([
                    "status": .int(200), "ok": .bool(true), "dryRun": .bool(true),
                    "body": .string("(dry-run: fetch skipped)"),
                ])
                finish(id, ok: true, jsonText: (try? TBJSON.encode(mock)) ?? "null")
                return id
            default:
                finish(id, ok: false, jsonText: "tool '\(op)' is not available in dry-run")
                return id
            }
        }

        switch op {
        case "log":
            if let data = argsJSON.data(using: .utf8),
                let values = try? JSONDecoder().decode([JSONValue].self, from: data)
            {
                box.appendLog(values.map(\.displayString).joined(separator: " "))
            }
        case "sleep":
            var ms: Int64 = 0
            if let data = argsJSON.data(using: .utf8),
                let args = try? JSONDecoder().decode([JSONValue].self, from: data),
                let parsed = args.first?.intValue
            {
                ms = parsed
            }
            let clamped = Int(min(max(ms, 0), 600_000))
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
                self?.finish(id, ok: true, jsonText: "null")
            }
        case "http.fetch":
            Task { [weak self] in
                await self?.performFetch(id: id, argsJSON: argsJSON)
            }
        case "exec":
            Task { [weak self] in
                await self?.performExec(id: id, argsJSON: argsJSON)
            }
        default:
            finish(id, ok: false, jsonText: "unknown tool '\(op)'")
        }
        return id
    }

    private func finish(_ id: Int, ok: Bool, jsonText: String) {
        guard box.isActive else { return }
        queue.async { [weak self] in
            guard let self, let js = self.jsContext else { return }
            _ = js.evaluateScript(
                "__tbFinish(\(id), \(ok ? "true" : "false"), \(Self.jsStringLiteral(jsonText)));")
            if let exception = js.exception {
                js.exception = nil
                if self.box.isActive {
                    self.box.settle(ok: false, json: "tool result delivery failed: \(exception.toString() ?? "<exception>")")
                }
            }
        }
    }

    private func performFetch(id: Int, argsJSON: String) async {
        var url: URL? = nil
        var method = "GET"
        var headers: [String: String] = [:]
        var body: Data? = nil
        var timeoutMs: Int = 30_000

        if let data = argsJSON.data(using: .utf8),
            let args = try? JSONDecoder().decode([JSONValue].self, from: data)
        {
            url = args.first?.stringValue.flatMap(URL.init(string:))
            if args.count > 1, case .object(let opts) = args[1] {
                if let m = opts["method"]?.stringValue { method = m.uppercased() }
                if case .object(let h)? = opts["headers"] {
                    for (name, value) in h where value.stringValue != nil {
                        headers[name] = value.stringValue
                    }
                }
                switch opts["body"] {
                case .string(let text): body = Data(text.utf8)
                case .object, .array:
                    body = try? TBJSON.encodeData(opts["body"]!)
                    if body != nil, headers["Content-Type"] == nil {
                        headers["Content-Type"] = "application/json"
                    }
                default: break
                }
                if let t = opts["timeoutMs"]?.intValue { timeoutMs = Int(t) }
            }
        }

        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            url.host != nil
        else {
            finish(id, ok: false, jsonText: "http.fetch requires a valid http(s) url")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = min(max(Double(timeoutMs) / 1000, 1), 120)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            var headerObject: [String: JSONValue] = [:]
            var status: Int64 = 0
            if let http = response as? HTTPURLResponse {
                status = Int64(http.statusCode)
                for (name, value) in http.allHeaderFields {
                    if let n = name as? String, let v = value as? String {
                        headerObject[n.lowercased()] = .string(v)
                    }
                }
            }
            let bodyText = String(data: data.prefix(2_000_000), encoding: .utf8) ?? ""
            let result = JSONValue.object([
                "status": .int(status),
                "ok": .bool((200..<300).contains(Int(status))),
                "headers": .object(headerObject),
                "body": .string(bodyText),
            ])
            guard let jsonText = try? TBJSON.encode(result) else {
                finish(id, ok: false, jsonText: "http.fetch result is not encodable")
                return
            }
            finish(id, ok: true, jsonText: jsonText)
        } catch {
            finish(id, ok: false, jsonText: "http.fetch: \(error.localizedDescription)")
        }
    }

    /// ctx.tools.exec: after passing the allowlist, runs the command under the augmented PATH and returns {exitCode, stdout, stderr}.
    private func performExec(id: Int, argsJSON: String) async {
        var command = ""
        var timeoutMs = 30_000
        if let data = argsJSON.data(using: .utf8),
            let args = try? JSONDecoder().decode([JSONValue].self, from: data),
            let first = args.first?.stringValue
        {
            command = first
            if args.count > 1, case .object(let opts) = args[1] {
                if let t = opts["timeoutMs"]?.intValue {
                    timeoutMs = Int(min(max(t, 1), 600_000))
                }
            }
        }
        guard !command.isEmpty else {
            finish(id, ok: false, jsonText: "exec requires a command string")
            return
        }
        guard allowlist.matches(command) else {
            finish(
                id, ok: false,
                jsonText: "exec denied: command not in allowlist (authorize with `tb allow add \"<pattern>\"`)")
            return
        }
        if dryRun {
            let mock: JSONValue = .object([
                "dryRun": .bool(true), "command": .string(command),
            ])
            finish(id, ok: true, jsonText: (try? TBJSON.encode(mock)) ?? "null")
            return
        }
        do {
            let result = try await CoreProcess.runZshCommand(command, timeoutMs: timeoutMs)
            finish(id, ok: true, jsonText: (try? TBJSON.encode(result)) ?? "null")
        } catch {
            finish(id, ok: false, jsonText: "exec: \(error.localizedDescription)")
        }
    }

    // MARK: Literals

    static func jsStringLiteral(_ text: String) -> String {
        let encoded = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
        return String(data: encoded, encoding: .utf8) ?? "\"\""
    }
}
