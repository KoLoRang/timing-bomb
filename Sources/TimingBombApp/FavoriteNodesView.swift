import SwiftUI
import TimingBombCore
import TimingBombL10n

struct FavoriteNodesView: View {
    @State private var favorites: [FavoriteNode] = []
    @State private var selection: String?
    @State private var search = ""
    @State private var loading = false
    @State private var errorText: String?
    @State private var collecting = false
    @State private var deleting: FavoriteNode?
    @ObservedObject private var daemon = DaemonManager.shared

    private var filtered: [FavoriteNode] {
        favorites.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.t("Favorite Nodes")).font(.headline)
                    Spacer()
                    Button { collecting = true } label: { Image(systemName: "plus") }
                        .help(L10n.t("Favorite an existing node"))
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .help(L10n.t("Refresh"))
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 8)
                .padding(.leading, 16)
                .padding(.trailing, 12)
                TextField(L10n.t("Search favorite nodes"), text: $search)
                    .textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 8)
                if loading && favorites.isEmpty {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List(selection: $selection) {
                        ForEach(filtered) { favorite in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(favorite.name, systemImage: "star.fill")
                                    .font(.body.weight(.medium)).lineLimit(1)
                                Text(favorite.node.action ?? favorite.node.language ?? favorite.node.type.rawValue)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .tag(favorite.id)
                            .contextMenu {
                                if favorite.canDelete {
                                    Button(L10n.t("Remove favorite"), role: .destructive) { deleting = favorite }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                .padding(.horizontal, 8)
                }
            }
            .frame(width: AppLayout.listColumnWidth)
            Divider()
            VStack(spacing: 0) {
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                if let favorite = favorites.first(where: { $0.id == selection }) {
                    FavoriteNodeDetail(favorite: favorite, onUpdated: { updated in
                        Task { await reload(select: updated.id) }
                    }, onDelete: { deleting = favorite })
                    .id(favorite.id)
                } else {
                    ContentUnavailableView {
                        Label(L10n.t("Reusable nodes"), systemImage: "star")
                    } description: {
                        Text(L10n.t("Save configured nodes here, then reuse them in other flows."))
                    } actions: {
                        Button(L10n.t("Favorite an existing node")) { collecting = true }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await reload() }
        .onChange(of: daemon.isRunning) { _, running in
            if running { Task { await reload() } }
        }
        .sheet(isPresented: $collecting) {
            CollectNodeSheet { saved in Task { await reload(select: saved.id) } }
        }
        .alert(L10n.t("Remove favorite?"), isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button(L10n.t("Cancel"), role: .cancel) { deleting = nil }
            Button(L10n.t("Remove favorite"), role: .destructive) {
                guard let item = deleting, item.canDelete else { return }
                Task {
                    do { try await TBAPIClient.deleteFavorite(id: item.id); await reload() }
                    catch { errorText = nodeLibraryError(error) }
                    deleting = nil
                }
            }
        } message: {
            Text(L10n.t("Copies already added to flows will be kept."))
        }
    }

    private func reload(select id: String? = nil) async {
        loading = true
        defer { loading = false }
        do {
            favorites = try await TBAPIClient.favorites()
            errorText = nil
            if let id { selection = id }
            if !favorites.contains(where: { $0.id == selection }) { selection = favorites.first?.id }
        } catch { errorText = nodeLibraryError(error) }
    }
}

private struct FavoriteNodeDetail: View {
    let favorite: FavoriteNode
    let onUpdated: (FavoriteNode) -> Void
    let onDelete: () -> Void
    @State private var selectedNodeID: String?
    @State private var editing: FlowNode?
    @State private var adding = false
    @State private var errorText: String?
    @State private var feedback: String?
    @State private var saving = false

    private var selectedNode: FlowNode {
        FlowTree.find(in: [favorite.node], id: selectedNodeID ?? favorite.node.id) ?? favorite.node
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.name).font(.title3.weight(.semibold))
                    if favorite.isBuiltIn {
                        Label(L10n.t("Built-in favorite · Cannot be deleted"), systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let source = favorite.sourceFlowName {
                        Text(L10n.t("Saved from {name}", ["name": source]))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(L10n.t("Edit Node")) { errorText = nil; editing = selectedNode }
                Button(L10n.t("Add to flow")) { adding = true }
                if favorite.canDelete {
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .help(L10n.t("Remove favorite"))
                }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let errorText { Text(errorText).foregroundStyle(.red) }
                    if let feedback { Label(feedback, systemImage: "checkmark.circle").foregroundStyle(.green) }
                    if !FlowTree.childBlocks(of: favorite.node).isEmpty {
                        FlowGraphView(flow: FlowDefinition(id: "preview", name: favorite.name, nodes: [favorite.node])) {
                            selectedNodeID = $0.id
                        }
                        .frame(minHeight: 180)
                    }
                    NodeDetailsView(node: selectedNode)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $editing) { node in
            NodeEditorView(node: node, allowsFavorite: false, saving: saving, saveError: errorText, onSave: { updated in
                guard !saving else { return }
                saving = true
                errorText = nil
                Task {
                    defer { saving = false }
                    var copy = favorite
                    var roots = [copy.node]
                    _ = FlowTree.replace(in: &roots, id: updated.id, with: updated)
                    copy.node = roots[0]
                    do {
                        let saved = try await TBAPIClient.saveFavorite(copy)
                        editing = nil
                        errorText = nil
                        onUpdated(saved)
                    } catch { errorText = nodeLibraryError(error) }
                }
            }, onDismiss: { editing = nil })
        }
        .sheet(isPresented: $adding) {
            AddFavoriteToFlowSheet(favorite: favorite) { name in
                feedback = L10n.t("Added to {name}", ["name": name])
            }
        }
    }
}

/// Shows documentation beside the actual reusable configuration, without executing it.
struct NodeDetailsView: View {
    let node: FlowNode

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(node.name ?? node.id).font(.headline)
                Text(node.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            documentation(L10n.t("Input description"), NodeDocumentation.input(for: node), icon: "arrow.right.circle")
            documentation(L10n.t("Output description"), NodeDocumentation.output(for: node), icon: "arrow.left.circle")
            let references = NodeReuse.externalReferences(in: node)
            if !references.isEmpty {
                documentation(L10n.t("Upstream nodes to connect"), references.joined(separator: ", "), icon: "link")
            }
            if let code = node.code {
                source(L10n.t("Script content"), code)
            } else if node.type == .action {
                source(L10n.t("Action configuration"), "\(node.action ?? "")\n\(Presentation.prettyJSON(node.params ?? .object([:])))")
            } else if let condition = node.condition {
                source(L10n.t("Condition"), condition)
            } else if let over = node.over {
                source(L10n.t("Loop source"), over)
            }
            DisclosureGroup(L10n.t("Full configuration")) {
                if let data = try? TBJSON.prettyEncoder.encode(node) {
                    Text(String(decoding: data, as: UTF8.self))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }
        }
    }

    private func documentation(_ title: String, _ text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func source(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct CollectNodeSheet: View {
    var sourceFlow: FlowDefinition? = nil
    let onSaved: (FavoriteNode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var flows: [FlowDefinition] = []
    @State private var flowID = ""
    @State private var nodeID = ""
    @State private var name = ""
    @State private var errorText: String?
    @State private var saving = false
    @State private var loading = true

    private var flow: FlowDefinition? { flows.first { $0.id == flowID } }
    private var nodes: [FlowNode] { NodePlacement.flatten(flow?.nodes ?? []) }
    private var node: FlowNode? { nodes.first { $0.id == nodeID } }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("Favorite an existing node")).font(.headline).padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if loading { ProgressView() }
                    if flows.isEmpty && !loading { Text(L10n.t("Create a flow with configured nodes first.")) }
                    Picker(L10n.t("Flow"), selection: $flowID) {
                        ForEach(flows, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    Picker(L10n.t("Node"), selection: $nodeID) {
                        ForEach(nodes) { Text("\($0.name ?? $0.id) · \($0.id)").tag($0.id) }
                    }
                    TextField(L10n.t("Favorite name"), text: $name).textFieldStyle(.roundedBorder)
                    if let node { NodeDetailsView(node: node) }
                    if let errorText { Text(errorText).foregroundStyle(.red) }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.t("Save favorite")) { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(node == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }.padding(12)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 640)
        .task {
            defer { loading = false }
            do {
                if let sourceFlow { flows = [sourceFlow] }
                else { flows = try await TBAPIClient.flows().map(\.flow) }
                flowID = flows.first?.id ?? ""
                selectFirstNode()
            } catch { errorText = nodeLibraryError(error) }
        }
        .onChange(of: flowID) { _, _ in selectFirstNode() }
        .onChange(of: nodeID) { _, _ in name = node?.name ?? node?.id ?? "" }
    }

    private func selectFirstNode() {
        nodeID = nodes.first?.id ?? ""
        name = node?.name ?? node?.id ?? ""
    }

    private func save() async {
        guard let node else { return }
        saving = true
        defer { saving = false }
        do {
            let saved = try await TBAPIClient.saveFavorite(FavoriteNode(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines), node: node, sourceFlowName: flow?.name))
            onSaved(saved)
            dismiss()
        } catch { errorText = nodeLibraryError(error) }
    }
}

/// Used by the flow editor: insertion remains a draft until Save changes.
struct FavoritePickerSheet: View {
    let nodes: [FlowNode]
    let onInsert: (FlowNode, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var favorites: [FavoriteNode] = []
    @State private var selection: String?
    @State private var destination = "end"
    @State private var errorText: String?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("Add from favorites")).font(.headline).padding(14)
            Divider()
            HStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(favorites) { Text($0.name).tag($0.id) }
                }.frame(width: 200)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if loading { ProgressView() }
                        if let item = favorites.first(where: { $0.id == selection }) {
                            NodeDetailsView(node: item.node)
                            Text(L10n.t("Conflicting IDs and direct references are adjusted. Review upstream dependencies, dynamic references and aliases before running."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else if !loading {
                            Text(L10n.t("No favorites yet. Save a configured node from its editor or the Favorite Nodes page."))
                        }
                        if let errorText { Text(errorText).foregroundStyle(.red) }
                    }.padding(20)
                }.frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Picker(L10n.t("Insert at"), selection: $destination) {
                    ForEach(NodePlacement.destinations(in: nodes)) { Text($0.label).tag($0.id) }
                }.frame(maxWidth: 350)
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.t("Add node")) {
                    guard let item = favorites.first(where: { $0.id == selection }) else { return }
                    onInsert(NodeReuse.copy(item.node, avoiding: nodes), destination)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(selection == nil)
            }.padding(12)
        }
        .frame(width: 760, height: 620)
        .task {
            defer { loading = false }
            do {
                favorites = try await TBAPIClient.favorites()
                selection = favorites.first?.id
            } catch { errorText = nodeLibraryError(error) }
        }
    }
}

private struct AddFavoriteToFlowSheet: View {
    let favorite: FavoriteNode
    let onAdded: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var flows: [FlowDefinition] = []
    @State private var flowID = ""
    @State private var destination = "end"
    @State private var saving = false
    @State private var errorText: String?
    private var flow: FlowDefinition? { flows.first { $0.id == flowID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("Add to flow")).font(.headline)
            Text(favorite.name).foregroundStyle(.secondary)
            Picker(L10n.t("Flow"), selection: $flowID) {
                ForEach(flows, id: \.id) { Text($0.name).tag($0.id) }
            }
            Picker(L10n.t("Insert at"), selection: $destination) {
                ForEach(NodePlacement.destinations(in: flow?.nodes ?? [])) { Text($0.label).tag($0.id) }
            }
            Text(L10n.t("Adds an independent copy. Review its upstream references before running."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L10n.t("Conflicting IDs and direct references are adjusted. Review upstream dependencies, dynamic references and aliases before running."))
                .font(.caption).foregroundStyle(.secondary)
            if flows.isEmpty { Text(L10n.t("Create a flow first, or choose a favorite when creating a new flow.")) }
            if let errorText { Text(errorText).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.t("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.t("Add node")) { Task { await add() } }
                    .keyboardShortcut(.defaultAction).disabled(flow == nil || saving)
            }
        }
        .padding(20).frame(width: 500)
        .task {
            do { flows = try await TBAPIClient.flows().map(\.flow); flowID = flows.first?.id ?? "" }
            catch { errorText = nodeLibraryError(error) }
        }
        .onChange(of: flowID) { _, _ in destination = "end" }
    }

    private func add() async {
        saving = true
        defer { saving = false }
        do {
            guard var current = try await TBAPIClient.flows().first(where: { $0.id == flowID })?.flow else {
                errorText = L10n.t("flow not found"); return
            }
            let copy = NodeReuse.copy(favorite.node, avoiding: current.nodes)
            guard NodePlacement.insert(copy, at: destination, into: &current.nodes) else {
                errorText = L10n.t("The insertion point changed. Reopen this dialog and try again."); return
            }
            _ = try await TBAPIClient.saveFlow(current)
            onAdded(current.name)
            dismiss()
        } catch { errorText = nodeLibraryError(error) }
    }
}

enum NodePlacement {
    struct Destination: Identifiable { let id: String; let label: String }

    static func flatten(_ nodes: [FlowNode]) -> [FlowNode] {
        nodes.flatMap { [$0] + FlowTree.childBlocks(of: $0).flatMap { flatten($0) } }
    }

    static func destinations(in nodes: [FlowNode]) -> [Destination] {
        var result = [Destination(id: "end", label: L10n.t("End of flow"))]
        for node in flatten(nodes) {
            let name = node.name ?? node.id
            result.append(Destination(id: "after:\(node.id)", label: L10n.t("After {name}", ["name": name])))
            if node.type == .ifNode {
                result.append(Destination(id: "then:\(node.id)", label: "\(name) · then"))
                result.append(Destination(id: "else:\(node.id)", label: "\(name) · else"))
            } else if node.type == .loop {
                result.append(Destination(id: "body:\(node.id)", label: "\(name) · body"))
            }
        }
        return result
    }

    @discardableResult
    static func insert(_ node: FlowNode, at destination: String, into nodes: inout [FlowNode]) -> Bool {
        if destination == "end" { nodes.append(node); return true }
        let parts = destination.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        for index in nodes.indices {
            if nodes[index].id == parts[1] {
                switch parts[0] {
                case "after": nodes.insert(node, at: index + 1)
                case "then" where nodes[index].type == .ifNode: nodes[index].thenNodes = (nodes[index].thenNodes ?? []) + [node]
                case "else" where nodes[index].type == .ifNode: nodes[index].elseNodes = (nodes[index].elseNodes ?? []) + [node]
                case "body" where nodes[index].type == .loop: nodes[index].body = (nodes[index].body ?? []) + [node]
                default: return false
                }
                return true
            }
            if var children = nodes[index].thenNodes, insert(node, at: destination, into: &children) {
                nodes[index].thenNodes = children; return true
            }
            if var children = nodes[index].elseNodes, insert(node, at: destination, into: &children) {
                nodes[index].elseNodes = children; return true
            }
            if var children = nodes[index].body, insert(node, at: destination, into: &children) {
                nodes[index].body = children; return true
            }
        }
        return false
    }
}

private func nodeLibraryError(_ error: Error) -> String {
    if let error = error as? APIClientError {
        return ([error.rendered] + error.issues.map { "\($0.path): \($0.localizedMessage)" }).joined(separator: "\n")
    }
    return error.localizedDescription
}
