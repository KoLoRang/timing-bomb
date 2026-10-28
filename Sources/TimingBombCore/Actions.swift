import AppKit
import Foundation

// MARK: - Notifications

public protocol Notifying: Sendable {
    func notify(title: String, body: String) async
}

/// Default no-op implementation (for tests / when nothing is injected).
public struct NullNotifier: Notifying {
    public init() {}
    public func notify(title: String, body: String) async {}
}

// MARK: - Built-in actions

/// The built-in action set. Sensitive actions (shell / appleScript) must hit the allowlist;
/// in dryRun mode every side-effecting action only returns a placeholder result and is not really executed.
public struct BuiltinActions: ActionExecuting {
    let allowlistProvider: @Sendable () async -> Allowlist
    let notifier: any Notifying

    public init(
        allowlistProvider: @escaping @Sendable () async -> Allowlist = { Allowlist() },
        notifier: any Notifying = NullNotifier()
    ) {
        self.allowlistProvider = allowlistProvider
        self.notifier = notifier
    }

    public var knownActions: [String] {
        [
            "delay", "http", "shell", "appleScript", "notify", "openApp", "clipboard",
            "fileRead", "fileWrite",
        ]
    }

    public func execute(
        action: String, params: JSONValue, ctx: JSONValue, dryRun: Bool
    ) async throws -> JSONValue {
        switch action {
        case "delay":
            return try await delay(params: params, dryRun: dryRun)
        case "http":
            return try await http(params: params, dryRun: dryRun)
        case "shell":
            return try await shell(params: params, dryRun: dryRun)
        case "appleScript":
            return try await appleScript(params: params, dryRun: dryRun)
        case "notify":
            return try await notify(params: params, dryRun: dryRun)
        case "openApp":
            return try await openApp(params: params, dryRun: dryRun)
        case "clipboard":
            return try await clipboard(params: params, dryRun: dryRun)
        case "fileRead":
            return try fileRead(params: params, ctx: ctx, dryRun: dryRun)
        case "fileWrite":
            return try fileWrite(params: params, ctx: ctx, dryRun: dryRun)
        default:
            throw TBError.unsupportedAction(action)
        }
    }

    // MARK: delay

    private func delay(params: JSONValue, dryRun: Bool) async throws -> JSONValue {
        let ms = params["ms"]?.intValue ?? params.intValue ?? 0
        let clamped = min(max(ms, 0), 3_600_000)
        if dryRun {
            return .object(["delayedMs": .int(0), "dryRun": .bool(true)])
        }
        if clamped > 0 {
            try await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
        }
        return .object(["delayedMs": .int(clamped)])
    }

    // MARK: http

