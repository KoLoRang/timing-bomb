import AppKit
import Foundation
import TimingBombL10n

/// App version from the bundle's Info.plist; falls back to 0.1.0 when running
/// as a bare executable (`swift run`) where no Info.plist exists.
enum AppVersion {
    static let current: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        ?? "0.1.0"
}

/// Checks GitHub for the latest TimingBomb release; on demand downloads the
/// arm64 DMG and swaps the running app bundle via a detached install script.
///
/// The repository may be private, so the check/download tries the anonymous
/// GitHub API first and falls back to the `gh` CLI (which carries the user's
/// authentication) when the API returns 404/failure.
@MainActor
final class UpdateManager: ObservableObject {
    enum State {
        case idle
        case checking
        case latest(String)
        case noReleases
        case available(Release)
        /// Download progress as 0...1; nil when the size is unknown.
        case downloading(Double?)
        case installing
        case failed(String)
    }

    struct Release: Identifiable {
        let tag: String
        let name: String
        let notes: String
        let assetName: String?
        let assetURL: URL?
        var id: String { tag }
    }

    enum UpdateError: LocalizedError {
        case http(Int)
        case noAsset
        case notFromAppBundle
        case mountFailed(code: Int32, detail: String)
        case ghFailed(code: Int32, detail: String)
        case noAppInImage

        var errorDescription: String? {
            switch self {
            case .http(let status): return L10n.t("HTTP {status}", ["status": String(status)])
            case .noAsset: return L10n.t("Release has no DMG asset")
            case .notFromAppBundle:
                return L10n.t("In-app update requires running from TimingBomb.app")
            case .mountFailed(let code, let detail):
                return "hdiutil exit \(code): \(detail)"
            case .ghFailed(let code, let detail):
                return L10n.t("gh CLI error (exit {code}): {detail}", ["code": String(code), "detail": detail])
            case .noAppInImage: return L10n.t("No .app found in the downloaded image")
            }
        }
    }

    static let repo = "KoLoRang/timing-bomb"
    static var releasesPageURL: URL { URL(string: "https://github.com/\(repo)/releases")! }

    @Published var state: State = .idle

    // MARK: - Check

    func checkLatest() {
        state = .checking
        Task { await check() }
    }

    private func check() async {
        // Anonymous API: works when the repository is public.
        if let release = await fetchReleaseAnonymously() {
            finishCheck(release)
            return
        }
        // gh CLI fallback: required for private repositories.
        guard let gh = Self.ghBinaryURL() else {
            state = .failed(
                L10n.t(
                    "Update check failed: {detail}",
                    ["detail": L10n.t("GitHub API returned 404 — no Release published yet, or a private repository without a logged-in gh CLI")]))
            return
        }
        do {
            let (code, out, err) = try await Self.run(
                gh, ["api", "repos/\(Self.repo)/releases/latest"])
            if code == 0, let release = Self.parseRelease(out) {
                finishCheck(release)
            } else if code != 0, Self.stderrMentionsNotFound(err) {
                state = .noReleases
            } else {
                state = .failed(
                    L10n.t(
                        "Update check failed: {detail}",
                        ["detail": Self.decoded(err) ?? "gh exit \(code)"]))
            }
        } catch {
            state = .failed(
                L10n.t("Update check failed: {detail}", ["detail": error.localizedDescription]))
        }
    }

    private func finishCheck(_ release: Release) {
        if Self.isNewer(release.tag, than: AppVersion.current) {
            state = .available(release)
        } else {
            state = .latest(AppVersion.current)
        }
    }

