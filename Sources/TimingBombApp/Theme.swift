import SwiftUI
import TimingBombL10n

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L10n.t("System")
        case .light: return L10n.t("Light")
        case .dark: return L10n.t("Dark")
        }
    }

    var icon: String {
        switch self {
        case .system: return "macos"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    static var stored: AppearanceMode {
        AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system
    }

    static func store(_ mode: AppearanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "appearanceMode")
        apply(mode)
    }

    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// App display language. Persisted as the `TB_LANG` user default — the same
/// key the L10n module reads on launch — so the choice survives restarts.
/// `system` stores nothing and lets L10n follow the macOS preferred languages.
enum LanguageMode: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var label: String {
        switch self {
        // Language names are deliberately shown in their own language.
        case .system: return L10n.t("System")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }

    static var stored: LanguageMode {
        LanguageMode(rawValue: UserDefaults.standard.string(forKey: "TB_LANG") ?? "") ?? .system
    }

    static func store(_ mode: LanguageMode) {
        if mode == .system {
            // Store "" rather than removing the key: an app-domain empty value
            // shadows a stale `defaults write -g TB_LANG` global setting, and
            // L10n's resolver skips empty values to follow the system language.
            UserDefaults.standard.set("", forKey: "TB_LANG")
            L10n.setLanguage(nil)
        } else {
            UserDefaults.standard.set(mode.rawValue, forKey: "TB_LANG")
            L10n.setLanguage(mode.rawValue)
        }
    }
}
