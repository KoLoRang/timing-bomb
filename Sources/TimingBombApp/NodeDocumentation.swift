import Foundation
import TimingBombCore
import TimingBombL10n

/// User-authored notes take precedence over the built-in execution contract.
/// Custom scripts are never inspected to guess their input or output fields.
enum NodeDocumentation {
    static func input(for node: FlowNode) -> String {
        if let description = nonempty(node.inputDescription) { return description }
        switch node.type {
        case .code:
            switch SubprocessScriptRunner.normalize(node.language) {
            case "python", "shell":
                return L10n.t("Reads the full context JSON from stdin: trigger.payload, nodes.<id>.output and, inside a loop, loop.item/index. Describe the specific fields this script needs.")
            default:
                return L10n.t("run(ctx) receives trigger.payload, nodes.<id>.output and, inside a loop, loop.item/index. Describe the specific fields this script needs.")
            }
        case .ifNode:
            return L10n.t("condition reads the current context as a JavaScript expression, for example nodes.prepare.output.total > 0.")
        case .loop:
            switch node.mode ?? .count {
            case .count:
                return L10n.t("over supplies an iteration count. The body receives loop.index and loop.item, both starting at 0.")
            case .forEach:
                return L10n.t("over supplies an array, for example {{nodes.prepare.output.items}}. The body receives each value as loop.item and its position as loop.index.")
            case .whileLoop:
                return L10n.t("condition reads the context before each iteration. The body receives loop.index; loop.item is null.")
            }
        case .approval:
            return L10n.t("message can reference the current context with {{path}} templates. The run waits for an approval decision.")
        case .action:
            return actionInput(node.action ?? "delay")
        }
    }

    static func output(for node: FlowNode) -> String {
        if let description = nonempty(node.outputDescription) { return description }
        let result: String
        switch node.type {
        case .code:
            switch SubprocessScriptRunner.normalize(node.language) {
            case "python", "shell":
                result = L10n.t("stdout is parsed as JSON. Non-JSON output becomes {raw: text}; stderr is recorded as logs. Describe the fields the script emits.")
            default:
                result = L10n.t("The JSON value returned by run(ctx). No return value produces null. Describe the returned fields and their types.")
            }
        case .ifNode:
            result = L10n.t("{branch: \"then\"} or {branch: \"else\"}. Each executed child node also has its own output.")
        case .loop:
            result = L10n.t("{count: number, results: array}. results contains the output of the last top-level body node for each iteration; individual body outputs are overwritten by later iterations.")
        case .approval:
            return L10n.t("Approval status is recorded in the run timeline. This node does not write nodes.<id>.output; approval resumes the flow with its existing context.")
        case .action:
            result = actionOutput(node.action ?? "delay", params: node.params)
        }
        return result + "\n" + L10n.t("Stored at ctx.nodes.{id}.output.", ["id": node.id])
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func actionInput(_ action: String) -> String {
        switch action {
        case "delay":
            return L10n.t("ms: wait duration in milliseconds (0–3600000).")
        case "http":
            return L10n.t("url: HTTP(S) URL. Optional method, headers, body and timeoutMs. String fields support {{path}} templates.")
        case "shell":
            return L10n.t("command: shell command allowed by the allowlist. Optional timeoutMs. Supports {{path}} templates.")
        case "appleScript":
            return L10n.t("script: AppleScript allowed by the allowlist. Supports {{path}} templates.")
        case "notify":
            return L10n.t("title: notification title; body: notification text. Both support {{path}} templates.")
        case "openApp":
            return L10n.t("name: application name or bundle identifier. Supports {{path}} templates.")
        case "clipboard":
            return L10n.t("op: read or write. write also requires text; text supports {{path}} templates.")
        case "fileRead":
            return L10n.t("path: file path relative to this flow's workspace. Absolute paths and .. are not allowed.")
        case "fileWrite":
            return L10n.t("path: file path relative to this flow's workspace; content: text to write. Both support {{path}} templates.")
        default:
            return L10n.t("Action parameters are read from params. String fields support {{path}} templates.")
        }
    }

    private static func actionOutput(_ action: String, params: JSONValue?) -> String {
        switch action {
        case "delay":
            return L10n.t("{delayedMs: number}: actual requested wait duration after applying limits.")
        case "http":
            return L10n.t("{status: number, ok: boolean, headers: object, body: string}. Parse body as JSON in a code node when needed.")
        case "shell", "appleScript", "openApp":
            return L10n.t("{exitCode: number, stdout: string, stderr: string}: the process result.")
        case "notify":
            return L10n.t("{notified: true}: the notification was submitted.")
        case "clipboard":
            if params?["op"]?.stringValue == "write" {
                return L10n.t("{written: true}: the text was copied to the clipboard.")
            }
            return L10n.t("read returns {text: string}; write returns {written: true}.")
        case "fileRead":
            return L10n.t("{path: string, content: string}: the relative file path and its text content.")
        case "fileWrite":
            return L10n.t("{path: string, bytes: number}: the absolute saved path and the UTF-8 byte count.")
        default:
            return L10n.t("The JSON value returned by the action.")
        }
    }
}