    private func fetchReleaseAnonymously() async -> Release? {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return Self.parseRelease(data)
        } catch {
            return nil
        }
    }

    // MARK: - Download & install

    func downloadAndInstall() {
        guard case .available(let release) = state else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            state = .failed(UpdateError.notFromAppBundle.localizedDescription)
            return
        }
        state = .downloading(nil)
        Task { await install(release) }
    }

    private func install(_ release: Release) async {
        do {
            let fileManager = FileManager.default
            let workDir = fileManager.temporaryDirectory
                .appendingPathComponent("TimingBombUpdate-\(release.tag)", isDirectory: true)
            try? fileManager.removeItem(at: workDir)
            try fileManager.createDirectory(at: workDir, withIntermediateDirectories: true)
            let dmg = workDir.appendingPathComponent(release.assetName ?? "TimingBomb.dmg")

            if let assetURL = release.assetURL {
                do {
                    try await download(from: assetURL, to: dmg)
                } catch {
                    // Private repository: browser_download_url needs auth — go through gh.
                    try await downloadViaGH(release, to: dmg)
                }
            } else {
                try await downloadViaGH(release, to: dmg)
            }

            try await mountAndSwap(dmg: dmg, workDir: workDir)

            state = .installing
            // Give the detached swap script a moment to pick up our PID, then exit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            state = .failed(
                L10n.t("Update failed: {detail}", ["detail": error.localizedDescription]))
        }
    }

    private func downloadViaGH(_ release: Release, to destination: URL) async throws {
        guard let gh = Self.ghBinaryURL() else { throw UpdateError.noAsset }
        let (code, _, err) = try await Self.run(
            gh,
            [
                "release", "download", release.tag, "--repo", Self.repo,
                "--pattern", release.assetName ?? "*.dmg",
                "--output", destination.path,
            ])
        guard code == 0 else {
            throw UpdateError.ghFailed(code: code, detail: Self.decoded(err) ?? "")
        }
        guard destination.fileSizeBytes() > 0 else { throw UpdateError.noAsset }
    }

    private func mountAndSwap(dmg: URL, workDir: URL) async throws {
        // Strip the Finder quarantine flag so mounting and relaunching need no approval.
        _ = try? await Self.run(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            ["-d", "com.apple.quarantine", dmg.path])

        let mount = workDir.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let (code, _, err) = try await Self.run(
            URL(fileURLWithPath: "/usr/bin/hdiutil"),
            ["attach", dmg.path, "-mountpoint", mount.path, "-nobrowse", "-readonly", "-quiet"])
        guard code == 0 else {
            throw UpdateError.mountFailed(code: code, detail: Self.decoded(err) ?? "")
        }

        let apps = (try? FileManager.default.contentsOfDirectory(
            at: mount, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" }
        guard let newApp = apps?.first(where: { $0.lastPathComponent == "TimingBomb.app" })
            ?? apps?.first
        else { throw UpdateError.noAppInImage }

        let script = workDir.appendingPathComponent("swap.sh")
        try Self.swapScript().write(to: script, atomically: true, encoding: .utf8)
        _ = try? await Self.run(URL(fileURLWithPath: "/bin/chmod"), ["+x", script.path])

        // Detached: the script survives this process exiting.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path,
            newApp.path,
            mount.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Runs after the app exits: stages the new bundle next to the old one,
    /// swaps, and relaunches. Falls back cleanly if ditto fails.
    private static func swapScript() -> String {
        """
        #!/bin/sh
        # TimingBomb self-update: wait for the old app to exit, then swap bundles.
        APP_PID="$1"; OLD_APP="$2"; NEW_APP="$3"; MNT="$4"

        i=0
        while [ "$i" -lt 150 ] && kill -0 "$APP_PID" 2>/dev/null; do
          sleep 0.2
          i=$((i + 1))
        done

        STAGED="$OLD_APP.update-staged"
        ditto "$NEW_APP" "$STAGED"
        if [ -d "$STAGED" ]; then
          rm -rf "$OLD_APP"
          mv "$STAGED" "$OLD_APP"
          xattr -dr com.apple.quarantine "$OLD_APP" 2>/dev/null
          hdiutil detach "$MNT" -quiet >/dev/null 2>&1
          open "$OLD_APP"
        else
          hdiutil detach "$MNT" -quiet >/dev/null 2>&1
        fi
        """
    }

    // MARK: - Version comparison

    /// Dotted-numeric comparison ("v0.2.1" vs "0.10.0"); non-numeric suffixes
    /// inside a component are ignored, missing components count as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func components(_ version: String) -> [Int] {
            let trimmed = version.dropFirst(version.hasPrefix("v") || version.hasPrefix("V") ? 1 : 0)
            return trimmed.split(separator: ".").map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
        }
        let a = components(candidate)
        let b = components(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - GitHub release JSON

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }

        let tag_name: String
        let name: String?
        let body: String?
        let assets: [Asset]?
    }

    static func parseRelease(_ data: Data) -> Release? {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            return nil
        }
        let assets = release.assets ?? []
        let dmg = assets.first { $0.name.hasSuffix(".dmg") && $0.name.contains("arm64") }
            ?? assets.first { $0.name.hasSuffix(".dmg") }
        return Release(
            tag: release.tag_name,
            name: release.name ?? release.tag_name,
            notes: release.body ?? "",
            assetName: dmg?.name,
            assetURL: dmg.flatMap { URL(string: $0.browser_download_url) })
    }

    // MARK: - Process / shell helpers

    private static let ghCandidates = [
        "/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh",
    ]

    static func ghBinaryURL() -> URL? {
        ghCandidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Runs a subprocess to completion. Pipes are drained before waiting so a
    /// full pipe buffer cannot deadlock the child.
    static func run(_ executable: URL, _ arguments: [String]) async throws
        -> (code: Int32, stdout: Data, stderr: Data)
    {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, out, err)
        }.value
    }

    static func decoded(_ data: Data) -> String? {
        (data.isEmpty ? nil : String(data: data, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stderrMentionsNotFound(_ data: Data) -> Bool {
        guard let text = decoded(data) else { return false }
        return text.contains("Not Found")
    }

    // MARK: - Download with progress

    private func download(from url: URL, to destination: URL) async throws {
        let delegate = DownloadDelegate(
            onProgress: { [weak self] fraction in
                Task { @MainActor in self?.state = .downloading(fraction) }
            })
        _ = try await delegate.download(from: url, to: destination)
    }
}

/// URLSession download delegate that reports progress and hands the finished
/// file back through a continuation.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var session: URLSession?

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func download(from url: URL, to destination: URL) async throws -> URL {
        self.destination = destination
        let session = URLSession(
            configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.session = session
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _: URLSession, downloadTask: URLSessionDownloadTask, didWriteData: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        defer { finishSession() }
        guard
            let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200,
            let destination
        else {
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
            resume(throwing: UpdateManager.UpdateError.http(status))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            resume(returning: destination)
        } catch {
            resume(throwing: error)
        }
    }

    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        defer { finishSession() }
        resume(throwing: error)
    }

    private func resume(returning url: URL) {
        continuation?.resume(returning: url)
        continuation = nil
    }

    private func resume(throwing error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func finishSession() {
        session?.finishTasksAndInvalidate()
        session = nil
    }
}

private extension URL {
    func fileSizeBytes() -> Int64 {
        Int64((try? resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
}
