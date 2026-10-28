import SwiftUI
import TimingBombCore
import TimingBombL10n

/// Node editor sheet: common properties plus per-type fields (code nodes get a JS editor).
struct NodeEditorView: View {
    @State private var node: FlowNode
    private let onSave: (FlowNode) -> Void
    private let onDismiss: () -> Void

    @State private var paramsText: String = "{}"
    @State private var errorText: String?

    init(node: FlowNode, onSave: @escaping (FlowNode) -> Void, onDismiss: @escaping () -> Void) {
        _node = State(initialValue: node)
        self.onSave = onSave
        self.onDismiss = onDismiss
        if let params = node.params {
            paramsText = (try? TBJSON.prettyEncoder.encode(params)).map {
                String(decoding: $0, as: UTF8.self)
            } ?? "{}"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Form {
                Section(L10n.t("Basics")) {
                    LabeledContent(L10n.t("Node ID")) {
                        Text(node.id).font(.system(.caption, design: .monospaced))
                    }
                    LabeledContent(L10n.t("Type")) { Text(typeName) }
                    TextField(
                        L10n.t("Name (optional)"),
                        text: Binding(
                            get: { node.name ?? "" },
                            set: { node.name = $0.isEmpty ? nil : $0 }
                        ))
                    if node.type == .code {
                        Picker(
                            L10n.t("Language"),
                            selection: Binding(
                                get: { node.language ?? "js" },
                                set: { node.language = $0 == "js" ? nil : $0 }
                            )) {
                            Text(L10n.t("JavaScript (built-in sandbox)")).tag("js")
                            Text(L10n.t("Python (system interpreter)")).tag("python")
                            Text(L10n.t("Shell (zsh)")).tag("shell")
                        }
                        .pickerStyle(.menu)
                    }
                }

                typeSection

                    Section(L10n.t("Execution Policy")) {
                        LabeledContent(L10n.t("Timeout (ms)")) {
                            numberField($node.timeoutMs)
                        }
                        LabeledContent(L10n.t("Retries on failure")) {
                            numberField($node.retries, min: 0)
                        }
                        Picker(L10n.t("On failure"), selection: $node.onError) {
                            Text(L10n.t("Abort the flow")).tag(OnErrorPolicy?.some(.abort))
                            Text(L10n.t("Log and continue")).tag(OnErrorPolicy?.some(.continueOn))
                        }
                        .pickerStyle(.radioGroup)
                        TextField(
                            L10n.t("Skip condition (optional, JS expression)"),
                            text: Binding(
                                get: { node.skipIf ?? "" },
                                set: { node.skipIf = $0.isEmpty ? nil : $0 }
                            ),
                            axis: .vertical
                        )
                        .font(.system(.caption, design: .monospaced))
                    }
                }
                .formStyle(.grouped)
                .padding(.vertical, 4)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 540, idealHeight: 620)
    }

    private var header: some View {
        HStack {
            Text(L10n.t("Edit Node · {name}", ["name": node.name ?? node.id]))
                .font(.headline)
            Spacer()
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(L10n.t("Cancel"), action: onDismiss).keyboardShortcut(.cancelAction)
            Button(L10n.t("Save Node"), action: save).keyboardShortcut(.defaultAction)
        }
        .padding(10)
    }

