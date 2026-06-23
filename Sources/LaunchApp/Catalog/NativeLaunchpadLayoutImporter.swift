import Foundation
import LaunchCore

enum NativeLaunchpadLayoutImporter {
    static func importOrder(apps: [LaunchApp]) -> [String] {
        let appIDs = Set(apps.map(\.id))
        for database in dockDatabases() {
            for query in queries {
                let imported = bundleIDs(from: database, query: query).filter(appIDs.contains)
                if !imported.isEmpty { return imported }
            }
        }
        return []
    }

    private static let queries = [
        "select apps.bundleid from apps join items on apps.item_id = items.rowid order by items.ordering;",
        "select bundleid from apps order by title;"
    ]

    private static func dockDatabases() -> [URL] {
        let root = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dock")
        guard let files = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "db" }
    }

    private static func bundleIDs(from database: URL, query: String) -> [String] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, query]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }
}
