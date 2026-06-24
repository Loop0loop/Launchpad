import AppKit
import LaunchCore
import SwiftUI

private struct IconCacheKey: EnvironmentKey {
    static let defaultValue: IconCache = IconCache()
}

extension EnvironmentValues {
    var iconCache: IconCache {
        get { self[IconCacheKey.self] }
        set { self[IconCacheKey.self] = newValue }
    }
}

final class IconCache: @unchecked Sendable {
    private var icons: [String: NSImage] = [:]

    @MainActor
    func icon(for app: LaunchApp, size: CGFloat = LaunchConstants.Launcher.maxIconSize) -> NSImage {
        if let cached = icons[app.path] { return cached }

        let image = NSWorkspace.shared.icon(forFile: app.path)
        let pixelSize = size * 2
        image.size = NSSize(width: pixelSize, height: pixelSize)
        icons[app.path] = image
        return image
    }

    @MainActor func clear() {
        icons.removeAll()
    }
}
