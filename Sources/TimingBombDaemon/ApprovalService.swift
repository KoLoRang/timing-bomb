import Foundation
import TimingBombCore
import TimingBombL10n

/// Approval decisions: approve resumes execution from the breakpoint, reject terminates the run.
public actor ApprovalService {
    private let store: Store
    private let runs: RunService
    private let notifier: any Notifying

    public init(store: Store, runs: RunService, notifier: any Notifying) {
        self.store = store
        self.runs = runs
        self.notifier = notifier
    }

    public enum Decision: String {
        case approve = "approved"
        case reject = "rejected"
    }

    /// Handles an approval decision. Returns the approval record after the decision.
    @discardableResult
    public func decide(
        approvalId: String, decision: Decision, comment: String?
    ) async throws -> ApprovalRecord {
        guard let approval = try await store.approval(id: approvalId) else {
            throw TBError.notFound("approval \(approvalId)")
        }
        guard approval.isPending else {
            throw TBApiError(
                status: 400, code: "approvalAlreadyHandled",
                template: "approval was already handled (current status: {status})",
                params: ["status": approval.status])
        }
        guard var run = try await store.run(id: approval.runId) else {
            throw TBError.notFound("run \(approval.runId)")
        }

        let decided = try await store.decideApproval(
            id: approvalId, status: decision.rawValue, comment: comment)
            ?? approval

        switch decision {
        case .approve:
            guard run.status == .awaitingApproval, let path = run.resumePath else {
                throw TBApiError(
                    status: 400, code: "runNotAwaitingApproval",
                    template: "run {runId} is not awaiting approval; cannot resume",
                    params: ["runId": run.id])
            }
            guard let flow = try await store.flow(id: run.flowId) else {
                throw TBError.notFound("flow \(run.flowId)")
            }
            let resume = FlowEngine.ResumeInfo(
                context: run.context ?? .object([:]), path: path,
                priorNodeRuns: run.nodeRuns, startedAt: run.startedAt)
            try await runs.resume(flow: flow, record: run, resume: resume)
        case .reject:
            run.status = .failed
            run.endedAt = Date()
            let commentSuffix = comment.map { L10n.t(": {comment}", ["comment": $0]) } ?? ""
            run.error = L10n.t(
                "approval rejected{commentSuffix} (node {node})",
                ["commentSuffix": commentSuffix, "node": approval.nodeName ?? approval.nodeId])
            try await store.saveRun(run)
            await notifier.notify(
                title: L10n.t("TimingBomb · {name} was rejected", ["name": run.flowName]),
                body: run.error ?? "")
        }
        return decided
    }
}
