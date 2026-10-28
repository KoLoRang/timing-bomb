import Foundation

// MARK: - Approval model

/// A pending item produced by an approval node: a run suspends at the approval node, awaiting a human approve/reject decision.
public struct ApprovalRecord: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var runId: String
    public var flowId: String
    public var flowName: String
    public var nodeId: String
    public var nodeName: String?
    /// Explanation shown to the approver (from the node's message field)
    public var message: String?
    /// pending | approved | rejected
    public var status: String
    public var comment: String?
    public var createdAt: Date
    public var decidedAt: Date?

    public init(
        id: String, runId: String, flowId: String, flowName: String,
        nodeId: String, nodeName: String?, message: String?,
        status: String = "pending", comment: String? = nil,
        createdAt: Date = Date(), decidedAt: Date? = nil
    ) {
        self.id = id
        self.runId = runId
        self.flowId = flowId
        self.flowName = flowName
        self.nodeId = nodeId
        self.nodeName = nodeName
        self.message = message
        self.status = status
        self.comment = comment
        self.createdAt = createdAt
        self.decidedAt = decidedAt
    }

    public var isPending: Bool { status == "pending" }
}

/// Engine → host approval request (the host persists/notifies and returns the approval id).
public struct ApprovalRequest: Sendable {
    public var runId: String
    public var flowId: String
    public var flowName: String
    public var nodeId: String
    public var nodeName: String?
    public var message: String?

    public init(
        runId: String, flowId: String, flowName: String,
        nodeId: String, nodeName: String?, message: String?
    ) {
        self.runId = runId
        self.flowId = flowId
        self.flowName = flowName
        self.nodeId = nodeId
        self.nodeName = nodeName
        self.message = message
    }
}
