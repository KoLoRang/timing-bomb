import Foundation
import TimingBombL10n

// MARK: - PATH resolution and process execution support

/// The daemon may be launched by Finder/launchd (PATH only /usr/bin:/bin:...),
/// which hides tools like claude and homebrew binaries. All subprocesses uniformly go through this augmented PATH.
public enum ProcessSupport {
    public static func augmentedPATH() -> String {
        var parts: [String] = []
        if let current = ProcessInfo.processInfo.environment["PATH"] {
            parts += current.split(separator: ":").map(String.init)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin", "\(home)/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin", "\(home)/.npm-global/bin",
            "\(home)/.cargo/bin", "\(home)/.volta/bin", "\(home)/.deno/bin",
        ]
        let fileManager = FileManager.default
        for directory in candidates
        where fileManager.fileExists(atPath: directory) {
            parts.append(directory)
        }
        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    public static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = augmentedPATH()
        return environment
    }

    /// Looks up the absolute path of an executable in the augmented PATH.
    public static func lookup(_ tool: String) -> String? {
        if tool.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: tool) ? tool : nil
        }
        for directory in augmentedPATH().split(separator: ":").map(String.init) {
            let path = directory + "/" + tool
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

// MARK: - Subprocess execution (hard kill on timeout)

public enum CoreProcess {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
        public var signaled: Bool
    }

    /// Runs a command and waits for exit/timeout. On timeout, a separate killer task kills the process (once dead, pipes hit EOF and reads return naturally).
    @discardableResult
    public static func run(
        launchPath: String, arguments: [String], stdin: Data? = nil, timeoutMs: Int,
        environment: [String: String]? = nil
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment { process.environment = environment }
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        if let stdin {
            try? inPipe.fileHandleForWriting.write(contentsOf: stdin)
        }
        try? inPipe.fileHandleForWriting.close()

        let killerTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(clamping: timeoutMs) * 1_000_000)
            guard !Task.isCancelled, process.isRunning else { return }
            process.terminate()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        let stdoutData = try? outPipe.fileHandleForReading.readToEnd()
        let stderrData = try? errPipe.fileHandleForReading.readToEnd()
        killerTask.cancel()
        // Skip waitUntilExit: for a child killed by a bare kill() it occasionally never returns; EOF already arrived, so the process is dead
        var waitedNanos = 0
        while process.isRunning, waitedNanos < 2_000_000_000 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            waitedNanos += 50_000_000
        }

        return Result(
            exitCode: process.terminationStatus,
            stdout: stdoutData.map { String(decoding: $0.prefix(200_000), as: UTF8.self) } ?? "",
            stderr: stderrData.map { String(decoding: $0.prefix(100_000), as: UTF8.self) } ?? "",
            signaled: process.terminationReason == .uncaughtSignal)
    }

    /// Runs `zsh -c command` with the augmented PATH, returning {exitCode, stdout, stderr}.
    public static func runZshCommand(
        _ command: String, timeoutMs: Int
    ) async throws -> JSONValue {
        let result = try await run(
            launchPath: "/bin/zsh", arguments: ["-c", command],
            timeoutMs: timeoutMs, environment: ProcessSupport.environment())
        if result.signaled {
            throw TBError.timeout("command exceeded \(timeoutMs)ms: \(command.prefix(120))")
        }
        return .object([
            "exitCode": .int(Int64(result.exitCode)),
            "stdout": .string(result.stdout),
            "stderr": .string(result.stderr),
        ])
    }
}

// MARK: - Multi-language script nodes

public protocol ScriptRunning: Sendable {
    /// language: "python" | "shell" (normalized by the host first). Protocol: receives the context JSON on stdin,
    /// writes the result JSON to stdout (falls back to {raw: stdout} when parsing fails); stderr is captured as logs.
    func run(
        language: String, script: String, ctx: JSONValue, timeoutMs: Int, dryRun: Bool
    ) async throws -> CodeOutcome
}

/// Executes non-JS code nodes in system-interpreter (python3 / zsh) subprocesses.
/// The interpreter path can be overridden with TIMINGBOMB_PYTHON; reports a readable error when no interpreter is found.
public struct SubprocessScriptRunner: ScriptRunning {
    public init() {}

    public static let supportedLanguages: [String] = ["python", "shell"]

    public static func normalize(_ language: String?) -> String {
        switch (language ?? "js").lowercased() {
        case "js", "javascript", "": return "js"
        case "python", "py", "python3": return "python"
        case "shell", "sh", "zsh", "bash": return "shell"
        default: return language?.lowercased() ?? "js"
        }
    }

    public func run(
        language: String, script: String, ctx: JSONValue, timeoutMs: Int, dryRun: Bool
    ) async throws -> CodeOutcome {
        if dryRun {
            return CodeOutcome(
                value: .object(["dryRun": .bool(true), "language": .string(language)]),
                logs: [L10n.t("(dry-run) {language} script not executed", ["language": language])])
        }

        let interpreter: String
        let suffix: String
        switch language {
        case "python":
            interpreter =
                ProcessInfo.processInfo.environment["TIMINGBOMB_PYTHON"]
                ?? ProcessSupport.lookup("python3")
                ?? "/usr/bin/python3"
            suffix = "py"
        case "shell":
            interpreter = "/bin/zsh"
            suffix = "sh"
        default:
            throw TBError.validation("unsupported script language: \(language)")
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tb-script-\(UUID().uuidString).\(suffix)")
        try Data(script.utf8).write(to: scriptURL)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let stdin = try TBJSON.encodeData(ctx)
        let result = try await CoreProcess.run(
            launchPath: interpreter, arguments: [scriptURL.path], stdin: stdin,
            timeoutMs: timeoutMs, environment: ProcessSupport.environment())

        var logs = result.stderr
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0) }
        if logs.count > 200 {
            logs = Array(logs.prefix(200)) + ["... more stderr truncated"]
        }

        if result.signaled {
            throw TBError.timeout("\(language) script exceeded \(timeoutMs)ms")
        }
        guard result.exitCode == 0 else {
            throw TBError.scriptError(
                "\(language) exit \(result.exitCode): \(result.stderr.suffix(500))")
        }

        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
            let value = try? TBJSON.decodeData(JSONValue.self, from: data)
        {
            return CodeOutcome(value: value, logs: logs)
        }
        return CodeOutcome(value: .object(["raw": .string(trimmed)]), logs: logs)
    }
}
