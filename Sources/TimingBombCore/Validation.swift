import Foundation
import TimingBombL10n

// MARK: - Issues

public struct ValidationIssue: Codable, Sendable, Equatable {
    public enum Level: String, Codable, Sendable {
        case error, warning
    }

    public var level: Level
    public var path: String
    /// Rendered in the validating process's locale.
    public var message: String
    /// English template with `{name}` placeholders; travels over the wire so
    /// clients can re-render in their own locale. nil for legacy payloads.
    public var template: String?
    public var params: [String: String]?

    public init(level: Level, path: String, message: String) {
        self.level = level
        self.path = path
        // Static English messages double as templates; dynamic strings miss
        // the table and render as-is.
        self.message = L10n.t(message)
        self.template = message
        self.params = nil
    }

    public init(level: Level, path: String, template: String, params: [String: String]) {
        self.level = level
        self.path = path
        self.message = L10n.t(template, params)
        self.template = template
        self.params = params
    }

    /// Re-renders the issue in the current process's locale (clients use this
    /// instead of the daemon-rendered `message` when `template` is present).
    public var localizedMessage: String {
        guard let template, !template.isEmpty else { return message }
        return L10n.t(template, params ?? [:])
    }
}

// MARK: - JS static checks

/// String-level checks applied to every code/condition/skipIf source before execution.
/// The sandbox enforces the real boundary at runtime; these catch mistakes early
/// and keep AI-generated sources on the unified format.
public enum CodeStaticChecker {
    public enum SourceKind: String, Sendable {
        case code, condition
    }

