import Foundation
import ServiceManagement
import TimingBombL10n

/// Launch-at-login toggle (SMAppService login item). Not registered after install;
/// only written to the system login items when the user flips the switch in Settings.
@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var statusText = L10n.t("Not enabled")
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            enabled = true
            statusText = L10n.t("Enabled · TimingBomb opens and starts the service at login")
        case .requiresApproval:
            enabled = false
            statusText = L10n.t("Awaiting approval · allow TimingBomb in System Settings → General → Login Items")
        case .notRegistered:
            enabled = false
            statusText = L10n.t("Not enabled")
        case .notFound:
            enabled = false
            statusText = L10n.t("App not found; make sure TimingBomb.app was not moved")
        @unknown default:
            enabled = false
            statusText = L10n.t("Unknown state")
        }
    }

    func setEnabled(_ on: Bool) {
        lastError = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = L10n.t("Setting failed: {detail}", ["detail": error.localizedDescription])
        }
        refresh()
    }
}

/// Copies the bundled timingbomb skill to ~/.agents/skills/timingbomb, then
/// links it into agent CLI skill directories that already exist
/// (~/.claude/skills, ~/.codex/skills, ...). Directories that do not exist are
/// left untouched, so only agents the user actually runs see the skill.
enum SkillInstaller {
    struct InstallResult {
        /// Agent dirs (relative to ~) that now hold a timingbomb symlink.
        var linked: [String] = []
        /// Agent dirs skipped because a non-symlink entry named timingbomb exists there.
        var skipped: [String] = []
    }

    enum InstallError: LocalizedError {
        case sourceMissing

        var errorDescription: String? {
            L10n.t("Skill source not found (must run from TimingBomb.app or the repo checkout)")
        }
    }

    /// Canonical copy of the skill; all agent-dir symlinks point here.
    static var destinationURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agents/skills/timingbomb")
    }

    /// Agent skill directories (relative to ~) that receive a symlink when present.
    static let agentSkillDirs = [
        ".claude/skills", ".codex/skills", ".cursor/skills",
        ".gemini/skills", ".qwen/skills", ".iflow/skills",
    ]

    /// Bundled skill source: the app bundle first, the repo checkout second
    /// (covers `swift run TimingBombApp`, where the binary sits in .build/debug).
    static func bundledSkillURL() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Skills/timingbomb"),
            Bundle.main.bundleURL
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Skills/timingbomb"),
        ].compactMap { $0 }
        return candidates.first { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    static func isInstalled() -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: destinationURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func install() throws -> InstallResult {
        let fileManager = FileManager.default
        guard let source = bundledSkillURL() else { throw InstallError.sourceMissing }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try copyTree(from: source, to: destinationURL)

        var result = InstallResult()
        for dir in agentSkillDirs {
            let dirURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(dir)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue
            else { continue }
            let linkURL = dirURL.appendingPathComponent("timingbomb")
            if isSymlink(linkURL) {
                try fileManager.removeItem(at: linkURL)
            } else if fileManager.fileExists(atPath: linkURL.path) {
                result.skipped.append(dir)
                continue
            }
            try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: destinationURL)
            result.linked.append(dir)
        }
        return result
    }

    static func uninstall() throws {
        let fileManager = FileManager.default
        let canonical = destinationURL.resolvingSymlinksInPath().path
        for dir in agentSkillDirs {
            let linkURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("\(dir)/timingbomb")
            guard isSymlink(linkURL),
                let dest = try? fileManager.destinationOfSymbolicLink(atPath: linkURL.path),
                URL(fileURLWithPath: dest).resolvingSymlinksInPath().path == canonical
            else { continue }
            try fileManager.removeItem(at: linkURL)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Recursive copy that skips Finder metadata (.DS_Store) at every level.
    private static func copyTree(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            guard entry.lastPathComponent != ".DS_Store" else { continue }
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue {
                try copyTree(from: entry, to: target)
            } else {
                try fileManager.copyItem(at: entry, to: target)
            }
        }
    }
}
