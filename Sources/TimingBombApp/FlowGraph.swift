import SwiftUI
import TimingBombCore
import TimingBombL10n

// MARK: - Layout engine

/// Lays nested node blocks (then/else/body) into top-down graph coordinates.
enum FlowLayoutEngine {
    static let nodeSize = CGSize(width: 208, height: 60)
    static let emptyBranchSize = CGSize(width: 120, height: 30)
    static let vGap: CGFloat = 44
    static let hGap: CGFloat = 36
    static let margin: CGFloat = 24

    struct Box: Identifiable {
        enum Kind { case node, emptyBranch }
        let id: String
        let node: FlowNode?
        let kind: Kind
        let rect: CGRect
    }

    struct Link {
        let from: CGPoint
        let to: CGPoint
        let label: String?
        let dashed: Bool
    }

    struct Result {
        let boxes: [Box]
        let links: [Link]
        let size: CGSize
    }

    static func layout(nodes: [FlowNode]) -> Result {
        var boxes: [Box] = []
        var links: [Link] = []
        let contentSize = placeBlock(nodes, at: CGPoint(x: margin, y: margin), into: &boxes, links: &links)
        let size = CGSize(
            width: contentSize.width + margin * 2, height: contentSize.height + margin * 2)
        return Result(boxes: boxes, links: links, size: size)
    }

    // MARK: Measurement (pure computation)

    /// Child branches of a node: if → then/else; loop → body.
    private static func branches(of node: FlowNode) -> [(label: String?, nodes: [FlowNode]?)] {
        switch node.type {
        case .ifNode:
            return [
                (label: "then", nodes: node.thenNodes ?? []),
                (label: "else", nodes: node.elseNodes ?? []),
            ]
        case .loop:
            return [(label: L10n.t("loop body"), nodes: node.body ?? [])]
        default:
            return []
        }
    }

    private static func subtreeSize(of node: FlowNode) -> CGSize {
        let childBranches = branches(of: node)
        if childBranches.isEmpty { return nodeSize }

        var branchWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        for (index, branch) in childBranches.enumerated() {
            let size = branchSize(branch.nodes)
            branchWidth += size.width
            maxHeight = max(maxHeight, size.height)
            if index < childBranches.count - 1 { branchWidth += hGap }
        }
        return CGSize(
            width: max(nodeSize.width, branchWidth),
            height: nodeSize.height + vGap + maxHeight)
    }

    /// Size of an empty-branch placeholder or a vertical sequence block.
    private static func branchSize(_ nodes: [FlowNode]?) -> CGSize {
        guard let nodes, !nodes.isEmpty else { return emptyBranchSize }
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (index, node) in nodes.enumerated() {
            let size = subtreeSize(of: node)
            width = max(width, size.width)
            height += size.height
            if index < nodes.count - 1 { height += vGap }
        }
        return CGSize(width: width, height: height)
    }

    // MARK: Placement

    @discardableResult
    private static func placeBlock(
        _ nodes: [FlowNode], at origin: CGPoint, into boxes: inout [Box], links: inout [Link]
    ) -> CGSize {
        let blockSize = branchSize(nodes)
        var y = origin.y
        var previousBottom: CGPoint? = nil
        for node in nodes {
            let subtree = subtreeSize(of: node)
            let topLeft = CGPoint(
                x: origin.x + (blockSize.width - subtree.width) / 2, y: y)
            placeNode(node, subtree: subtree, at: topLeft, into: &boxes, links: &links)
            let nodeCenter = CGPoint(x: topLeft.x + subtree.width / 2, y: topLeft.y + nodeSize.height / 2)
            if let previous = previousBottom {
                links.append(
                    Link(
                        from: previous,
                        to: CGPoint(x: nodeCenter.x, y: topLeft.y),
                        label: nil, dashed: false))
            }
            previousBottom = CGPoint(x: nodeCenter.x, y: topLeft.y + nodeSize.height / 2)
            y += subtree.height + vGap
        }
        return blockSize
    }

    private static func placeNode(
        _ node: FlowNode, subtree: CGSize, at topLeft: CGPoint,
        into boxes: inout [Box], links: inout [Link]
    ) {
        let nodeRect = CGRect(
            x: topLeft.x + (subtree.width - nodeSize.width) / 2, y: topLeft.y,
            width: nodeSize.width, height: nodeSize.height)
        boxes.append(Box(id: node.id, node: node, kind: .node, rect: nodeRect))

        let childBranches = branches(of: node)
        guard !childBranches.isEmpty else { return }

        var branchX = topLeft.x + (subtree.width - childrenRowWidth(childBranches)) / 2
        let rowTop = topLeft.y + nodeSize.height
        let anchor = CGPoint(x: nodeRect.midX, y: nodeRect.maxY)
        for branch in childBranches {
            let size = branchSize(branch.nodes)
            let branchCenterX = branchX + size.width / 2
            let branchTopCenter = CGPoint(x: branchCenterX, y: rowTop + vGap)
            links.append(
                Link(
                    from: anchor, to: branchTopCenter, label: branch.label,
                    dashed: branch.nodes?.isEmpty != false))

            if let branchNodes = branch.nodes, !branchNodes.isEmpty {
                _ = placeBlock(
                    branchNodes, at: CGPoint(x: branchX, y: rowTop + vGap),
                    into: &boxes, links: &links)
            } else {
                boxes.append(
                    Box(
                        id: "\(node.id)-empty-\(branch.label ?? "?")", node: nil,
                        kind: .emptyBranch,
                        rect: CGRect(
                            x: branchCenterX - emptyBranchSize.width / 2,
                            y: branchTopCenter.y,
                            width: emptyBranchSize.width, height: emptyBranchSize.height)))
            }
            branchX += size.width + hGap
        }
    }

