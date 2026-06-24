import Foundation

public struct LaunchApp: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let path: String

    public init(id: String, name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
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
    public static func scan(roots: [URL] = defaultRoots(), languageCode: String? = nil) -> [LaunchApp] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [LaunchApp] = []

        for root in roots where fm.fileExists(atPath: root.path) {
            guard let files = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in files where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let key = bundle?.bundleIdentifier ?? url.standardizedFileURL.path
                guard seen.insert(key).inserted else { continue }

                apps.append(LaunchApp(
                    id: key,
                    name: displayName(for: url, bundle: bundle, languageCode: languageCode),
                    path: url.path
                ))
            }
        }

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func displayName(for url: URL, bundle: Bundle? = nil, languageCode: String? = nil) -> String {
        // Explicit language: read the app's <lang>.lproj/InfoPlist.strings, else fall back to
        // the base (development-language) name — exactly how macOS shows unlocalized apps.
        if let code = languageCode {
            if let localized = localizedName(for: url, languageCode: code) { return localized }
            let info = bundle?.infoDictionary
            return info?["CFBundleDisplayName"] as? String
                ?? info?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        }

        // System language.
        let info = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    /// Reads `CFBundleDisplayName`/`CFBundleName` from a specific `.lproj/InfoPlist.strings`.
    private static func localizedName(for url: URL, languageCode: String) -> String? {
        for lproj in lprojCandidates(for: languageCode) {
            let stringsURL = url.appendingPathComponent("Contents/Resources/\(lproj).lproj/InfoPlist.strings")
            guard let dict = NSDictionary(contentsOf: stringsURL) else { continue }
            if let name = dict["CFBundleDisplayName"] as? String ?? dict["CFBundleName"] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// `.lproj` directory names to try for a language (e.g. "ko" → ["ko", "ko-KR"]).
    private static func lprojCandidates(for code: String) -> [String] {
        switch code {
        case "ko": return ["ko", "ko-KR", "Korean"]
        case "en": return ["en", "en-US", "English", "Base"]
        default: return [code]
        }
    }
}

