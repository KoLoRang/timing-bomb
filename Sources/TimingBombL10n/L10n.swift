import Foundation

/// Lightweight localization for TimingBomb.
///
/// Strategy: English templates are the keys; `zh-Hans` translations live in
/// `ZhHans.table`. Placeholders use `{name}` syntax so translations may reorder
/// or omit context around them freely. Missing translations fall back to the
/// English template itself, so a stale table degrades gracefully.
///
/// Language resolution (first match wins):
/// 1. `TB_LANG` environment variable (`en`, `zh`, `zh-Hans`, ...)
/// 2. `TB_LANG` user default (`defaults write -g TB_LANG zh-Hans` also works
///    for GUI launches; `./TimingBombApp -TB_LANG en` works too)
/// 3. System preferred languages (any `zh*` → `zh-Hans`)
/// 4. English
public enum L10n {
    private static let lock = NSLock()
    private static var _language: String?
    private static let debugMisses =
        ProcessInfo.processInfo.environment["TB_L10N_DEBUG"] == "1"

    /// Currently active language tag (`"en"` or `"zh-Hans"`). Cached after first use.
    public static var language: String {
        lock.lock()
        defer { lock.unlock() }
        if let language = _language { return language }
        let resolved = Self.resolve()
        _language = resolved
        return resolved
    }

    public static var isChinese: Bool { language.hasPrefix("zh") }

    /// Test/debug hook: pin the language for this process (nil = auto-detect).
    public static func setLanguage(_ tag: String?) {
        lock.lock()
        defer { lock.unlock() }
        _language = tag
    }

    /// Translates an English template, substituting `{name}` placeholders from
    /// `params`. Unmatched placeholders are left verbatim; extra params are ignored.
    public static func t(_ template: String, _ params: [String: String] = [:]) -> String {
        var text = template
        if isChinese {
            text = ZhHans.table[template] ?? template
        }
        return substitute(text, params)
    }

    /// Convenience for a `{count}` placeholder.
    public static func t(_ template: String, count: Int) -> String {
        t(template, ["count": String(count)])
    }

    /// Positional single-parameter shorthand: `t("run {0} started", [id])`.
    public static func t(_ template: String, _ params: [String]) -> String {
        var named: [String: String] = [:]
        for (index, value) in params.enumerated() { named["\(index)"] = value }
        return t(template, named)
    }

    /// Renders a wire error (code + template + params) for display.
    /// Falls back to the server-rendered `message` when no template is present.
    public static func renderError(
        template: String?, params: [String: String]?, fallback: String
    ) -> String {
        guard let template, !template.isEmpty else { return fallback }
        return t(template, params ?? [:])
    }

    // MARK: - Implementation

    private static func resolve() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let tag = environment["TB_LANG"], !tag.isEmpty { return normalize(tag) }
        // Test processes pin English unless TB_LANG overrides: test fixtures assert
        // English templates, which would otherwise follow the host system language.
        // (SPM's xctest runner does not set XCTestConfigurationFilePath, so detect
        // by executable name / loaded test classes instead.)
        if isTestProcess() { return "en" }
        if let stored = UserDefaults.standard.string(forKey: "TB_LANG"), !stored.isEmpty {
            return normalize(stored)
        }
        for preferred in Locale.preferredLanguages {
            if preferred.hasPrefix("zh") { return "zh-Hans" }
            if preferred.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    private static func isTestProcess() -> Bool {
        if let executable = CommandLine.arguments.first,
            executable.hasSuffix("/xctest") || executable.hasSuffix("swift-testing")
        {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
    }

    private static func normalize(_ tag: String) -> String {
        let lowered = tag.lowercased()
        if lowered.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }

    /// Single-pass substitution so parameter values containing `{...}` are never re-expanded.
    private static func substitute(_ text: String, _ params: [String: String]) -> String {
        guard !params.isEmpty else { return text }
        var output = ""
        var searchStart = text.startIndex
        while let open = text[searchStart...].firstIndex(of: "{") {
            guard let close = text[open...].firstIndex(of: "}"),
                close > text.index(after: open)
            else { break }
            let name = String(text[text.index(after: open)..<close])
            output += text[searchStart..<open]
            if let value = params[name] {
                output += value
            } else {
                output += "{\(name)}"
                if debugMisses { logMiss("placeholder", name, in: text) }
            }
            searchStart = text.index(after: close)
        }
        output += text[searchStart...]
        return output
    }

    private static func logMiss(_ kind: String, _ key: String, in context: String) {
        FileHandle.standardError.write(
            Data("[l10n] missing \(kind) '\(key)' in '\(context)'\n".utf8))
    }
}
