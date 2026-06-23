import AppKit
import LaunchCore

enum AppSystemAdapter {
    static func launch(_ app: LaunchApp) {
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
    }

    static func showInFinder(_ app: LaunchApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }

    static func moveToTrash(_ app: LaunchApp) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: nil)
    }

    // ponytail: restarting Dock is the only reliable public way to add a persistent tile.
    static func addToDock(_ app: LaunchApp) {
        let tile = "<dict><key>tile-data</key><dict><key>file-data</key><dict>"
            + "<key>_CFURLString</key><string>\(app.path)</string>"
            + "<key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
        run("/usr/bin/defaults", ["write", "com.apple.dock", "persistent-apps", "-array-add", tile])
        run("/usr/bin/killall", ["Dock"])
    }

    private static func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
        process.waitUntilExit()
    }
}