    @ViewBuilder
    private var typeSection: some View {
        switch node.type {
        case .code:
            Section(codeSectionTitle) {
                codeEditor(
                    text: optionalText($node.code), minHeight: 260,
                    placeholder: codePlaceholder)
                if node.type == .code {
                    Text(codeHint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        case .ifNode:
            Section(L10n.t("Condition (JS expression, e.g. nodes.a.output.x > 0)")) {
                codeEditor(text: optionalText($node.condition), minHeight: 80, placeholder: "nodes.a.output.x > 0")
            }
            LabeledContent(L10n.t("Branches")) {
                Text(
                    L10n.t(
                        "then: {then} node(s) · else: {else} node(s)",
                        [
                            "then": String(node.thenNodes?.count ?? 0),
                            "else": String(node.elseNodes?.count ?? 0),
                        ]))
                    .foregroundStyle(.secondary)
            }
        case .loop:
            Section(L10n.t("Loop")) {
                Picker(
                    L10n.t("Mode"),
                    selection: Binding(
                        get: { node.mode ?? .count },
                        set: { node.mode = $0 }
                    )) {
                    Text(L10n.t("Fixed count (count)")).tag(LoopMode.count)
                    Text(L10n.t("Iterate array (forEach)")).tag(LoopMode.forEach)
                    Text(L10n.t("While condition (while)")).tag(LoopMode.whileLoop)
                }
                if node.mode == .whileLoop {
                    codeEditor(
                        text: optionalText($node.condition), minHeight: 60,
                        placeholder: L10n.t("condition for the loop to continue"))
                } else {
                    TextField(
                        L10n.t("over ({{ template }} / number / JSON array)"),
                        text: Binding(
                            get: { node.over ?? "" },
                            set: { node.over = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .font(.system(.caption, design: .monospaced))
                }
                LabeledContent(L10n.t("Concurrency (1-32)")) {
                    numberField($node.concurrency, min: 1)
                }
                LabeledContent(L10n.t("Max iterations")) {
                    numberField($node.maxIterations, min: 1)
                }
            }
        case .approval:
            Section(L10n.t("Approval")) {
                TextField(
                    L10n.t("Approval message (shown to the approver; say what to check)"),
                    text: Binding(
                        get: { node.message ?? "" },
                        set: { node.message = $0.isEmpty ? nil : $0 }
                    ),
                    axis: .vertical
                )
                Text(L10n.t("The run suspends here until someone approves or rejects it on the Approvals page; approval resumes from this node onward"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

        case .action:
            Section(L10n.t("Action")) {
                Picker(
                    L10n.t("Action type"),
                    selection: Binding(
                        get: { node.action ?? "delay" },
                        set: { node.action = $0 }
                    )) {
                    Text(L10n.t("delay · wait")).tag("delay")
                    Text(L10n.t("http · request")).tag("http")
                    Text(L10n.t("shell · command (needs allowlist)")).tag("shell")
                    Text(L10n.t("appleScript (needs allowlist)")).tag("appleScript")
                    Text(L10n.t("notify · system notification")).tag("notify")
                    Text(L10n.t("openApp · open app")).tag("openApp")
                    Text(L10n.t("clipboard · clipboard")).tag("clipboard")
                    Text(L10n.t("fileRead · read workspace file")).tag("fileRead")
                    Text(L10n.t("fileWrite · write workspace file")).tag("fileWrite")
                }
                .pickerStyle(.radioGroup)
                Text(actionHint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(L10n.t("Params (JSON, supports {{ templates }})"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                codeEditor(text: $paramsText, minHeight: 110, placeholder: "{ \"ms\": 500 }")
            }
        }
    }

    private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func codeEditor(text: Binding<String>, minHeight: CGFloat, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(size: 11.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(.quinary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: minHeight)
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 6)
                    .allowsHitTesting(false)
            }
        }
    }

    private func numberField(_ binding: Binding<Int?>, min minimum: Int = 1) -> some View {
        TextField(
            "-",
            text: Binding(
                get: { binding.wrappedValue.map(String.init) ?? "" },
                set: { binding.wrappedValue = Int($0).map { max($0, minimum) } }
            ))
        .textFieldStyle(.roundedBorder)
        .frame(width: 90)
    }

    private var codeSectionTitle: String {
        switch node.language ?? "js" {
        case "python": return L10n.t("Python code (context JSON on stdin, result JSON on stdout)")
        case "shell": return L10n.t("Shell script (zsh; context JSON on stdin, result JSON on stdout)")
        default: return L10n.t("JavaScript code (must define async function run(ctx))")
        }
    }

    private var codePlaceholder: String {
        switch node.language ?? "js" {
        case "python":
            return "import sys, json\nctx = json.load(sys.stdin)\n# ...\nprint(json.dumps({\"ok\": True}))"
        case "shell":
            return "CTX=$(cat)\n# ...\necho '{\"ok\": 1}'"
        default:
            return "async function run(ctx) {\n  return {};\n}"
        }
    }

    private var codeHint: String {
        switch node.language ?? "js" {
        case "python":
            return L10n.t("Uses the system python3 (override the path with TIMINGBOMB_PYTHON); stderr goes to node logs; a non-zero exit code fails the node")
        case "shell":
            return L10n.t("stdin carries the full context JSON (trigger/nodes/loop); stdout must be JSON, otherwise the output falls back to {raw}")
        default:
            return L10n.t("tools: log/sleep/fail/http.fetch/exec (allowlisted); the return value is stored as nodes.<id>.output; inside a loop, returning {$loop:\"break\"} stops it")
        }
    }

    private var typeName: String {
        switch node.type {
        case .code: return L10n.t("Code (code)")
        case .ifNode: return L10n.t("Condition (if)")
        case .loop: return L10n.t("Loop (loop)")
        case .action: return L10n.t("Built-in action (action)")
        case .approval: return L10n.t("Manual approval (approval)")
        }
    }

    private var actionHint: String {
        switch node.action ?? "delay" {
        case "delay": return "params: { \"ms\": 500 }"
        case "http": return "params: { method, url, headers, body, timeoutMs }"
        case "shell": return L10n.t("params: { command, timeoutMs } · the command must match an allowlist rule (Settings page or tb allow)")
        case "appleScript": return L10n.t("params: { script } · the script must match an allowlist rule")
        case "notify": return "params: { title, body }"
        case "openApp": return L10n.t("params: { name } (app name or bundleId)")
        case "clipboard": return "params: { op: \"read\" } or { op: \"write\", text }"
        case "fileRead": return L10n.t("params: { path } · relative to the flow workspace; cannot escape it")
        case "fileWrite": return L10n.t("params: { path, content } · relative to the flow workspace; cannot escape it")
        default: return ""
        }
    }

    private func save() {
        errorText = nil
        if node.type == .action {
            guard let data = paramsText.data(using: .utf8),
                let params = try? TBJSON.decodeData(JSONValue.self, from: data)
            else {
                errorText = L10n.t("action params are not valid JSON")
                return
            }
            node.params = params
        }
        var cleaned = node
        if cleaned.name?.isEmpty == true { cleaned.name = nil }
        if cleaned.skipIf?.isEmpty == true { cleaned.skipIf = nil }
        if cleaned.over?.isEmpty == true { cleaned.over = nil }
        if cleaned.condition?.isEmpty == true { cleaned.condition = nil }
        if cleaned.code?.isEmpty == true { cleaned.code = nil }
        onSave(cleaned)
    }
}
