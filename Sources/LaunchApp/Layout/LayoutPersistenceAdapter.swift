import Foundation

enum LayoutPersistenceAdapter {
    static func stringArray(forKey key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func set(_ value: [String], forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    static func data(forKey key: String) -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    static func set(_ value: Data, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