    private static func childrenRowWidth(
        _ branches: [(label: String?, nodes: [FlowNode]?)]
    ) -> CGFloat {
        var width: CGFloat = 0
        for (index, branch) in branches.enumerated() {
            width += branchSize(branch.nodes).width
            if index < branches.count - 1 { width += hGap }
        }
        return width
    }
}

// MARK: - View

struct NodeStatusInfo {
    let status: NodeRunStatus
    let executions: Int
}

/// Visualizes a workflow as node cards plus links; optional run statuses tint it.
struct FlowGraphView: View {
    let flow: FlowDefinition
    var statusByNode: [String: NodeStatusInfo] = [:]
    var selectedNodeId: String? = nil
    var onTapNode: (FlowNode) -> Void = { _ in }

    var body: some View {
        let layout = FlowLayoutEngine.layout(nodes: flow.nodes)
        ScrollView([.vertical, .horizontal]) {
            ZStack {
                Canvas { context, _ in
                    for link in layout.links {
                        draw(link: link, in: &context)
                    }
                }
                ForEach(layout.boxes) { box in
                    boxView(box)
                        .frame(width: box.rect.width, height: box.rect.height)
                        .position(x: box.rect.midX, y: box.rect.midY)
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
        }
        .background(.background.opacity(0.5))
    }

    @ViewBuilder
    private func boxView(_ box: FlowLayoutEngine.Box) -> some View {
        switch box.kind {
        case .emptyBranch:
            Text(L10n.t("(empty branch)"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.tertiary)
                )
        case .node:
            if let node = box.node {
                NodeCard(
                    node: node, status: statusByNode[node.id],
                    selected: node.id == selectedNodeId
                )
                .onTapGesture { onTapNode(node) }
            }
        }
    }

    private func draw(link: FlowLayoutEngine.Link, in context: inout GraphicsContext) {
        let color = Color.secondary.opacity(0.55)
        let midY = link.from.y + (link.to.y - link.from.y) * 0.5
        var path = Path()
        path.move(to: link.from)
        path.addLine(to: CGPoint(x: link.from.x, y: midY))
        path.addLine(to: CGPoint(x: link.to.x, y: midY))
        path.addLine(to: CGPoint(x: link.to.x, y: link.to.y - 6))

        let style = link.dashed
            ? StrokeStyle(lineWidth: 1, dash: [4, 3])
            : StrokeStyle(lineWidth: 1.4)
        context.stroke(path, with: .color(color), style: style)

        var arrow = Path()
        arrow.move(to: CGPoint(x: link.to.x - 4.5, y: link.to.y - 7))
        arrow.addLine(to: CGPoint(x: link.to.x + 4.5, y: link.to.y - 7))
        arrow.addLine(to: CGPoint(x: link.to.x, y: link.to.y))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))

        if let label = link.label {
            let at = CGPoint(x: (link.from.x + link.to.x) / 2, y: midY - 9)
            context.draw(
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary),
                at: at)
        }
    }
}

struct NodeCard: View {
    let node: FlowNode
    let status: NodeStatusInfo?
    var selected: Bool = false

    private var baseColor: Color {
        status.map { statusColor($0.status) } ?? borderColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: typeIcon)
                    .foregroundStyle(baseColor)
                Text(node.name?.isEmpty == false ? node.name! : node.id)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let status {
                    Image(systemName: statusIcon(status.status))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusColor(status.status))
                }
                if let status, status.executions > 1 {
                    Text("×\(status.executions)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
            Text("\(node.type.rawValue) · \(node.id)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(baseColor.opacity(selected ? 0.20 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : baseColor, lineWidth: selected ? 2.6 : 1.4)
        )
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "target")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color.accentColor))
                    .offset(x: 7, y: -7)
            }
        }
        .contentShape(Rectangle())
    }

    private func statusIcon(_ status: NodeRunStatus) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .timeout: return "clock.badge.exclamationmark"
        case .cancelled, .skipped: return "minus.circle.fill"
        }
    }

    private var typeIcon: String {
        switch node.type {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .ifNode: return "arrow.triangle.branch"
        case .loop: return "arrow.triangle.2.circlepath"
        case .action: return "bolt"
        case .approval: return "hand.raised"
        }
    }

    private var borderColor: Color {
        switch node.type {
        case .code: return .accentColor
        case .ifNode: return .orange
        case .loop: return .purple
        case .action: return .teal
        case .approval: return .yellow
        }
    }

    private func statusColor(_ status: NodeRunStatus) -> Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .timeout: return .orange
        case .cancelled: return .gray
        case .skipped: return .gray
        }
    }
}
