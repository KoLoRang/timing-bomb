import Foundation

/// Copies a saved node tree while keeping explicit context references connected.
/// Computed property names and aliases cannot be resolved statically and remain unchanged.
public enum NodeReuse {
    public static func copy(_ node: FlowNode, avoiding nodes: [FlowNode]) -> FlowNode {
        let existingIDs = Set(flatten(nodes).map(\.id))
        let sourceNodes = flatten([node])
        // A fresh internal ID must not accidentally capture an upstream dependency
        // which has not been added to the destination flow yet.
        var reservedIDs = existingIDs.union(sourceNodes.map(\.id)).union(externalReferences(in: node))
        var replacements: [String: String] = [:]

        for source in sourceNodes where existingIDs.contains(source.id) {
            guard replacements[source.id] == nil else { continue }
            var suffix = 2
            var candidate = "\(source.id)_\(suffix)"
            while reservedIDs.contains(candidate) {
                suffix += 1
                candidate = "\(source.id)_\(suffix)"
            }
            replacements[source.id] = candidate
            reservedIDs.insert(candidate)
        }
        return rewriting(node, replacements: replacements)
    }

    /// Literal node references outside the copied tree; callers can show these as dependencies.
    public static func externalReferences(in node: FlowNode) -> [String] {
        let nodes = flatten([node])
        let internalIDs = Set(nodes.map(\.id))
        var referencedIDs = Set<String>()
        for node in nodes {
            for (text, kind) in texts(in: node) {
                referencedIDs.formUnion(references(in: text, kind: kind).map(\.id))
            }
        }
        return referencedIDs.subtracting(internalIDs).sorted()
    }

    private static func flatten(_ nodes: [FlowNode]) -> [FlowNode] {
        nodes.flatMap { node in
            [node] + flatten(node.thenNodes ?? []) + flatten(node.elseNodes ?? [])
                + flatten(node.body ?? [])
        }
    }

    private static func rewriting(_ node: FlowNode, replacements: [String: String]) -> FlowNode {
        var copy = node
        copy.id = replacements[node.id] ?? node.id
        copy.inputDescription = node.inputDescription.map { rewrite($0, kind: .documentation, replacements: replacements) }
        copy.outputDescription = node.outputDescription.map { rewrite($0, kind: .documentation, replacements: replacements) }
        copy.code = node.code.map { rewrite($0, kind: .code(node.language ?? "js"), replacements: replacements) }
        copy.condition = node.condition.map { rewrite($0, kind: .condition, replacements: replacements) }
        copy.skipIf = node.skipIf.map { rewrite($0, kind: .condition, replacements: replacements) }
        copy.over = node.over.map { rewrite($0, kind: .templates, replacements: replacements) }
        copy.message = node.message.map { rewrite($0, kind: .templates, replacements: replacements) }
        copy.params = node.params.map { rewrite($0, replacements: replacements) }
        copy.thenNodes = node.thenNodes?.map { rewriting($0, replacements: replacements) }
        copy.elseNodes = node.elseNodes?.map { rewriting($0, replacements: replacements) }
        copy.body = node.body?.map { rewriting($0, replacements: replacements) }
        return copy
    }

    private static func rewrite(_ value: JSONValue, replacements: [String: String]) -> JSONValue {
        switch value {
        case .string(let text): return .string(rewrite(text, kind: .templates, replacements: replacements))
        case .array(let values): return .array(values.map { rewrite($0, replacements: replacements) })
        case .object(let values):
            return .object(values.mapValues { rewrite($0, replacements: replacements) })
        default: return value
        }
    }

    private enum TextKind {
        case code(String), condition, templates, documentation
    }

    private static func texts(in node: FlowNode) -> [(String, TextKind)] {
        var result: [(String, TextKind)] = []
        if let text = node.code { result.append((text, .code(node.language ?? "js"))) }
        for text in [node.condition, node.skipIf].compactMap({ $0 }) { result.append((text, .condition)) }
        for text in [node.over, node.message].compactMap({ $0 }) { result.append((text, .templates)) }
        for text in [node.inputDescription, node.outputDescription].compactMap({ $0 }) { result.append((text, .documentation)) }
        result += (node.params.map(strings) ?? []).map { ($0, .templates) }
        return result
    }

