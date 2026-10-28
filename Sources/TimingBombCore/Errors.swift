import Foundation
import TimingBombL10n

/// Legacy freeform error. `errorDescription` stays English; locale rendering
/// happens at the edges (daemon wire responses, client displays) via `api`.
public enum TBError: Error, LocalizedError, Equatable, Sendable {
    case notFound(String)
    case validation(String)
    case scriptError(String)
    case nodeFailed(nodeId: String, message: String)
    case timeout(String)
    case cancelled
    case unsupportedAction(String)
    case invalidRequest(String)
    case unauthorized
    case internalError(String)

    public var errorDescription: String? {
        api.rendered(templateOnly: true)
    }

    /// Bridges to the structured wire form (code + English template + params).
    public var api: TBApiError {
        switch self {
        case .notFound(let what):
            TBApiError(status: 404, code: "notFound", template: "not found: {what}", params: ["what": what])
        case .validation(let message):
            TBApiError(status: 400, code: "validation", template: "validation error: {message}", params: ["message": message])
        case .scriptError(let message):
            TBApiError(status: 500, code: "scriptError", template: "script error: {message}", params: ["message": message])
        case .nodeFailed(let nodeId, let message):
            TBApiError(
                status: 500, code: "nodeFailed", template: "node '{nodeId}' failed: {message}",
                params: ["nodeId": nodeId, "message": message])
        case .timeout(let what):
            TBApiError(status: 500, code: "timeout", template: "timeout: {what}", params: ["what": what])
        case .cancelled:
            TBApiError(status: 500, code: "cancelled", template: "cancelled")
        case .unsupportedAction(let action):
            TBApiError(
                status: 400, code: "unsupportedAction", template: "unsupported action: {action}",
                params: ["action": action])
        case .invalidRequest(let message):
            TBApiError(
                status: 400, code: "invalidRequest", template: "invalid request: {message}",
                params: ["message": message])
        case .unauthorized:
            TBApiError(status: 401, code: "unauthorized", template: "unauthorized")
        case .internalError(let message):
            TBApiError(
                status: 500, code: "internalError", template: "internal error: {message}",
                params: ["message": message])
        }
    }
}

/// Structured error that travels over the network: a stable machine-readable
/// `code`, an English `template` with `{name}` placeholders, and interpolation
/// `params`. Each client renders it in its own locale via `L10n.t`.
/// `message` keeps a daemon-locale rendering for non-localized HTTP consumers.
public struct TBApiError: Error, LocalizedError, Sendable {
    public let status: Int
    public let code: String
    public let template: String
    public let params: [String: String]
    public let issues: [ValidationIssue]?

    public init(
        status: Int, code: String, template: String,
        params: [String: String] = [:], issues: [ValidationIssue]? = nil
    ) {
        self.status = status
        self.code = code
        self.template = template
        self.params = params
        self.issues = issues
    }

    /// Renders in the current process locale (English template with placeholders
    /// substituted when `templateOnly`). `errorDescription` goes through `L10n`,
    /// so a CLI/App process re-renders daemon errors in its own language.
    public func rendered(templateOnly: Bool = false) -> String {
        guard !templateOnly else {
            var text = template
            for (name, value) in params {
                text = text.replacingOccurrences(of: "{\(name)}", with: value)
            }
            return text
        }
        return L10n.t(template, params)
    }

    public var errorDescription: String? { rendered() }
}