    static let forbiddenPatterns: [(pattern: String, message: String)] = [
        (#"\bimport\s"#, "import is not allowed; use ctx.tools only"),
        (#"\brequire\s*\("#, "require() is not allowed; use ctx.tools only"),
        (#"\bprocess\."#, "process.* globals do not exist in the sandbox"),
        (#"\b__tb"#, "internal runner globals are reserved"),
        (#"\bJava\s|\bObjC\b"#, "Java/ObjC bridges are disabled"),
    ]

    public static func issues(for source: String, kind: SourceKind, path: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            issues.append(.init(level: .error, path: path, message: "script is empty"))
            return issues
        }
        for rule in forbiddenPatterns {
            if source.range(of: rule.pattern, options: .regularExpression) != nil {
                issues.append(.init(level: .error, path: path, message: rule.message))
            }
        }
        if kind == .code {
            let declaresRun =
                source.range(of: #"(async\s+)?function\s+run\s*\("#, options: .regularExpression) != nil
                || source.range(of: #"(const|let|var)\s+run\s*=\s*(async\s*)?\("#, options: .regularExpression) != nil
            if !declaresRun {
                issues.append(
                    .init(
                        level: .error, path: path,
                        message: "code node must define `async function run(ctx)`"))
            }
            // Advisory checks (warning level): common pitfalls
            if source.range(of: #"(?<!tools\.)\bfetch\s*\("#, options: .regularExpression) != nil {
                issues.append(
                    .init(
                        level: .warning, path: path,
                        message: "bare fetch() does not exist in the sandbox; use ctx.tools.http.fetch"))
            }
            if source.range(of: #"while\s*\(\s*(true|1)\s*\)"#, options: .regularExpression) != nil,
                !source.contains("await")
            {
                issues.append(
                    .init(
                        level: .warning, path: path,
                        message: "`while(true)` without any await cannot be preempted; add an await (e.g. ctx.tools.sleep) or it will hang until timeout"))
            }
        }
        return issues
    }

    /// Throws on the first error-level issue.
    public static func requireValid(_ source: String, kind: SourceKind) throws {
        let issues = Self.issues(for: source, kind: kind, path: "script")
        if let first = issues.first(where: { $0.level == .error }) {
            throw TBError.validation(first.message)
        }
    }
}

// MARK: - Cron syntax (5-field)

public enum CronSyntax {
    public static let aliases: [String: String] = [
        "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
        "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *",
        "@hourly": "0 * * * *",
    ]
    static let fieldRanges: [(Int, Int)] = [(0, 59), (0, 23), (1, 31), (1, 12), (0, 6)]
    public static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    /// Expands aliases like @daily/@hourly; non-alias expressions pass through unchanged.
    public static func alias(for expression: String) -> String? {
        aliases[expression.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Localizable issue text: English template + interpolation params.
    public struct IssueText: Equatable, Sendable {
        public let template: String
        public let params: [String: String]

        public init(_ template: String, _ params: [String: String] = [:]) {
            self.template = template
            self.params = params
        }

        public var rendered: String { L10n.t(template, params) }
    }

    /// Returns issue text (template + params) for invalid expressions, nil when valid.
    public static func validate(_ expression: String) -> IssueText? {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        guard !expr.isEmpty else { return IssueText("cron expression is empty") }
        let expanded = alias(for: expr) ?? expr
        let fields = expanded.split(separator: " ").map(String.init)
        guard fields.count == 5 else {
            return IssueText(
                "cron expression must have 5 fields (minute hour day-of-month month day-of-week)")
        }
        for (index, field) in fields.enumerated() {
            if let reason = validateField(field, range: fieldRanges[index]) {
                return IssueText(
                    "cron field {index} '{field}': {reason}",
                    [
                        "index": String(index + 1),
                        "field": field,
                        "reason": reason.rendered,
                    ])
            }
        }
        return nil
    }

    private static func validateField(_ field: String, range: (Int, Int)) -> IssueText? {
        for part in field.split(separator: ",") {
            let piece = String(part)
            var body = piece
            if piece == "*" {
                continue
            }
            if piece.hasPrefix("*/") {
                body = String(piece.dropFirst(2))
                guard let step = Int(body), step > 0 else {
                    return IssueText("invalid step in '{field}'", ["field": piece])
                }
                continue
            }
            if let slash = piece.firstIndex(of: "/") {
                body = String(piece[..<slash])
                guard let step = Int(piece[piece.index(after: slash)...]), step > 0 else {
                    return IssueText("invalid step in '{field}'", ["field": piece])
                }
            }
            var low = body
            var high: String? = nil
            if let dash = body.firstIndex(of: "-") {
                low = String(body[..<dash])
                high = String(body[body.index(after: dash)...])
            }
            guard let lo = number(low, range: range), lo >= range.0, lo <= range.1 else {
                return IssueText(
                    "'{value}' out of range {low}-{high}",
                    ["value": low, "low": String(range.0), "high": String(range.1)])
            }
            if let high {
                guard let hi = number(high, range: range), hi >= range.0, hi <= range.1 else {
                    return IssueText(
                        "'{value}' out of range {low}-{high}",
                        ["value": high, "low": String(range.0), "high": String(range.1)])
                }
                if hi < lo {
                    return IssueText(
                        "range end {high} < start {low}",
                        ["high": String(hi), "low": String(lo)])
                }
            }
        }
        return nil
    }

    private static func number(_ token: String, range: (Int, Int)) -> Int? {
        if let n = Int(token) { return n }
        if range == fieldRanges[4], let idx = dayNames.firstIndex(of: token.lowercased()) {
            return idx
        }
        return nil
    }
}

// MARK: - Flow validator

public enum FlowValidator {
    public static let idPattern = #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#

    public static func validate(
        _ flow: FlowDefinition, knownActions: [String]
    ) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if flow.id.isEmpty || flow.id.range(of: idPattern, options: .regularExpression) == nil {
            issues.append(
                .init(
                    level: .error, path: "id",
                    template: "flow id must match {pattern} (got '{actual}')",
                    params: ["pattern": idPattern, "actual": flow.id]))
        }
        if flow.name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.init(level: .error, path: "name", message: "flow name is required"))
        }
        if let trigger = flow.trigger {
            if let cron = trigger.cron {
                if let issue = CronSyntax.validate(cron) {
                    issues.append(
                        .init(
                            level: .error, path: "trigger.cron",
                            template: issue.template, params: issue.params))
                }
            } else if trigger.type == .schedule {
                issues.append(
                    .init(
                        level: .error, path: "trigger.cron",
                        message: "schedule trigger requires a cron expression"))
            }
            if let timezone = trigger.timezone,
                trigger.timezone != "local", TimeZone(identifier: timezone) == nil
            {
                issues.append(
                    .init(
                        level: .error, path: "trigger.timezone",
                        template: "unknown timezone '{timezone}'", params: ["timezone": timezone]))
            }
            if let misfire = trigger.misfire, !["skip", "fireOnce"].contains(misfire) {
                issues.append(
                    .init(
                        level: .error, path: "trigger.misfire",
                        template: "misfire must be 'skip' or 'fireOnce' (got '{actual}')",
                        params: ["actual": misfire]))
            }
            if trigger.type == .fileWatch {
                if let path = trigger.path, !path.isEmpty {
                    let expanded = (path as NSString).expandingTildeInPath
                    var isDirectory: ObjCBool = false
                    if !FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory)
                        || !isDirectory.boolValue
                    {
                        issues.append(
                            .init(
                                level: .warning, path: "trigger.path",
                                template: "directory does not exist (yet): {path}",
                                params: ["path": expanded]))
                    }
                } else {
                    issues.append(
                        .init(
                            level: .error, path: "trigger.path",
                            message: "fileWatch trigger requires a directory 'path'"))
                }
            }
        }
        if flow.nodes.isEmpty {
            issues.append(.init(level: .warning, path: "nodes", message: "flow has no nodes"))
        }

        var seenIds = Set<String>()
        walk(flow.nodes, prefix: "nodes", into: &issues, seenIds: &seenIds, knownActions: knownActions, inLoop: false)
        return issues
    }

    private static func walk(
        _ nodes: [FlowNode], prefix: String, into issues: inout [ValidationIssue],
        seenIds: inout Set<String>, knownActions: [String], inLoop: Bool
    ) {
        for (index, node) in nodes.enumerated() {
            let path = "\(prefix)[\(index)]"
            if node.id.isEmpty || node.id.range(of: idPattern, options: .regularExpression) == nil {
                issues.append(
                    .init(
                        level: .error, path: "\(path).id",
                        template: "node id must match {pattern} (got '{actual}')",
                        params: ["pattern": idPattern, "actual": node.id]))
            } else if !seenIds.insert(node.id).inserted {
                issues.append(
                    .init(
                        level: .error, path: "\(path).id",
                        template: "duplicate node id '{nodeId}'", params: ["nodeId": node.id]))
            }
            if let name = node.name, name.isEmpty {
                issues.append(.init(level: .warning, path: "\(path).name", message: "empty node name"))
            }
            if let retries = node.retries, retries < 0 {
                issues.append(.init(level: .error, path: "\(path).retries", message: "retries must be >= 0"))
            }
            if let timeout = node.timeoutMs, timeout <= 0 {
                issues.append(.init(level: .error, path: "\(path).timeoutMs", message: "timeoutMs must be > 0"))
            }

            switch node.type {
            case .code:
                let language = SubprocessScriptRunner.normalize(node.language)
                if let raw = node.language, !raw.isEmpty,
                    !(["js", "javascript"] + SubprocessScriptRunner.supportedLanguages)
                        .contains(raw.lowercased())
                {
                    issues.append(
                        .init(
                            level: .error, path: "\(path).language",
                            template: "unsupported language '{language}' (js | python | shell)",
                            params: ["language": raw]))
                }
                if let code = node.code, !code.isEmpty {
                    // The JS static contract (run function / no import) only applies to js nodes
                    if language == "js" {
                        issues.append(
                            contentsOf: CodeStaticChecker.issues(
                                for: code, kind: .code, path: "\(path).code"))
                    }
                } else {
                    issues.append(.init(level: .error, path: "\(path).code", message: "code node requires 'code'"))
                }
            case .ifNode:
                if let condition = node.condition, !condition.isEmpty {
                    issues.append(
                        contentsOf: CodeStaticChecker.issues(
                            for: condition, kind: .condition, path: "\(path).condition"))
                } else {
                    issues.append(
                        .init(level: .error, path: "\(path).condition", message: "if node requires 'condition'"))
                }
                if (node.thenNodes ?? []).isEmpty && (node.elseNodes ?? []).isEmpty {
                    issues.append(
                        .init(
                            level: .warning, path: path,
                            message: "if node has empty 'then' and 'else' branches"))
                }
                walk(node.thenNodes ?? [], prefix: "\(path).then", into: &issues, seenIds: &seenIds, knownActions: knownActions, inLoop: inLoop)
                walk(node.elseNodes ?? [], prefix: "\(path).else", into: &issues, seenIds: &seenIds, knownActions: knownActions, inLoop: inLoop)
            case .loop:
                let mode = node.mode ?? .count
                if mode == .whileLoop {
                    if node.over != nil {
                        issues.append(
                            .init(
                                level: .warning, path: "\(path).over",
                                message: "'over' is ignored in while mode; use 'condition'"))
                    }
                    if let condition = node.condition, !condition.isEmpty {
                        issues.append(
                            contentsOf: CodeStaticChecker.issues(
                                for: condition, kind: .condition, path: "\(path).condition"))
                    } else {
                        issues.append(
                            .init(
                                level: .error, path: "\(path).condition",
                                message: "while loop requires 'condition'"))
                    }
                } else {
                    if let over = node.over, !over.isEmpty {
                        // Templates resolve at runtime; only literals are checkable here.
                        let isTemplate = over.contains("{{")
                        if !isTemplate, Int(over) == nil, !over.hasPrefix("[") {
                            issues.append(
                                .init(
                                    level: .error, path: "\(path).over",
                                    message: "'over' must be a number, a JSON array or a {{ template }}"))
                        }
                        if mode == .forEach, !isTemplate, Int(over) != nil {
                            issues.append(
                                .init(
                                    level: .error, path: "\(path).over",
                                    message: "forEach loop needs an array, not a count"))
                        }
                    } else {
                        issues.append(
                            .init(
                                level: .error, path: "\(path).over",
                                template: "{mode} loop requires 'over'",
                                params: ["mode": mode.rawValue]))
                    }
                    if let condition = node.condition, !condition.isEmpty, mode != .whileLoop {
                        issues.append(
                            contentsOf: CodeStaticChecker.issues(
                                for: condition, kind: .condition, path: "\(path).condition"))
                    }
                }
                if let c = node.concurrency, (c < 1 || c > 32) {
                    issues.append(
                        .init(level: .error, path: "\(path).concurrency", message: "concurrency must be 1...32"))
                }
                if mode == .whileLoop, let c = node.concurrency, c > 1 {
                    issues.append(
                        .init(
                            level: .error, path: "\(path).concurrency",
                            message: "while loops do not support concurrency > 1"))
                }
                if (node.body ?? []).isEmpty {
                    issues.append(
                        .init(level: .warning, path: "\(path).body", message: "loop body is empty"))
                }
                walk(node.body ?? [], prefix: "\(path).body", into: &issues, seenIds: &seenIds, knownActions: knownActions, inLoop: true)
            case .action:
                guard let action = node.action, !action.isEmpty else {
                    issues.append(
                        .init(level: .error, path: "\(path).action", message: "action node requires 'action'"))
                    break
                }
                if !knownActions.contains(action) {
                    issues.append(
                        .init(
                            level: .error, path: "\(path).action",
                            template: "unknown action '{action}'; available: {available}",
                            params: [
                                "action": action,
                                "available": knownActions.sorted().joined(separator: ", "),
                            ]))
                }
            case .approval:
                if inLoop {
                    issues.append(
                        .init(
                            level: .error, path: path,
                            message: "approval node cannot be placed inside a loop body (cannot resume mid-iteration)"))
                }
                if node.message == nil || node.message?.isEmpty == true {
                    issues.append(
                        .init(
                            level: .warning, path: "\(path).message",
                            message: "approval node works better with a 'message' explaining what to check"))
                }
            }

            if let skipIf = node.skipIf, !skipIf.isEmpty {
                issues.append(
                    contentsOf: CodeStaticChecker.issues(for: skipIf, kind: .condition, path: "\(path).skipIf"))
            }
        }
    }
}