    private static func strings(in value: JSONValue) -> [String] {
        switch value {
        case .string(let text): return [text]
        case .array(let values): return values.flatMap(strings)
        case .object(let values): return values.values.flatMap(strings)
        default: return []
        }
    }

    private struct Reference {
        let id: String
        let range: NSRange
    }

    private static let templateRegex = try! NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#)
    private static let pathPatterns = [
        #"^nodes\.([A-Za-z0-9._-]+?)(?=\.output(?:\.|$))"#,
        #"^nodes\.([A-Za-z0-9_-]+)(?=\.|$)"#,
    ].map { try! NSRegularExpression(pattern: $0) }
    private static let contextPrefixes = [#"ctx\s*\.\s*nodes"#, #"ctx\s*\[\s*(?:"nodes"|'nodes')\s*\]"#]
    private static let directPatterns = makeDirectPatterns(prefixes: contextPrefixes)
    private static let barePatterns = makeDirectPatterns(prefixes: ["nodes"])
    private static let getPattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_$])ctx\s*\.\s*get\s*\(\s*(['"])(nodes\.[A-Za-z0-9._-]+)\1\s*\)"#)

    private static func makeDirectPatterns(prefixes: [String]) -> [NSRegularExpression] {
        prefixes.flatMap { prefix in
            [
                #"\s*\.\s*([A-Za-z0-9_-]+(?:\s*\.\s*[A-Za-z0-9_-]+)*?)(?=\s*\.\s*output\b)"#,
                #"\s*\[\s*['"]([A-Za-z0-9._-]+)['"]\s*\]"#,
                #"\s*\.\s*([A-Za-z0-9_-]+)"#,
            ].map { try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_$])"# + prefix + $0) }
        }
    }

    private static func pathReference(_ path: String, offset: Int) -> Reference? {
        let text = path as NSString
        for regex in pathPatterns {
            if let match = regex.firstMatch(in: path, range: NSRange(location: 0, length: text.length)) {
                let range = match.range(at: 1)
                return Reference(id: text.substring(with: range), range: NSRange(location: offset + range.location, length: range.length))
            }
        }
        return nil
    }

    private static func references(in text: String, kind: TextKind) -> [Reference] {
        let string = text as NSString
        let entireRange = NSRange(location: 0, length: string.length)
        var references: [Reference] = []
        if case .templates = kind {
            for match in templateRegex.matches(in: text, range: entireRange) {
                let range = match.range(at: 1)
                if let reference = pathReference(string.substring(with: range), offset: range.location) {
                    references.append(reference)
                }
            }
            return references
        }

        let allowBare: Bool
        let hashComments: Bool
        let documentation: Bool
        switch kind {
        case .condition: allowBare = true; hashComments = false; documentation = false
        case .code(let language):
            allowBare = false
            hashComments = !["js", "javascript"].contains(language.lowercased())
            documentation = false
        case .documentation: allowBare = false; hashComments = false; documentation = true
        case .templates: return []
        }
        let protected = protectedCharacters(in: text, hashComments: hashComments)
        let characters = Array(text.utf16)
        func isContextStart(_ location: Int) -> Bool {
            guard !protected[location] else { return false }
            var previous = location - 1
            while previous >= 0 && [9, 10, 13, 32].contains(characters[previous]) { previous -= 1 }
            guard previous >= 0 else { return true }
            // Exclude payload.ctx.nodes and payload . nodes, including spaced member access.
            if characters[previous] == 46 { return false }
            // A documented URL such as https://ctx.nodes.foo is not a context path.
            return !documentation || ![47, 58].contains(characters[previous])
        }
        for regex in directPatterns + (allowBare ? barePatterns : []) {
            for match in regex.matches(in: text, range: entireRange) {
                guard isContextStart(match.range.location) else { continue }
                let range = match.range(at: 1)
                guard !references.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) else {
                    continue
                }
                let id = string.substring(with: range)
                    .replacingOccurrences(of: #"\s"#, with: "", options: .regularExpression)
                references.append(Reference(id: id, range: range))
            }
        }
        for match in getPattern.matches(in: text, range: entireRange) where isContextStart(match.range.location) {
            let range = match.range(at: 2)
            if let reference = pathReference(string.substring(with: range), offset: range.location) {
                references.append(reference)
            }
        }
        return references
    }

    /// Protect literal text and comments before recognizing code references. Template
    /// literal expressions remain code, while their surrounding message text is protected.
    private static func protectedCharacters(in text: String, hashComments: Bool) -> [Bool] {
        let characters = Array(text.utf16)
        var result = Array(repeating: false, count: characters.count)
        var index = 0
        func protect(_ start: Int, _ end: Int) {
            for i in start..<end { result[i] = true }
        }
        func quoted(_ quote: UInt16) {
            let start = index
            index += 1
            while index < characters.count {
                if characters[index] == 92 { index = min(index + 2, characters.count); continue }
                if characters[index] == quote { index += 1; break }
                index += 1
            }
            protect(start, index)
        }
        func regexMayStart() -> Bool {
            var previous = index - 1
            while previous >= 0 && [9, 10, 13, 32].contains(characters[previous]) { previous -= 1 }
            if previous < 0 { return true }
            if Array("=([{,:;!?&|~%^<>+-*".utf16).contains(characters[previous]) { return true }
            var start = previous
            while start >= 0 && ((65...90).contains(characters[start]) || (97...122).contains(characters[start])) { start -= 1 }
            guard start < previous else { return false }
            let word = String(decoding: characters[(start + 1)...previous], as: UTF16.self)
            return ["return", "throw", "yield", "case", "delete", "void", "typeof", "instanceof", "in", "of", "await"].contains(word)
        }
        func scanRegex() {
            let start = index
            var characterClass = false
            index += 1
            while index < characters.count {
                let character = characters[index]
                if character == 10 || character == 13 { break }
                if character == 92 { index = min(index + 2, characters.count); continue }
                if character == 91 { characterClass = true }
                if character == 93 { characterClass = false }
                index += 1
                if character == 47 && !characterClass { break }
            }
            protect(start, index)
        }
        func scanTemplate() {
            var literalStart = index
            index += 1
            while index < characters.count {
                if characters[index] == 92 { index = min(index + 2, characters.count); continue }
                if characters[index] == 96 {
                    index += 1; protect(literalStart, index); return
                }
                if characters[index] == 36, index + 1 < characters.count, characters[index + 1] == 123 {
                    index += 2; protect(literalStart, index)
                    scanCode(untilClosingBrace: true)
                    literalStart = index
                } else { index += 1 }
            }
            protect(literalStart, index)
        }
        func scanCode(untilClosingBrace: Bool) {
            var braces = 0
            while index < characters.count {
                let character = characters[index]
                if character == 34 || character == 39 { quoted(character); continue }
                if character == 96, !hashComments { scanTemplate(); continue }
                if character == 35 && hashComments || !hashComments && character == 47 && index + 1 < characters.count && characters[index + 1] == 47 {
                    let start = index
                    while index < characters.count, characters[index] != 10 { index += 1 }
                    protect(start, index); continue
                }
                if !hashComments, character == 47, index + 1 < characters.count, characters[index + 1] == 42 {
                    let start = index
                    index += 2
                    while index + 1 < characters.count, !(characters[index] == 42 && characters[index + 1] == 47) { index += 1 }
                    index = min(index + 2, characters.count)
                    protect(start, index); continue
                }
                if character == 47 && !hashComments && regexMayStart() { scanRegex(); continue }
                if character == 123 { braces += 1 }
                if character == 125 {
                    if untilClosingBrace && braces == 0 { index += 1; return }
                    braces -= 1
                }
                index += 1
            }
        }
        scanCode(untilClosingBrace: false)
        return result
    }

    private static func rewrite(_ text: String, kind: TextKind, replacements: [String: String]) -> String {
        let result = NSMutableString(string: text)
        for reference in references(in: text, kind: kind).sorted(by: { $0.range.location > $1.range.location }) {
            if let replacement = replacements[reference.id] {
                result.replaceCharacters(in: reference.range, with: replacement)
            }
        }
        return result as String
    }
}
