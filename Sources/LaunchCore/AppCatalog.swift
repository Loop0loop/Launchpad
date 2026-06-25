import Foundation

public struct LaunchApp: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    public var existingBundleURL: URL? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard url.pathExtension == "app",
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return url
    }
}

public enum AppCatalog {
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            home.appendingPathComponent("Applications")
        ]
    }

    /// `languageCode` ("ko"/"en") localizes app names to that language; nil follows the system.
    public static func scan(
        roots: [URL] = defaultRoots(),
        languageCode: String? = nil,
        isCancelled: () -> Bool = { false }
    ) -> [LaunchApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [LaunchApp] = []

        guard !isCancelled() else { return [] }
        for root in roots where fm.fileExists(atPath: root.path) {
            guard let files = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in files where url.pathExtension == "app" {
                guard !isCancelled() else { return [] }
                let info = languageCode == nil
                    ? Bundle(url: url)?.localizedInfoDictionary ?? infoDictionary(for: url)
                    : infoDictionary(for: url)
                let key = info?["CFBundleIdentifier"] as? String ?? url.standardizedFileURL.path
                guard seen.insert(key).inserted else { continue }

                apps.append(LaunchApp(
                    id: key,
                    name: displayName(for: url, info: info, languageCode: languageCode),
                    path: url.path
                ))
            }
        }

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func displayName(for url: URL, bundle: Bundle? = nil, languageCode: String? = nil) -> String {
        if languageCode == nil {
            for code in Locale.preferredLanguages {
                if let localized = localizedName(for: url, languageCode: code) { return localized }
            }
        }
        return displayName(for: url, info: bundle?.localizedInfoDictionary ?? bundle?.infoDictionary, languageCode: languageCode)
    }

    private static func displayName(for url: URL, info: [String: Any]?, languageCode: String?) -> String {
        if let code = languageCode {
            if let localized = localizedName(for: url, languageCode: code) { return localized }
            return info?["CFBundleDisplayName"] as? String
                ?? info?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        }

        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    /// Resolves the app's localized name. Modern macOS apps keep these in
    /// `Contents/Resources/InfoPlist.loctable` (a dict keyed by language code); older apps
    /// use `<lang>.lproj/InfoPlist.strings`. We try the loctable first, then the .strings.
    private static func localizedName(for url: URL, languageCode: String) -> String? {
        let candidates = lprojCandidates(for: languageCode)

        let loctableURL = url.appendingPathComponent("Contents/Resources/InfoPlist.loctable")
        if let table = NSDictionary(contentsOf: loctableURL) {
            for lang in candidates {
                guard let entry = table[lang] as? [String: Any] else { continue }
                if let name = entry["CFBundleDisplayName"] as? String ?? entry["CFBundleName"] as? String, !name.isEmpty {
                    return name
                }
            }
        }

        for lproj in candidates {
            let stringsURL = url.appendingPathComponent("Contents/Resources/\(lproj).lproj/InfoPlist.strings")
            guard let dict = NSDictionary(contentsOf: stringsURL) else { continue }
            if let name = dict["CFBundleDisplayName"] as? String ?? dict["CFBundleName"] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private static func infoDictionary(for url: URL) -> [String: Any]? {
        NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    /// `.lproj` directory names to try for a language (e.g. "ko" → ["ko", "ko-KR"]).
    private static func lprojCandidates(for code: String) -> [String] {
        var candidates: [String] = []
        func append(_ candidate: String) {
            guard !candidate.isEmpty, !candidates.contains(candidate) else { return }
            candidates.append(candidate)
        }

        append(code)
        append(code.replacingOccurrences(of: "-", with: "_"))

        let language = code
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init) ?? code
        append(language)

        switch language {
        case "ko":
            append("Korean")
        case "en":
            append("English")
            append("Base")
        default:
            break
        }

        return candidates
    }
}
