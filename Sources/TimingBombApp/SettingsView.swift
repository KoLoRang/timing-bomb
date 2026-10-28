import SwiftUI
import TimingBombCore
import TimingBombL10n

// MARK: - Settings page

struct SettingsView: View {
    @StateObject private var daemon = DaemonManager.shared
    @StateObject private var loginItem = LoginItemManager()
    @State private var appearance = AppearanceMode.stored
    @State private var language = LanguageMode.stored
    @State private var skillInstalled = SkillInstaller.isInstalled()
    @State private var skillError: String?
    @State private var skillNote: String?
    @State private var showAbout = false
    @State private var token: String?
    @State private var tokenCopied = false
    @State private var allowPatterns: [String] = []
    @State private var newPattern = ""
    @State private var allowError: String?
    @State private var loggingEnabled = true
    @State private var loggingError: String?
    @State private var lanAccess = false
    @State private var lanError: String?
    @StateObject private var update = UpdateManager()

    var body: some View {
        ScrollView {
            Form {
                serviceSection
                appearanceSection
                loginItemSection
                loggingSection
                allowlistSection
                skillSection
                connectionSection
                aboutSection
            }
            .formStyle(.grouped)
            .padding()
        }
        .onAppear {
            token = try? String(contentsOf: TBPaths.tokenFileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            skillInstalled = SkillInstaller.isInstalled()
            Task {
                await reloadAllowlist()
                loggingEnabled = (try? await TBAPIClient.loggingEnabled()) ?? true
                lanAccess = (try? await TBAPIClient.lanAccessEnabled()) ?? false
            }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
    }

    // MARK: - Run logging

    private var loggingSection: some View {
        Section(L10n.t("Run Logging")) {
            Toggle(L10n.t("Record run history (source of the Runs page)"), isOn: $loggingEnabled)
                .onChange(of: loggingEnabled) { _, enabled in
                    Task {
                        do {
                            try await TBAPIClient.setLoggingEnabled(enabled)
                            loggingError = nil
                        } catch let error as APIClientError {
                            loggingError = error.rendered
                        } catch {
                            loggingError = String(describing: error)
                        }
                    }
                }
            Text(
                L10n.t(
                    "When off, new runs are not written to history (live results remain visible during the run); existing history is kept and can be deleted on the Runs page"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if let loggingError {
                Text(loggingError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Allowlist

    private var allowlistSection: some View {
        Section(L10n.t("Command Allowlist (shell / appleScript)")) {
            if allowPatterns.isEmpty {
                Text(L10n.t("No rules yet. shell/appleScript actions are denied until allowlisted."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(allowPatterns, id: \.self) { pattern in
                    HStack {
                        Text(pattern)
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Button {
                            Task { await savePatterns(allowPatterns.filter { $0 != pattern }) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                TextField(L10n.t("New rule, e.g. git * or ls"), text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPattern)
                Button(L10n.t("Add"), action: addPattern)
                    .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(L10n.t("Rules: `git status` matches exactly; `git *` matches by prefix; `*` allows everything (be careful)"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let allowError {
                Text(allowError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func addPattern() {
        let pattern = newPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !allowPatterns.contains(pattern) else { return }
        newPattern = ""
        Task { await savePatterns(allowPatterns + [pattern]) }
    }

    private func reloadAllowlist() async {
        allowPatterns = (try? await TBAPIClient.allowlist()) ?? []
    }

    private func savePatterns(_ patterns: [String]) async {
        do {
            try await TBAPIClient.saveAllowlist(patterns)
            allowError = nil
            await reloadAllowlist()
        } catch let error as APIClientError {
            allowError = error.rendered
        } catch {
            allowError = String(describing: error)
        }
    }

    private var serviceSection: some View {
        Section(L10n.t("Service")) {
            HStack(spacing: 8) {
                Circle().fill(daemonColor).frame(width: 10, height: 10)
                Text(daemonStatusText)
                Spacer()
                if let version = daemon.daemonVersion {
                    Text("v\(version)").foregroundStyle(.secondary)
                }
            }
            Toggle(L10n.t("Start the service when TimingBomb opens"), isOn: $daemon.autoStartWithApp)
            HStack {
                switch daemon.state {
                case .running:
                    Button(L10n.t("Stop Service"), role: .destructive, action: daemon.stopDaemon)
                case .stopped:
                    Button(L10n.t("Start Service"), action: daemon.startDaemon)
                case .checking:
                    Button(L10n.t("Start Service")) {}.disabled(true)
                }
                Text(L10n.t("The service runs independently of the window; log {path}", ["path": daemon.logPath]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let error = daemon.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var daemonColor: Color {
        switch daemon.state {
        case .checking: return .orange
        case .running: return .green
        case .stopped: return .gray
        }
    }

    private var daemonStatusText: String {
        switch daemon.state {
        case .checking: return L10n.t("Checking…")
        case .running(mine: true): return L10n.t("Running (managed by this app)")
        case .running(mine: false): return L10n.t("Running (external process, e.g. tb serve)")
        case .stopped: return L10n.t("Stopped")
        }
    }

    private var appearanceSection: some View {
        Section(L10n.t("Appearance")) {
            Picker(L10n.t("Theme"), selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { _, new in
                AppearanceMode.store(new)
            }
            Picker(L10n.t("Language"), selection: $language) {
                ForEach(LanguageMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: language) { _, new in
                LanguageMode.store(new)
            }
        }
    }

    private var loginItemSection: some View {
        Section(L10n.t("Launch at Login")) {
            Toggle(
                L10n.t("Start automatically at macOS login"),
                isOn: Binding(
                    get: { loginItem.enabled },
                    set: { loginItem.setEnabled($0) }
                )
            )
            Text(loginItem.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = loginItem.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var skillSection: some View {
        Section(L10n.t("Skill (timingbomb)")) {
            LabeledContent(L10n.t("Status")) {
                Text(skillInstalled ? L10n.t("Installed") : L10n.t("Not installed"))
                    .foregroundStyle(skillInstalled ? Color.green : Color.secondary)
            }
            LabeledContent(L10n.t("Path")) {
                Text(SkillInstaller.destinationURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            HStack {
                Button(skillInstalled ? L10n.t("Reinstall") : L10n.t("Install Skill"), action: installSkill)
                if skillInstalled {
                    Button(L10n.t("Remove"), role: .destructive) {
                        try? SkillInstaller.uninstall()
                        skillInstalled = SkillInstaller.isInstalled()
                        skillNote = nil
                    }
                }
            }
            Text(
                L10n.t("Copies the bundled timingbomb skill to ~/.agents/skills, then links it into agent skill directories that already exist (~/.claude/skills, ~/.codex/skills, ...); missing directories are left untouched.")
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
            if let skillNote {
                Text(skillNote).font(.caption).foregroundStyle(.secondary)
            }
            if let skillError {
                Text(skillError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func installSkill() {
        do {
            skillError = nil
            let result = try SkillInstaller.install()
            skillInstalled = SkillInstaller.isInstalled()
            var notes: [String] = []
            if !result.linked.isEmpty {
                notes.append(
                    L10n.t("Linked into: {list}", ["list": result.linked.joined(separator: ", ")]))
            }
            if !result.skipped.isEmpty {
                notes.append(
                    L10n.t(
                        "Skipped {list} (timingbomb already exists there and is not a symlink)",
                        ["list": result.skipped.joined(separator: ", ")]))
            }
            if notes.isEmpty {
                notes.append(
                    L10n.t("No agent skill directories found; the skill was only copied to ~/.agents/skills"))
            }
            skillNote = notes.joined(separator: "\n")
        } catch {
            skillNote = nil
            skillError = L10n.t("Install failed: {detail}", ["detail": error.localizedDescription])
        }
    }

    private var connectionSection: some View {
        Section(L10n.t("Connection")) {
            Toggle(L10n.t("Allow LAN access"), isOn: $lanAccess)
                .onChange(of: lanAccess) { _, enabled in
                    Task {
                        do {
                            try await TBAPIClient.setLanAccess(enabled)
                            lanError = nil
                            lanAccess = (try? await TBAPIClient.lanAccessEnabled()) ?? enabled
                        } catch let error as APIClientError {
                            lanError = error.rendered
                            lanAccess = (try? await TBAPIClient.lanAccessEnabled()) ?? !enabled
                        } catch {
                            lanError = String(describing: error)
                        }
                    }
                }
            Text(
                L10n.t(
                    "When on, the API listens on all network interfaces so machines on the LAN can call it (still token-protected); when off, only 127.0.0.1 is accepted"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if let lanError {
                Text(lanError).font(.caption).foregroundStyle(.red)
            }
            LabeledContent(L10n.t("Local API")) {
                Text("http://127.0.0.1:\(TBPaths.defaultPort)")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            LabeledContent(L10n.t("Data Directory")) {
                HStack(spacing: 4) {
                    Text(TBPaths.homeDir.path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button(L10n.t("Open")) {
                        try? FileManager.default.createDirectory(
                            at: TBPaths.homeDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(TBPaths.homeDir)
                    }
                }
            }
            LabeledContent("API Token") {
                HStack(spacing: 4) {
                    Text(token ?? L10n.t("(generated after the service starts)"))
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if token != nil {
                        Button(tokenCopied ? L10n.t("Copied") : L10n.t("Copy")) {
                            if let token {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(token, forType: .string)
                                tokenCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    tokenCopied = false
                                }
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("External trigger example"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    "curl -X POST http://127.0.0.1:\(TBPaths.defaultPort)/hooks/<flowId> \\\n  -H \"Authorization: Bearer <token>\" \\\n  -d '{\"payload\": {}}'"
                )
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var aboutSection: some View {
        Section(L10n.t("About")) {
            LabeledContent(L10n.t("Version")) {
                Text(AppVersion.current)
            }
            updateRows
            Link(L10n.t("Open Releases page"), destination: UpdateManager.releasesPageURL)
            Button(L10n.t("Open About")) { showAbout = true }
        }
    }

    @ViewBuilder
    private var updateRows: some View {
        switch update.state {
        case .idle:
            Button(L10n.t("Check for Updates"), action: update.checkLatest)
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L10n.t("Checking…"))
            }
        case .latest(let version):
            Label(
                L10n.t("Up to date (v{version})", ["version": version]),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        case .noReleases:
            Text(L10n.t("No releases published yet"))
                .foregroundStyle(.secondary)
        case .available(let release):
            LabeledContent(L10n.t("Latest Release")) {
                Text(release.tag)
            }
            if !release.notes.isEmpty {
                Text(release.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .truncationMode(.tail)
            }
            Button(
                L10n.t("Update to {version}", ["version": release.tag]),
                action: update.downloadAndInstall
            )
        case .downloading(let fraction):
            if let fraction {
                ProgressView(value: fraction) {
                    Text(L10n.t("Downloading update…"))
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("Downloading update…"))
                }
            }
        case .installing:
            Label(
                L10n.t("Installing… the app will relaunch shortly"),
                systemImage: "arrow.triangle.2.circlepath"
            )
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
            Button(L10n.t("Check for Updates"), action: update.checkLatest)
        }
    }
}

// MARK: - About page

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "timer.2")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.top, 24)
            Text("TimingBomb")
                .font(.title2.weight(.bold))
            Text(L10n.t("Version {version}", ["version": AppVersion.current]))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                L10n.t(
                    "Mac task automation orchestration: flows are built from code / if / loop / action nodes.\nNode code runs as JavaScript in the built-in system sandbox (zero environment dependencies).\nSupports external API and manual triggers; a CLI (tb) and Skill package provide a unified AI development surface."
                )
            )
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)

            VStack(spacing: 4) {
                LabeledContent(L10n.t("App Location")) {
                    Text(Bundle.main.bundlePath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent(L10n.t("Project Source")) {
                    Link(
                        "github.com/KoLoRang/timing-bomb",
                        destination: URL(string: "https://github.com/KoLoRang/timing-bomb")!)
                }
            }
            .padding(.horizontal, 24)

            Button(L10n.t("OK")) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 18)
        }
        .frame(minWidth: 460, minHeight: 460)
    }
}
