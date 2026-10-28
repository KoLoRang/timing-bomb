import SwiftUI
import TimingBombCore
import TimingBombL10n

// MARK: - Runs page

struct RunsView: View {
    @State private var runs: [RunRecord] = []
    @State private var selectedRunId: String?
    @State private var filterFlowId = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var confirmDeleteSelected = false
    @State private var confirmClearAll = false

    var body: some View {
        HStack(spacing: 0) {
            runList.frame(width: 330)
            Divider()
            if let runId = selectedRunId {
                RunDetailView(runId: runId)
                    .id(runId)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text(L10n.t("Select a run on the left to view details"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await reload() }
        .alert(L10n.t("Delete this run record?"), isPresented: $confirmDeleteSelected) {
            Button(L10n.t("Delete"), role: .destructive) {
                Task { await deleteSelected() }
            }
            Button(L10n.t("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("This cannot be undone: {runId}", ["runId": selectedRunId ?? ""]))
        }
        .alert(
            confirmClearScope.isEmpty
                ? L10n.t("Clear all run records?")
                : L10n.t("Clear run records for {scope}?", ["scope": confirmClearScope]),
            isPresented: $confirmClearAll)
        {
            Button(L10n.t("Clear"), role: .destructive) {
                Task { await clearAll() }
            }
            Button(L10n.t("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("This cannot be undone (running tasks are not affected)"))
        }
    }

    private var confirmClearScope: String {
        filterFlowId.trimmingCharacters(in: .whitespaces)
    }

    private var runList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.t("Runs")).font(.headline)
                Spacer()
                TextField(L10n.t("Filter by flow"), text: $filterFlowId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit { Task { await reload() } }
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L10n.t("Refresh"))
                Button {
                    guard selectedRunId != nil else { return }
                    confirmDeleteSelected = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(selectedRunId == nil)
                .help(L10n.t("Delete the selected run record"))
                Button {
                    confirmClearAll = true
                } label: {
                    Image(systemName: "trash.slash")
                }
                .buttonStyle(.borderless)
                .disabled(runs.isEmpty)
                .help(
                    confirmClearScope.isEmpty
                        ? L10n.t("Clear all run records")
                        : L10n.t("Clear run records of the filtered flow"))
                .padding(.trailing, 10)
            }
            .padding(.vertical, 8)

            if loading && runs.isEmpty {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else if runs.isEmpty {
                Spacer()
                Text(errorMessage ?? L10n.t("No run records yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selectedRunId) {
                    ForEach(runs) { run in
                        RunListRow(run: run)
                            .tag(run.id)
                            .contextMenu {
                                Button(L10n.t("Delete this record"), role: .destructive) {
                                    selectedRunId = run.id
                                    confirmDeleteSelected = true
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func deleteSelected() async {
        guard let runId = selectedRunId else { return }
        do {
            try await TBAPIClient.deleteRun(id: runId)
            selectedRunId = nil
            await reload()
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func clearAll() async {
        do {
            let scope = confirmClearScope
            _ = try await TBAPIClient.deleteRuns(flowId: scope.isEmpty ? nil : scope)
            selectedRunId = nil
            await reload()
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func reload() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            runs = try await TBAPIClient.runs(
                flowId: filterFlowId.isEmpty ? nil : filterFlowId, limit: 100)
            if let selected = selectedRunId, !runs.contains(where: { $0.id == selected }) {
                selectedRunId = nil
            }
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

struct RunListRow: View {
    let run: RunRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                statusIcon(run.status)
                Text(run.flowId)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(Presentation.triggerName(run.trigger.type))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(run.status.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor(run.status))
                Text(Presentation.dateFormatter.string(from: run.startedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let ended = run.endedAt {
                    Text(
                        Presentation.format(
                            durationMs: ended.timeIntervalSince(run.startedAt) * 1000)
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusIcon(_ status: RunStatus) -> some View {
        switch status {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .timeout:
            Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
        case .cancelled:
            Image(systemName: "minus.circle.fill").foregroundStyle(.gray)
        case .running, .pending:
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
        case .awaitingApproval:
            Image(systemName: "hourglass.circle").foregroundStyle(.orange)
        }
    }

    private func statusColor(_ status: RunStatus) -> Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .timeout: return .orange
        case .cancelled: return .gray
        case .running, .pending: return .blue
        case .awaitingApproval: return .orange
        }
    }
}

// MARK: - Run detail

struct RunDetailView: View {
    let runId: String

    @State private var run: RunRecord?
    @State private var flow: FlowDefinition?
    @State private var errorMessage: String?
    @State private var selectedNodeId: String?
    @State private var selectedRecordId: String?
    @State private var showContextSheet = false

    var body: some View {
        Group {
            if let run {
                content(run)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title).foregroundStyle(.orange)
                    Text(errorMessage).font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .sheet(isPresented: $showContextSheet) {
            if let run { contextSheet(run) }
        }
    }

    private func content(_ run: RunRecord) -> some View {
        VStack(spacing: 0) {
            header(run)
            if let error = run.error {
                errorBanner(error)
            }
            Divider()
            if let flow {
                VSplitView {
                    graphPane(flow: flow, run: run)
                    nodeIOPane(flow: flow, run: run)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 34))
                        .foregroundStyle(.tertiary)
                    Text(L10n.t("The flow definition for this run could not be found"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Top: the whole flow graph

    private func graphPane(flow: FlowDefinition, run: RunRecord) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.t("Flow graph · click a node to view its input / output"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.t("{count} node execution(s) in total", ["count": String(run.nodeRuns.count)]))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()
            FlowGraphView(
                flow: flow,
                statusByNode: statusByNode(run),
                selectedNodeId: selectedNodeId
            ) { node in
                selectedNodeId = node.id
                selectedRecordId = nil
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220, maxHeight: .infinity)
    }

    // MARK: Bottom: input / output of the selected node (two stacked panes)

    private func nodeIOPane(flow: FlowDefinition, run: RunRecord) -> some View {
        let records = selectedNodeId.map { Self.records(of: $0, in: run) } ?? []
        let selected = records.first { $0.id == selectedRecordId } ?? records.last

        return VStack(spacing: 0) {
            ioHeader(flow: flow, records: records, selected: selected)
            Divider()
            if let selected {
                VSplitView {
                    inputPane(selected)
                    outputPane(selected)
                }
            } else if let nodeId = selectedNodeId {
                VStack(spacing: 8) {
                    Image(systemName: "zzz")
                        .font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text(
                        L10n.t(
                            "Node “{name}” has no execution record in this run",
                            ["name": displayName(of: nodeId, flow: flow)]))
                        .font(.callout)
                    Text(L10n.t("The flow may have taken another branch, or ended before reaching it"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text(L10n.t("Click a node in the flow graph above"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(L10n.t("Its input and output will appear below in two panes"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180, maxHeight: .infinity)
    }

    private func ioHeader(
        flow: FlowDefinition, records: [NodeRunRecord], selected: NodeRunRecord?
    ) -> some View {
        HStack(spacing: 10) {
            if let nodeId = selectedNodeId {
                Image(systemName: "target")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName(of: nodeId, flow: flow))
                        .font(.system(size: 12, weight: .semibold))
                    Text(nodeId)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(L10n.t("No node selected")).font(.caption).foregroundStyle(.tertiary)
            }

            Spacer()

            if records.count > 1, let selected {
                Menu {
                    ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                        Button(
                            L10n.t(
                                "#{index} · {status}",
                                [
                                    "index": String(index + 1),
                                    "status": record.status.rawValue,
                                ])
                                + (record.iteration.map { " · iter \($0)" } ?? "")
                        ) {
                            selectedRecordId = record.id
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text(Self.execLabel(record: selected, in: records))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(
                    L10n.t(
                        "This node ran {count} time(s) in this run; pick which one to view",
                        ["count": String(records.count)]))
            }
            if let selected {
                HStack(spacing: 4) {
                    Circle().fill(Self.recordColor(selected.status)).frame(width: 7, height: 7)
                    Text(selected.status.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Self.recordColor(selected.status))
                }
                if let ended = selected.endedAt {
                    Text(
                        Presentation.format(
                            durationMs: ended.timeIntervalSince(selected.startedAt) * 1000)
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func inputPane(_ record: NodeRunRecord) -> some View {
        pane(
            title: L10n.t("Input"), tint: .blue,
            trailing: record.iteration.map { L10n.t("iter {n}", ["n": String($0)]) }
        ) {
            if let input = record.input {
                JSONScrollText(text: Presentation.prettyJSON(input))
            } else {
                Text(L10n.t("(no input snapshot for this record; it may come from an older TimingBomb version)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func outputPane(_ record: NodeRunRecord) -> some View {
        pane(title: L10n.t("Output"), tint: .green, trailing: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if let output = record.output {
                    JSONScrollText(text: Presentation.prettyJSON(output))
                } else {
                    Text("null")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let error = record.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                ForEach(Array(record.logs.enumerated()), id: \.offset) { _, log in
                    Text("log · \(log)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
        }
    }

    private func pane<Body: View>(
        title: String, tint: Color, trailing: String?, @ViewBuilder body: () -> Body
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(.bold))
                if let trailing {
                    Text(trailing)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            Divider()
            body()
        }
        .frame(minHeight: 70, maxHeight: .infinity)
    }

    // MARK: Trigger payload / final context sheet

    private func contextSheet(_ run: RunRecord) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("Trigger payload & final context")).font(.headline)
                Spacer()
                Button(L10n.t("Close")) { showContextSheet = false }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("payload").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(run.trigger.payload.map { Presentation.prettyJSON($0) } ?? "null")
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("Final context"))
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(run.context.map { Presentation.prettyJSON($0) } ?? "null")
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 600, minHeight: 480)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.octagon")
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08))
    }

    private func header(_ run: RunRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(run.flowName.isEmpty ? run.flowId : run.flowName)
                        .font(.title3.weight(.semibold))
                    Text(run.status.rawValue)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
                HStack(spacing: 8) {
                    Text(L10n.t("Trigger: {type}", ["type": Presentation.triggerName(run.trigger.type)]))
                    Text(runId).font(.system(.caption, design: .monospaced))
                    if let ended = run.endedAt {
                        Text(
                            L10n.t(
                                "Duration {duration}",
                                [
                                    "duration": Presentation.format(
                                        durationMs: ended.timeIntervalSince(run.startedAt) * 1000),
                                ]))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
            Spacer()
            Button {
                showContextSheet = true
            } label: {
                Image(systemName: "curlybraces.square")
            }
            .help(L10n.t("View trigger payload & final context"))
            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L10n.t("Refresh"))
        }
        .padding(12)
    }

    // MARK: Data helpers

    private static func records(of nodeId: String, in run: RunRecord) -> [NodeRunRecord] {
        run.nodeRuns.filter { $0.nodeId == nodeId }
    }

    private func findNode(id: String, in nodes: [FlowNode]) -> FlowNode? {
        for node in nodes {
            if node.id == id { return node }
            if let hit = findNode(id: id, in: node.thenNodes ?? [])
                ?? findNode(id: id, in: node.elseNodes ?? [])
                ?? findNode(id: id, in: node.body ?? [])
            {
                return hit
            }
        }
        return nil
    }

    private func displayName(of nodeId: String, flow: FlowDefinition) -> String {
        let node = findNode(id: nodeId, in: flow.nodes)
        if let name = node?.name, !name.isEmpty { return name }
        return nodeId
    }

    private static func recordColor(_ status: NodeRunStatus) -> Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .timeout: return .orange
        case .cancelled, .skipped: return .gray
        }
    }

    /// Label for the current item in the multi-execution picker, e.g. "#3 · success · iter 2".
    private static func execLabel(record: NodeRunRecord, in records: [NodeRunRecord]) -> String {
        let index = records.firstIndex { $0.id == record.id }.map { $0 + 1 } ?? records.count
        return L10n.t("#{index} · {status}", ["index": String(index), "status": record.status.rawValue])
            + (record.iteration.map { " · iter \($0)" } ?? "")
    }

    private func statusByNode(_ run: RunRecord) -> [String: NodeStatusInfo] {
        var grouped: [String: [NodeRunStatus]] = [:]
        for record in run.nodeRuns {
            grouped[record.nodeId, default: []].append(record.status)
        }
        var result: [String: NodeStatusInfo] = [:]
        for (nodeId, statuses) in grouped {
            let worst = statuses.min { rankOf($0) < rankOf($1) } ?? .success
            result[nodeId] = NodeStatusInfo(status: worst, executions: statuses.count)
        }
        return result
    }

    private func rankOf(_ status: NodeRunStatus) -> Int {
        switch status {
        case .failed: return 0
        case .timeout: return 1
        case .cancelled: return 2
        case .success: return 3
        case .skipped: return 4
        }
    }

    private func load() async {
        errorMessage = nil
        do {
            run = try await TBAPIClient.run(id: runId)
            if let flowId = run?.flowId, flow?.id != flowId {
                let flows = (try? await TBAPIClient.flows()) ?? []
                flow = flows.first { $0.id == flowId }?.flow
            }
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

/// Monospaced JSON text with independent scrolling; shared by the input/output panes.
struct JSONScrollText: View {
    let text: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }
}
