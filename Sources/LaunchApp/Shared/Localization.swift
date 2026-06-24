import Foundation

/// Languages offered in Settings. `.system` follows the macOS preferred language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case korean
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return Localized.t("시스템", "System")
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    /// Locale code used to look up localized app names; nil = follow system.
    var localeCode: String? {
        switch self {
        case .system: return nil
        case .korean: return "ko"
        case .english: return "en"
        }
    }

    static func load() -> AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: LaunchConstants.Storage.appLanguageKey) ?? "") ?? .system
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: LaunchConstants.Storage.appLanguageKey)
    }
}

/// In-code localization for the launcher's own UI strings. Avoids `.strings`/resource-bundle
/// plumbing (which doesn't switch instantly) — `language` is read live at render time so
/// changing it re-localizes everything on the next view update.
enum Localized {
    // Single-threaded UI state; only mutated on the main thread from Settings.
    nonisolated(unsafe) static var language: AppLanguage = .system

    /// Effective two-letter code ("ko"/"en"), resolving `.system` from the OS preference.
    static var code: String {
        if let code = language.localeCode { return code }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko") ? "ko" : "en"
    }

    static func t(_ ko: String, _ en: String) -> String {
        code == "ko" ? ko : en
    }
}
