import Foundation

/// An independent, reusable snapshot of a node and its complete child tree.
public struct FavoriteNode: Codable, Equatable, Sendable, Identifiable {
    public static let builtInDesktopNotificationID = "builtin-desktop-notification"

    public var id: String
    public var name: String
    public var node: FlowNode
    public var sourceFlowName: String?
    public var createdAt: Date
    public var updatedAt: Date

    public var isBuiltIn: Bool { id == Self.builtInDesktopNotificationID }
    public var canDelete: Bool { !isBuiltIn }

    public init(
        id: String = UUID().uuidString.lowercased(), name: String, node: FlowNode,
        sourceFlowName: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.node = node
        self.sourceFlowName = sourceFlowName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased(),
            name: try container.decode(String.self, forKey: .name),
            node: try container.decode(FlowNode.self, forKey: .node),
            sourceFlowName: try container.decodeIfPresent(String.self, forKey: .sourceFlowName),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? now)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, node, sourceFlowName, createdAt, updatedAt
    }

    /// The built-in desktop notification template shown to every new TimingBomb
    /// installation. It is inserted once by the store migration and remains
    /// editable, but cannot be deleted.
    static func builtInDesktopNotification(now: Date = Date()) -> FavoriteNode {
        FavoriteNode(
            id: builtInDesktopNotificationID,
            name: "桌面通知",
            node: FlowNode(
                id: "desktopNotify",
                type: .action,
                name: "桌面通知",
                inputDescription: "title：通知标题；message：通知正文。默认读取 trigger.payload.title 和 trigger.payload.message。",
                outputDescription: "{notified: true}：已提交桌面通知；dry-run 时返回 {dryRun: true}。",
                action: "notify",
                params: .object([
                    "title": .string("{{trigger.payload.title}}"),
                    "body": .string("{{trigger.payload.message}}"),
                ])),
            sourceFlowName: "TimingBomb 内置",
            createdAt: now,
            updatedAt: now)
    }
}

public enum FavoriteNodeError: Error, LocalizedError, Equatable, Sendable {
    case builtInCannotBeDeleted

    public var errorDescription: String? {
        "Built-in favorite nodes cannot be deleted."
    }
}
