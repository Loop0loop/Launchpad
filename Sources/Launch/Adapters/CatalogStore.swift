import Foundation
import LaunchCore

enum CatalogStore {
    static func scanApps(extraRoots: [String] = []) -> [LaunchApp] {
        let roots = AppCatalog.defaultRoots() + extraRoots.map(URL.init(fileURLWithPath:))
        return AppCatalog.scan(roots: roots)
    }
}
