import Foundation

/// A JSON value tree used for flow context, node input/output and API payloads.
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        default: return nil
        }
    }

    public var intValue: Int64? {
        switch self {
        case .int(let i): return i
        case .double(let d): return d == d.rounded() ? Int64(d) : nil
        case .bool(let b): return b ? 1 : 0
        case .string(let s): return Int64(s)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        default: return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Human readable single-line form (used by logs and CLI).
    public var displayString: String {
        switch self {
        case .string(let s): return s
        case .null: return "null"
        default:
            return (try? TBJSON.encode(self)) ?? String(describing: self)
        }
    }

    /// Dot-path lookup, e.g. `nodes.fetch.output.items.0`.
    public subscript(path: String) -> JSONValue? {
        var current: JSONValue? = self
        for rawKey in path.split(separator: ".").map(String.init) {
            guard let node = current else { return nil }
            switch node {
            case .object(let o):
                current = o[rawKey]
            case .array(let a):
                guard let idx = Int(rawKey), idx >= 0, idx < a.count else { return nil }
                current = a[idx]
            default:
                return nil
            }
        }
        return current
    }

    /// Sets a value at a dot path, creating intermediate containers as needed.
    public mutating func set(value: JSONValue, atPath path: String) {
        let keys = path.split(separator: ".").map(String.init)
        guard !keys.isEmpty else { return }
        self = Self.setting(self, keys, value)
    }

    /// Removes the value at a dot path (used to scrub loop scope from outer context).
    public mutating func remove(atPath path: String) {
        let keys = path.split(separator: ".").map(String.init)
        guard !keys.isEmpty else { return }
        self = Self.removing(self, keys)
    }

    private static func setting(_ node: JSONValue, _ keys: [String], _ value: JSONValue) -> JSONValue {
        guard let key = keys.first else { return value }
        let rest = Array(keys.dropFirst())
        if let idx = Int(key) {
            var arr = node.arrayValue ?? []
            while arr.count <= idx { arr.append(.null) }
            arr[idx] = setting(arr[idx], rest, value)
            return .array(arr)
        }
        var obj = node.objectValue ?? [:]
        obj[key] = setting(obj[key] ?? .null, rest, value)
        return .object(obj)
    }

    private static func removing(_ node: JSONValue, _ keys: [String]) -> JSONValue {
        guard let key = keys.first else { return node }
        let rest = Array(keys.dropFirst())
        if rest.isEmpty {
            if var obj = node.objectValue {
                obj.removeValue(forKey: key)
                return .object(obj)
            }
            if var arr = node.arrayValue, let idx = Int(key), idx >= 0, idx < arr.count {
                arr.remove(at: idx)
                return .array(arr)
            }
            return node
        }
        guard var obj = node.objectValue, let child = obj[key] else { return node }
        obj[key] = removing(child, rest)
        return .object(obj)
    }
}

// MARK: - Template rendering

extension JSONValue {
    static let templateRegex = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)

    /// Renders `{{ path }}` templates against this value.
    ///
    /// A string that is exactly one template resolves to the raw typed value
    /// (object/array/number/...); otherwise matched segments are interpolated
    /// into the surrounding string (strings inserted as-is, other values as JSON text).
    public static func render(template: String, in context: JSONValue) -> JSONValue {
        guard template.contains("{{") else { return .string(template) }
        let ns = template as NSString
        let matches = templateRegex.matches(in: template, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return .string(template) }

        if matches.count == 1, matches[0].range.location == 0, matches[0].range.length == ns.length {
            let path = ns.substring(with: matches[0].range(at: 1)).trimmingCharacters(in: .whitespaces)
            return context[path] ?? .null
        }

        var result = ""
        var cursor = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let path = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let resolved = context[path] ?? .null
            if case .string(let s) = resolved {
                result += s
            } else {
                result += resolved.displayString
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return .string(result)
    }

    /// Deeply renders every string in the tree (used for action params).
    public func renderingTemplates(in context: JSONValue) -> JSONValue {
        switch self {
        case .string(let s):
            return .string(JSONValue.render(template: s, in: context).displayString)
        case .array(let a):
            return .array(a.map { $0.renderingTemplates(in: context) })
        case .object(let o):
            var rendered: [String: JSONValue] = [:]
            for (k, v) in o { rendered[k] = v.renderingTemplates(in: context) }
            return .object(rendered)
        default:
            return self
        }
    }

    /// Replaces the value with a truncation marker when its JSON form exceeds the limit.
    public func clipping(jsonBudget: Int) -> JSONValue {
        guard let text = try? TBJSON.encode(self), text.utf8.count > jsonBudget else { return self }
        return .object([
            "__truncated": .bool(true),
            "preview": .string(String(text.prefix(2000))),
        ])
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}

// MARK: - Shared coder

public enum TBJSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func encode<T: Encodable>(_ value: T) throws -> String {
        guard let text = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw TBError.internalError("JSON encoding produced invalid UTF-8")
        }
        return text
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = text.data(using: .utf8) else {
            throw TBError.internalError("invalid UTF-8 in JSON payload")
        }
        return try decoder.decode(type, from: data)
    }

    public static func encodeData<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decodeData<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}
