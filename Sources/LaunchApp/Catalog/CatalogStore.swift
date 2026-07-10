import Darwin
import Dispatch
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

@MainActor
final class AppCatalogMonitor {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var onChange: (@MainActor () -> Void)?

    func start(paths: [String], onChange: @escaping @MainActor () -> Void) {
        stop()
        self.onChange = onChange
        for path in Set(paths) {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            // Do not bridge a global-actor closure directly to a dispatch block.
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.onChange?()
                }
            }
            source.setCancelHandler { close(descriptor) }
            source.activate()
            sources.append(source)
        }
    }

    func stop() {
        sources.forEach { $0.cancel() }
        sources.removeAll()
        onChange = nil
    }
}
