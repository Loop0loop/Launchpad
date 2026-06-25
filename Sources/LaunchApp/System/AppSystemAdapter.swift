import AppKit
import LaunchpadCore

enum AppSystemAdapter {
    static func launch(_ app: LaunchApp) {
        guard let url = app.existingBundleURL else { return }
        NSWorkspace.shared.open(url)
    }

    static func showInFinder(_ app: LaunchApp) {
        guard let url = app.existingBundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func moveToTrash(_ app: LaunchApp) throws {
        guard let url = app.existingBundleURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    // ponytail: restarting Dock is the only reliable public way to add a persistent tile.
    static func addToDock(_ app: LaunchApp) {
        guard let url = app.existingBundleURL, let tile = dockTilePlist(for: url.path) else { return }
        run("/usr/bin/defaults", ["write", "com.apple.dock", "persistent-apps", "-array-add", tile])
        run("/usr/bin/killall", ["Dock"])
    }

    private static func dockTilePlist(for path: String) -> String? {
        let tile: [String: Any] = ["tile-data": ["file-data": ["_CFURLString": path, "_CFURLStringType": 0]]]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: tile, format: .xml, options: 0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
}
