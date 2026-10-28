import SwiftUI
import TimingBombCore
import TimingBombL10n

// MARK: - Flows page

struct FlowsView: View {
    @State private var items: [FlowItemDTO] = []
    @State private var selectedFlowId: String?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var showNewFlow = false

    var body: some View {
        HStack(spacing: 0) {
            flowList
                .frame(width: 260)
            Divider()
            detail
        }
        .task { await reload() }
        .sheet(isPresented: $showNewFlow) {
            NewFlowSheet { id in
                Task { await reload(select: id) }
            }
        }
    }

    private var flowList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("Flows")).font(.headline).padding(.leading, 12)
                Spacer()
                Button {
                    showNewFlow = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(L10n.t("New flow"))
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L10n.t("Refresh"))
                .padding(.trailing, 10)
            }
            .padding(.vertical, 8)

            if loading && items.isEmpty {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else if items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text(errorMessage ?? L10n.t("No flows yet\nClick + to create, or import with tb flow create"))
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                Spacer()
            } else {
                List(selection: $selectedFlowId) {
                    ForEach(items) { item in
                        FlowListRow(item: item)
                            .tag(item.id)
                            .contextMenu {
                                Button(L10n.t("Delete"), role: .destructive) {
                                    Task { await delete(item) }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let item = items.first(where: { $0.id == selectedFlowId }) {
            FlowDetailView(item: item) {
                Task { await reload() }
            }
            .id(item.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "square.grid.3x3.square")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text(L10n.t("Select a flow on the left to view its workflow"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reload(select id: String? = nil) async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            items = try await TBAPIClient.flows()
            if let id {
                selectedFlowId = id
            } else if selectedFlowId != nil, !items.contains(where: { $0.id == selectedFlowId }) {
                selectedFlowId = items.first?.id
            } else if selectedFlowId == nil {
                selectedFlowId = items.first?.id
            }
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func delete(_ item: FlowItemDTO) async {
        do {
            try await TBAPIClient.deleteFlow(id: item.id)
            await reload()
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

struct FlowListRow: View {
    let item: FlowItemDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.flow.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                TriggerBadge(flow: item.flow)
                Text(L10n.t("{count} node(s)", ["count": String(item.flow.nodes.count)]))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct TriggerBadge: View {
    let flow: FlowDefinition

    private var info: (text: String, detail: String?) {
        Presentation.triggerBadge(flow)
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(info.text)
                .font(.caption2.weight(.medium))
            if let detail = info.detail {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch flow.trigger?.type ?? .manual {
        case .schedule: return .orange
        case .webhook: return .blue
        case .fileWatch: return .indigo
        case .manual: return .gray
        }
    }
}

// MARK: - Flow detail

struct FlowDetailView: View {
    let item: FlowItemDTO
    let onListChanged: () -> Void

    @State private var draft: FlowDefinition
    @State private var dirty = false
    @State private var saving = false
    @State private var saveError: String?
    @State private var saveIssues: [ValidationIssue] = []
    @State private var editingNode: FlowNode?
    @State private var showRunSheet = false
    @State private var runFeedback: String?

    init(item: FlowItemDTO, onListChanged: @escaping () -> Void) {
        self.item = item
        self.onListChanged = onListChanged
        _draft = State(initialValue: item.flow)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if saveError != nil {
                errorBanner
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    triggerSection
                    Divider()
                    Text(L10n.t("Workflow · click a node to edit"))
                        .font(.headline)
                    FlowGraphView(flow: draft) { node in
                        editingNode = node
                    }
                    .frame(minHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.quinary, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
        }
        .sheet(item: $editingNode) { node in
            NodeEditorView(
                node: node,
                onSave: { updated in
                    if FlowTree.replace(in: &draft.nodes, id: updated.id, with: updated) {
                        dirty = true
                    }
                    editingNode = nil
                },
                onDismiss: { editingNode = nil }
            )
        }
        .sheet(isPresented: $showRunSheet) {
            RunFlowSheet(flowId: draft.id) { message in
                runFeedback = message
                showRunSheet = false
            }
        }
        .alert(L10n.t("Triggered"), isPresented: Binding(
            get: { runFeedback != nil },
            set: { if !$0 { runFeedback = nil } }
        )) {
            Button(L10n.t("OK")) {}
        } message: {
            Text(runFeedback ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TextField(L10n.t("Flow name"), text: $draft.name)
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onChange(of: draft.name) { _, _ in dirty = true }
                HStack(spacing: 6) {
                    Text(draft.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TriggerBadge(flow: draft)
                }
            }
            Spacer()
            if dirty {
                Text(L10n.t("Unsaved")).font(.caption).foregroundStyle(.orange)
            }
            Button {
                Task { await save() }
            } label: {
                if saving {
                    ProgressView().controlSize(.small)
                } else {
                    Text(L10n.t("Save changes"))
                }
            }
            .disabled(!dirty || saving)
            Button(L10n.t("Run now")) { showRunSheet = true }
        }
        .padding(12)
    }

    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message = saveError {
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
            }
            ForEach(Array(saveIssues.enumerated()), id: \.offset) { _, issue in
                Text("[\(issue.level.rawValue)] \(issue.path): \(issue.localizedMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(L10n.t("Trigger")).font(.headline)
                Picker("", selection: triggerTypeBinding) {
                    Text(L10n.t("Manual")).tag("manual")
                    Text(L10n.t("Webhook")).tag("webhook")
                    Text(L10n.t("Schedule")).tag("schedule")
                    Text(L10n.t("File watch")).tag("fileWatch")
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                if isSchedule {
                    TextField(L10n.t("cron (e.g. 0 9 * * 1-5)"), text: cronBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .font(.system(.caption, design: .monospaced))
                    Picker("", selection: misfireBinding) {
                        Text(L10n.t("Skip missed")).tag("skip")
                        Text(L10n.t("Catch up once")).tag("fireOnce")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                } else if isWebhook {
                    Text("POST /hooks/\(draft.id)")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if isFileWatch {
                    TextField(L10n.t("Watched directory (e.g. ~/Downloads/inbox)"), text: watchPathBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .font(.system(.caption, design: .monospaced))
                }
                Spacer()
            }
            if isFileWatch {
                Text(L10n.t("Fires on file create/modify/delete inside the directory (recursive, 2.5s debounce)"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Text(L10n.t("Description")).font(.headline)
                TextField(
                    L10n.t("Optional"),
                    text: Binding(
                        get: { draft.description ?? "" },
                        set: { draft.description = $0.isEmpty ? nil : $0; dirty = true }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Spacer()
            }
        }
    }

    private var isSchedule: Bool { draft.trigger?.type == .schedule }
    private var isWebhook: Bool { draft.trigger?.type == .webhook }
    private var isFileWatch: Bool { draft.trigger?.type == .fileWatch }

    private var triggerTypeBinding: Binding<String> {
        Binding(
            get: { draft.trigger?.type?.rawValue ?? "manual" },
            set: { newValue in
                if draft.trigger == nil {
                    draft.trigger = TriggerConfig(type: TriggerType(rawValue: newValue))
                } else {
                    draft.trigger?.type = TriggerType(rawValue: newValue)
                }
                dirty = true
            }
        )
    }

    private var cronBinding: Binding<String> {
        Binding(
            get: { draft.trigger?.cron ?? "" },
            set: { newValue in
                if draft.trigger == nil { draft.trigger = TriggerConfig() }
                draft.trigger!.cron = newValue.isEmpty ? nil : newValue
                dirty = true
            }
        )
    }

    private var misfireBinding: Binding<String> {
        Binding(
            get: { draft.trigger?.misfire ?? "skip" },
            set: { newValue in
                if draft.trigger == nil { draft.trigger = TriggerConfig() }
                draft.trigger!.misfire = newValue == "fireOnce" ? "fireOnce" : "skip"
                dirty = true
            }
        )
    }

    private var watchPathBinding: Binding<String> {
        Binding(
            get: { draft.trigger?.path ?? "" },
            set: { newValue in
                if draft.trigger == nil { draft.trigger = TriggerConfig() }
                draft.trigger!.path = newValue.isEmpty ? nil : newValue
                dirty = true
            }
        )
    }

    private func save() async {
        saving = true
        saveError = nil
        saveIssues = []
        defer { saving = false }
        do {
            _ = try await TBAPIClient.saveFlow(draft)
            dirty = false
            onListChanged()
        } catch let error as APIClientError {
            saveError = error.rendered
            saveIssues = error.issues
        } catch {
            saveError = String(describing: error)
        }
    }
}

// MARK: - New flow sheet

struct NewFlowSheet: View {
    let onCreated: (String) -> Void

    @State private var flowId = ""
    @State private var flowName = ""
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("New Flow")).font(.headline).padding(12)
            Divider()
            ScrollView {
                Form {
                    TextField(
                        L10n.t("Flow ID (letters/digits/._-, e.g. daily-report)"),
                        text: $flowId
                    )
                    .font(.system(.body, design: .monospaced))
                    TextField(L10n.t("Flow name"), text: $flowName)
                    Text(L10n.t("Creates a flow with one skeleton code node. After saving, click the node to edit its JS."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
                .frame(minHeight: 120)
                .padding(.vertical, 2)
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
            }
            Divider()
            HStack {
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.t("Create")) { Task { await create() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(creating || flowId.isEmpty || flowName.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 400, idealWidth: 440, minHeight: 240, idealHeight: 280)
    }

    private func create() async {
        errorText = nil
        creating = true
        defer { creating = false }
        let skeleton = FlowDefinition(
            id: flowId.trimmingCharacters(in: .whitespaces),
            name: flowName,
            trigger: TriggerConfig(type: .manual),
            nodes: [
                FlowNode(
                    id: "step1", type: .code, name: L10n.t("Step 1"),
                    code: """
                    async function run(ctx) {
                      const payload = ctx.trigger.payload || {};
                      // TODO: your logic here
                      return { ok: true };
                    }
                    """)
            ])
        do {
            _ = try await TBAPIClient.saveFlow(skeleton)
            dismiss()
            onCreated(skeleton.id)
        } catch let error as APIClientError {
            errorText = error.rendered
            if !error.issues.isEmpty {
                errorText = (errorText ?? "") + "\n"
                    + error.issues.map { "\($0.path): \($0.localizedMessage)" }.joined(separator: "\n")
            }
        } catch {
            errorText = String(describing: error)
        }
    }
}

// MARK: - Run sheet

struct RunFlowSheet: View {
    let flowId: String
    let onLaunched: (String) -> Void

    @State private var payloadText = "{\n  \n}"
    @State private var dryRun = false
    @State private var errorText: String?
    @State private var launching = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("Run · {flowId}", ["flowId": flowId])).font(.headline).padding(12)
            Divider()
            ScrollView {
                Form {
                    Section(L10n.t("Input payload (injected as ctx.trigger.payload; optional)")) {
                        TextEditor(text: $payloadText)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .background(.quinary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Section {
                        Toggle(L10n.t("Dry-run (no real side effects)"), isOn: $dryRun)
                    }
                }
                .formStyle(.grouped)
                .padding(.vertical, 4)
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
            }
            Divider()
            HStack {
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(dryRun ? L10n.t("Dry-run") : L10n.t("Launch")) { Task { await launch() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(launching)
            }
            .padding(10)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 320, idealHeight: 380)
    }

    private func launch() async {
        errorText = nil
        var payload: JSONValue? = nil
        let text = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            guard let value = try? TBJSON.decode(JSONValue.self, from: text) else {
                errorText = L10n.t("payload is not valid JSON")
                return
            }
            payload = value
        }
        launching = true
        defer { launching = false }
        do {
            let runId = try await TBAPIClient.startRun(
                flowId: flowId, payload: payload, dryRun: dryRun)
            dismiss()
            onLaunched(
                dryRun
                    ? L10n.t("Dry-run {runId} started (no side effects). See the Runs page", ["runId": runId])
                    : L10n.t("Run {runId} started. See the Runs page for progress", ["runId": runId]))
        } catch let error as APIClientError {
            errorText = error.rendered
        } catch {
            errorText = String(describing: error)
        }
    }
}

extension FlowNode: Identifiable {}
