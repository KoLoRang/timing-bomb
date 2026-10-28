import SwiftUI
import TimingBombCore
import TimingBombL10n

// MARK: - Approvals page

struct ApprovalsView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case pending
        case history

        var id: String { rawValue }

        var label: String {
            switch self {
            case .pending: return L10n.t("Pending")
            case .history: return L10n.t("History")
            }
        }
    }

    @State private var approvals: [ApprovalRecord] = []
    @State private var segment: Segment = .pending
    @State private var selectedId: String?
    @State private var commentText = ""
    @State private var errorMessage: String?
    @State private var working = false
    @State private var confirmClear = false

    private var pending: [ApprovalRecord] {
        approvals.filter(\.isPending)
    }

    private var history: [ApprovalRecord] {
        approvals.filter { !$0.isPending }
    }

    private var visible: [ApprovalRecord] {
        segment == .pending ? pending : history
    }

    var body: some View {
        HStack(spacing: 0) {
            listColumn.frame(width: 340)
            Divider()
            detail
        }
        .task { await reload() }
        .alert(L10n.t("Clear the whole approval history?"), isPresented: $confirmClear) {
            Button(L10n.t("Clear"), role: .destructive) {
                Task { await clearHistory() }
            }
            Button(L10n.t("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("Deletes all decided approval records (pending ones are kept); this cannot be undone"))
        }
    }

    // MARK: List

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $segment) {
                    ForEach(Segment.allCases) { seg in
                        Text(
                            L10n.t(
                                "{label} ({count})",
                                [
                                    "label": seg.label,
                                    "count": String(seg == .pending ? pending.count : history.count),
                                ]))
                            .tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(L10n.t("Refresh"))
                if segment == .history {
                    Button {
                        confirmClear = true
                    } label: {
                        Image(systemName: "trash.slash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(history.isEmpty)
                    .help(L10n.t("Clear the whole approval history"))
                    .padding(.trailing, 10)
                }
            }
            .padding(.vertical, 8)

            if visible.isEmpty {
                Spacer()
                Text(
                    segment == .pending
                        ? L10n.t("Nothing pending approval")
                        : L10n.t("No approval history yet")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selectedId) {
                    ForEach(visible) { approval in
                        ApprovalRow(approval: approval)
                            .tag(approval.id)
                            .contextMenu {
                                if !approval.isPending {
                                    Button(L10n.t("Delete this record"), role: .destructive) {
                                        Task { await deleteRecord(approval) }
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let approval = visible.first(where: { $0.id == selectedId })
            ?? approvals.first(where: { $0.id == selectedId })
        {
            approvalDetail(approval)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text(L10n.t("Select an approval on the left"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func approvalDetail(_ approval: ApprovalRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(approval.flowName)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    statusBadge(approval)
                }
                if let message = approval.message, !message.isEmpty {
                    Text(message)
                        .font(.body)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quinary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text(L10n.t("Node")).foregroundStyle(.secondary)
                        Text(
                            L10n.t(
                                "{name} ({nodeId})",
                                ["name": approval.nodeName ?? approval.nodeId, "nodeId": approval.nodeId]))
                    }
                    GridRow {
                        Text(L10n.t("Run")).foregroundStyle(.secondary)
                        Text(approval.runId).font(.system(.caption, design: .monospaced))
                    }
                    GridRow {
                        Text(L10n.t("Created")).foregroundStyle(.secondary)
                        Text(Presentation.dateFormatter.string(from: approval.createdAt))
                    }
                    if let decided = approval.decidedAt {
                        GridRow {
                            Text(L10n.t("Decided")).foregroundStyle(.secondary)
                            Text(Presentation.dateFormatter.string(from: decided))
                        }
                    }
                    if let comment = approval.comment {
                        GridRow {
                            Text(L10n.t("Comment")).foregroundStyle(.secondary)
                            Text(comment)
                        }
                    }
                }
                .font(.callout)
                .textSelection(.enabled)

                if approval.isPending {
                    TextField(L10n.t("Comment (optional, stored with the decision)"), text: $commentText)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            Task { await decide(approval, approve: true) }
                        } label: {
                            if working {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(L10n.t("Approve & resume"), systemImage: "checkmark.circle")
                            }
                        }
                        .disabled(working)
                        Button(L10n.t("Reject"), role: .destructive) {
                            Task { await decide(approval, approve: false) }
                        }
                        .disabled(working)
                        Spacer()
                    }
                } else {
                    HStack {
                        Button(L10n.t("Delete this record"), role: .destructive) {
                            Task { await deleteRecord(approval) }
                        }
                        Spacer()
                    }
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(16)
        }
    }

    private func statusBadge(_ approval: ApprovalRecord) -> some View {
        let (text, color): (String, Color) = {
            switch approval.status {
            case "pending": return (L10n.t("Pending"), .orange)
            case "approved": return (L10n.t("Approved"), .green)
            case "rejected": return (L10n.t("Rejected"), .red)
            default: return (approval.status, .gray)
            }
        }()
        return Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: Actions

    private func decide(_ approval: ApprovalRecord, approve: Bool) async {
        working = true
        errorMessage = nil
        defer { working = false }
        do {
            _ = try await TBAPIClient.decideApproval(
                id: approval.id, approve: approve,
                comment: commentText.isEmpty ? nil : commentText)
            commentText = ""
            selectedId = nil
            await reload()
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func deleteRecord(_ approval: ApprovalRecord) async {
        do {
            try await TBAPIClient.deleteApproval(id: approval.id)
            if selectedId == approval.id { selectedId = nil }
            await reload()
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func clearHistory() async {
        do {
            _ = try await TBAPIClient.clearApprovalHistory()
            selectedId = nil
            await reload()
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func reload() async {
        do {
            approvals = try await TBAPIClient.approvals()
            if let selected = selectedId, !approvals.contains(where: { $0.id == selected }) {
                selectedId = nil
            }
        } catch let error as APIClientError {
            errorMessage = error.rendered
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

struct ApprovalRow: View {
    let approval: ApprovalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(approval.flowName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(approval.nodeName ?? approval.nodeId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let message = approval.message, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(Presentation.dateFormatter.string(from: approval.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let comment = approval.comment {
                    Text(L10n.t("Comment: {comment}", ["comment": comment]))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var icon: String {
        switch approval.status {
        case "pending": return "hourglass"
        case "approved": return "checkmark.circle.fill"
        case "rejected": return "xmark.circle.fill"
        default: return "circle"
        }
    }

    private var color: Color {
        switch approval.status {
        case "pending": return .orange
        case "approved": return .green
        case "rejected": return .red
        default: return .gray
        }
    }
}
