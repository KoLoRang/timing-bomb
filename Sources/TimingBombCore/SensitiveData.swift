import Foundation

/// Best-effort redaction at the history/API boundary. Execution contexts and
/// configured flows are never passed through this filter before execution.
public enum SensitiveData {
    public static let replacement = "[REDACTED]"

    public static func redact(_ value: JSONValue) -> JSONValue {
        Redactor(values: [value]).value(value)
    }

    public static func redact(_ text: String) -> String {
        Redactor(values: []).text(text)
    }

    public static func redacted(_ record: RunRecord) -> RunRecord {
        let values = [record.trigger.payload, record.context]
            + record.nodeRuns.flatMap { [$0.input, $0.output] }
        let redactor = Redactor(values: values.compactMap { $0 })
        var copy = record
        copy.flowName = redactor.text(copy.flowName)
        copy.trigger.payload = copy.trigger.payload.map(redactor.value)
        copy.context = copy.context.map(redactor.value)
        copy.error = copy.error.map(redactor.text)
        copy.nodeRuns = copy.nodeRuns.map { original in
            var node = original
            node.input = node.input.map(redactor.value)
            node.output = node.output.map(redactor.value)
            node.error = node.error.map(redactor.text)
            node.logs = node.logs.map(redactor.text)
            return node
        }
        return copy
    }

    private static func isSensitive(_ key: String) -> Bool {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        return ["authorization", "proxyauthorization", "cookie", "setcookie", "password",
                "passwd", "passphrase", "token", "apikey", "secret", "clientsecret",
                "privatekey", "credential", "credentials"].contains(normalized)
            || normalized.hasSuffix("token") || normalized.hasSuffix("password")
            || normalized.hasSuffix("apikey") || normalized.hasSuffix("secret")
    }

    private struct Redactor {
        let secrets: [String]

        init(values: [JSONValue]) {
            var found = Set<String>()
            func collectSecret(_ value: JSONValue) {
                switch value {
                case .string(let secret) where secret.count >= 4 && secret != replacement:
                    found.insert(secret)
                    if secret.lowercased().hasPrefix("bearer ") {
                        let token = String(secret.dropFirst(7))
                        if token.count >= 4 { found.insert(token) }
                    }
                case .array(let items): items.forEach(collectSecret)
                case .object(let fields): fields.values.forEach(collectSecret)
                default: break
                }
            }
            func walk(_ value: JSONValue) {
                switch value {
                case .object(let fields):
                    for (key, value) in fields {
                        if isSensitive(key) { collectSecret(value) } else { walk(value) }
                    }
                case .array(let items): items.forEach(walk)
                default: break
                }
            }
            values.forEach(walk)
            secrets = found.sorted { $0.count > $1.count }
        }

        func value(_ value: JSONValue) -> JSONValue {
            switch value {
            case .object(let fields):
                return .object(fields.reduce(into: [String: JSONValue]()) { result, entry in
                    result[entry.key] = isSensitive(entry.key) && entry.value != .null
                        ? .string(replacement) : self.value(entry.value)
                })
            case .array(let items): return .array(items.map(self.value))
            case .string(let string): return .string(text(string))
            default: return value
            }
        }

        func text(_ original: String) -> String {
            var result = original
            for secret in secrets {
                result = result.replacingOccurrences(of: secret, with: replacement)
            }
            // URLs may carry credentials in userinfo or query parameters.
            result = replacing(#"https?://[^\s<>\"']+"#, in: result) { url in
                guard var components = URLComponents(string: url) else { return url }
                if components.user != nil || components.password != nil {
                    components.user = "REDACTED"
                    components.password = nil
                }
                components.queryItems = components.queryItems?.map { item in
                    isSensitive(item.name) ? URLQueryItem(name: item.name, value: "REDACTED") : item
                }
                return components.string ?? url
            }
            // Common credentials in free-form errors and script logs. This is
            // deliberately not a claim to detect arbitrary application secrets.
            for pattern in [
                #"(?im)\b(?:authorization|proxy-authorization|cookie|set-cookie)\s*:\s*[^\r\n]+"#,
                #"(?i)\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+"#,
                #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
                #"\b(?:sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{12,})\b"#,
                #"(?i)[\"']?(?:authorization|proxy-authorization|cookie|set-cookie|password|passwd|passphrase|(?:access[_-]?|refresh[_-]?|id[_-]?)?token|api[_-]?key|client[_-]?secret|secret)[\"']?\s*[:=]\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;}&]+)"#,
                #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            ] {
                result = replacing(pattern, in: result) { _ in replacement }
            }
            return result
        }

        private func replacing(_ pattern: String, in text: String, transform: (String) -> String) -> String {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
            var result = text
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: transform(String(result[range])))
            }
            return result
        }
    }
}
