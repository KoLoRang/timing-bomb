import Foundation
import TimingBombCore
import TimingBombL10n

/// Owns the daemon subprocess lifecycle and state polling.
/// The daemon runs as a separate process (timingbombd) and survives app exit;
/// launching at login is LoginItemManager's job — this class only covers "while the app is open".
@MainActor
final class DaemonManager: ObservableObject {
    enum DaemonState: Equatable {
        case checking
        case running(mine: Bool)
        case stopped
    }

    @Published private(set) var state: DaemonState = .checking
    @Published private(set) var daemonVersion: String?
    @Published private(set) var lastError: String?
    @Published var autoStartWithApp: Bool {
        didSet { UserDefaults.standard.set(autoStartWithApp, forKey: "autoStartDaemonWithApp") }
    }

    private var pollTask: Task<Void, Never>?

    static let shared = DaemonManager()

    init() {
        autoStartWithApp =
            UserDefaults.standard.object(forKey: "autoStartDaemonWithApp") as? Bool ?? true
    }

    private var daemonExecutable: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/timingbombd")
    }

    private var pidFileURL: URL {
        TBPaths.homeDir.appendingPathComponent("daemon.pid")
    }

    private var logFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TimingBomb/daemon.log")
    }

    func startLifecycle() {
        FileHandle.standardError.write(Data("[tb-app] startLifecycle autoStart=\(autoStartWithApp)\n".utf8))
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            FileHandle.standardError.write(Data("[tb-app] first refresh -> \(self.state)\n".utf8))
            // Auto-start only when the user opens the app manually (not at login).
            if self.autoStartWithApp, self.state == .stopped {
                self.startDaemon()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self.refresh()
            }
        }
    }

    func refresh() async {
        guard let url = URL(string: "http://127.0.0.1:\(TBPaths.defaultPort)/healthz") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (data, _) = try await URLSession.shared.data(for: request)
            let health = try? TBJSON.decodeData(JSONValue.self, from: data)
            if health?["status"]?.stringValue == "ok" {
                daemonVersion = health?["version"]?.stringValue
                state = .running(mine: isDaemonOurs())
            } else {
                state = .stopped
            }
        } catch {
            state = .stopped
        }
    }

    func startDaemon() {
        FileHandle.standardError.write(Data("[tb-app] startDaemon exe=\(daemonExecutable.path)\n".utf8))
        guard FileManager.default.fileExists(atPath: daemonExecutable.path) else {
            FileHandle.standardError.write(Data("[tb-app] startDaemon: exe missing\n".utf8))
            lastError = L10n.t("daemon executable not found (must run from TimingBomb.app)")
            return
        }
        let process = Process()
        process.executableURL = daemonExecutable
        // The daemon's data directory (also its working directory) must exist first,
        // otherwise spawn fails immediately.
        try? FileManager.default.createDirectory(
            at: TBPaths.homeDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = TBPaths.homeDir

        do {
            try FileManager.default.createDirectory(
                at: logFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logFileURL.path) {
                FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            }
            if let handle = FileHandle(forWritingAtPath: logFileURL.path) {
                handle.seekToEndOfFile()
                process.standardOutput = handle
                process.standardError = handle
            }
            try process.run()
            try? String(process.processIdentifier).write(
                to: pidFileURL, atomically: true, encoding: .utf8)
            lastError = nil
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                await self?.refresh()
            }
        } catch {
            lastError = L10n.t("daemon failed to start: {detail}", ["detail": error.localizedDescription])
        }
    }

    func stopDaemon() {
        if let pidText = try? String(contentsOf: pidFileURL, encoding: .utf8),
            let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
            kill(pid, 0) == 0
        {
            kill(pid, SIGTERM)
            Task.detached {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
        } else {
            // Externally started daemons (e.g. tb serve) are terminated by name.
            let pkill = Process()
            pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            pkill.arguments = ["-x", "timingbombd"]
            try? pkill.run()
        }
        try? FileManager.default.removeItem(at: pidFileURL)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await self?.refresh()
        }
    }

    /// Whether the pid file points at a live process (i.e. the daemon was started by this app).
    private func isDaemonOurs() -> Bool {
        guard let pidText = try? String(contentsOf: pidFileURL, encoding: .utf8),
            let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
            kill(pid, 0) == 0
        else { return false }
        return true
    }

    var logPath: String { logFileURL.path }
}