    private func http(params: JSONValue, dryRun: Bool) async throws -> JSONValue {
        if dryRun {
            return .object([
                "status": .int(200), "ok": .bool(true), "dryRun": .bool(true),
                "body": .string("(dry-run: request skipped)"),
            ])
        }
        guard let urlString = params["url"]?.stringValue, let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
            url.host != nil
        else {
            throw TBError.validation("http action requires a valid http(s) 'url'")
        }

        var request = URLRequest(url: url)
        request.httpMethod = params["method"]?.stringValue?.uppercased() ?? "GET"
        if let timeoutMs = params["timeoutMs"]?.intValue {
            request.timeoutInterval = min(max(Double(timeoutMs) / 1000, 1), 120)
        }
        if case .object(let headers)? = params["headers"] {
            for (name, value) in headers {
                if let v = value.stringValue { request.setValue(v, forHTTPHeaderField: name) }
            }
        }
        if let body = params["body"] {
            switch body {
            case .string(let text):
                request.httpBody = Data(text.utf8)
            case .object, .array:
                request.httpBody = try TBJSON.encodeData(body)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            default:
                break
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        var headerMap: [String: JSONValue] = [:]
        let status: Int
        if let http = response as? HTTPURLResponse {
            status = http.statusCode
            for (name, value) in http.allHeaderFields {
                if let n = name as? String, let v = value as? String {
                    headerMap[n.lowercased()] = .string(v)
                }
            }
        } else {
            status = 0
        }
        let bodyText = String(data: data.prefix(2_000_000), encoding: .utf8) ?? ""
        return .object([
            "status": .int(Int64(status)),
            "ok": .bool((200..<300).contains(status)),
            "headers": .object(headerMap),
            "body": .string(bodyText),
        ])
    }

    // MARK: shell (allowlist)

    private func shell(params: JSONValue, dryRun: Bool) async throws -> JSONValue {
        guard let command = params["command"]?.stringValue, !command.isEmpty else {
            throw TBError.validation("shell action requires 'command'")
        }
        try await requireAllowed(command)
        if dryRun {
            return .object(["dryRun": .bool(true), "command": .string(command)])
        }
        let timeoutMs = Int(min(params["timeoutMs"]?.intValue ?? 30_000, 600_000))
        return try await runProcess(
            launchPath: "/bin/zsh", arguments: ["-c", command], timeoutMs: timeoutMs)
    }

    // MARK: appleScript (allowlist)

    private func appleScript(params: JSONValue, dryRun: Bool) async throws -> JSONValue {
        guard let script = params["script"]?.stringValue, !script.isEmpty else {
            throw TBError.validation("appleScript action requires 'script'")
        }
        try await requireAllowed(script)
        if dryRun {
            return .object(["dryRun": .bool(true)])
        }
        return try await runProcess(
            launchPath: "/usr/bin/osascript", arguments: ["-e", script], timeoutMs: 60_000)
    }

    private func requireAllowed(_ command: String) async throws {
        let allowlist = await allowlistProvider()
        guard allowlist.matches(command) else {
            throw TBError.validation(
                "command not in allowlist (authorize first: `tb allow add \"<pattern>\"`, e.g. \"git *\"; pattern `*` allows all)"
            )
        }
    }

    // MARK: notify / openApp / clipboard

    private func notify(params: JSONValue, dryRun: Bool) async throws -> JSONValue {
        let title = params["title"]?.stringValue ?? "TimingBomb"
        let body = params["body"]?.stringValue ?? ""
        if dryRun {
            return .object(["dryRun": .bool(true)])
        }
        await notifier.notify(title: title, body: body)
        return .object(["notified": .bool(true)])
    }

    private func openApp(params: JSONValue, dryRun: Bool) async throws -> JSONValue {
        let name = params["name"]?.stringValue ?? params["bundleId"]?.stringValue ?? ""
        guard !name.isEmpty else {
            throw TBError.validation("openApp action requires 'name'")
        }
        if dryRun {
            return .object(["dryRun": .bool(true), "app": .string(name)])
        }
        return try await runProcess(
            launchPath: "/usr/bin/open", arguments: ["-a", name], timeoutMs: 15_000)
    }

    private func clipboard(params: JSONValue, dryRun: Bool) async throws -> JSONValue {
        let op = params["op"]?.stringValue ?? "read"
        if op == "read" {
            let text = await MainActor.run {
                NSPasteboard.general.string(forType: .string)
            } ?? ""
            return .object(["text": .string(text)])
        }
        guard let text = params["text"]?.stringValue else {
            throw TBError.validation("clipboard write requires 'text'")
        }
        if dryRun {
            return .object(["dryRun": .bool(true)])
        }
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return .object(["written": .bool(true)])
    }

    // MARK: Workspace files (paths restricted to workspaces/<flowId>)

    public static func workspaceURL(flowId: String) -> URL {
        TBPaths.homeDir.appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(flowId, isDirectory: true)
    }

    private func sandboxedURL(path: String, ctx: JSONValue) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else {
            throw TBError.validation("file action 'path' must be relative to the flow workspace and cannot contain '..'")
        }
        guard let flowId = ctx["config.flowId"]?.stringValue, !flowId.isEmpty else {
            throw TBError.validation("file action requires ctx.config.flowId")
        }
        return Self.workspaceURL(flowId: flowId).appendingPathComponent(path)
    }

    private func fileRead(params: JSONValue, ctx: JSONValue, dryRun: Bool) throws -> JSONValue {
        if dryRun { return .object(["dryRun": .bool(true)]) }
        guard let path = params["path"]?.stringValue else {
            throw TBError.validation("fileRead requires 'path'")
        }
        let url = try sandboxedURL(path: path, ctx: ctx)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw TBError.notFound("workspace file \(path)")
        }
        return .object(["path": .string(path), "content": .string(String(decoding: data.prefix(1_000_000), as: UTF8.self))])
    }

    private func fileWrite(params: JSONValue, ctx: JSONValue, dryRun: Bool) throws -> JSONValue {
        guard let path = params["path"]?.stringValue else {
            throw TBError.validation("fileWrite requires 'path'")
        }
        guard let content = params["content"]?.stringValue else {
            throw TBError.validation("fileWrite requires 'content'")
        }
        let url = try sandboxedURL(path: path, ctx: ctx)
        if dryRun {
            return .object(["dryRun": .bool(true), "path": .string(url.path)])
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url, options: .atomic)
        return .object(["path": .string(url.path), "bytes": .int(Int64(content.utf8.count))])
    }

    // MARK: Process execution

    private func runProcess(launchPath: String, arguments: [String], timeoutMs: Int) async throws -> JSONValue {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        // The timeout task kills the process; once dead, pipes hit EOF and the read task returns naturally (avoids a group-wait deadlock)
        let killerTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(clamping: timeoutMs) * 1_000_000)
            guard !Task.isCancelled, process.isRunning else { return }
            process.terminate()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        let outData = try? outPipe.fileHandleForReading.readToEnd()
        let errData = try? errPipe.fileHandleForReading.readToEnd()
        killerTask.cancel()
        process.waitUntilExit()

        var timedOut = false
        if process.terminationReason == .uncaughtSignal { timedOut = true }
        let stdout = outData.map { String(decoding: $0.prefix(100_000), as: UTF8.self) } ?? ""
        let stderr = errData.map { String(decoding: $0.prefix(100_000), as: UTF8.self) } ?? ""

        if timedOut {
            throw TBError.timeout("shell command exceeded \(timeoutMs)ms: \(arguments.joined(separator: " "))")
        }
        return .object([
            "exitCode": .int(Int64(process.terminationStatus)),
            "stdout": .string(stdout),
            "stderr": .string(stderr),
        ])
    }
}

// MARK: - Timeout utilities

public func withTimeoutMs<T: Sendable>(
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
