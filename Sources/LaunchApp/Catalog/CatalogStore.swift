import Foundation
import LaunchpadCore

enum CatalogStore {
    static func scanApps(
        extraRoots: [String] = [],
        languageCode: String? = nil,
        isCancelled: () -> Bool = { false }
    ) -> [LaunchApp] {
        let roots = AppCatalog.defaultRoots() + extraRoots.map(URL.init(fileURLWithPath:))
        return AppCatalog.scan(roots: roots, languageCode: languageCode, isCancelled: isCancelled)
    }

    static func loadCachedApps() -> [LaunchApp] {
        guard let data = UserDefaults.standard.data(forKey: LaunchConstants.Storage.catalogAppsKey),
              let decoded = try? JSONDecoder().decode([LaunchApp].self, from: data) else { return [] }
        return decoded.filter { $0.existingBundleURL != nil }
    }

    static func saveCachedApps(_ apps: [LaunchApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: LaunchConstants.Storage.catalogAppsKey)
    }
}
