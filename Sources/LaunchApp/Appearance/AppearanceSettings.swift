import Foundation

struct AppearanceSettings: Equatable, Codable {
    /// 0 = heavy dim, 1 = wallpaper shows through most.
    var backgroundTransparency: Double
    /// Dim behind folder overlay when open.
    var folderDimOpacity: Double

    static let defaults = AppearanceSettings(
        backgroundTransparency: LaunchConstants.Appearance.defaultBackgroundTransparency,
        folderDimOpacity: LaunchConstants.Appearance.defaultFolderDimOpacity
    )

    var backgroundDimOpacity: Double {
        (1 - backgroundTransparency.clamped(to: 0...1)) * LaunchConstants.Appearance.maxBackgroundDim
    }

    var clamped: AppearanceSettings {
        AppearanceSettings(
            backgroundTransparency: backgroundTransparency.clamped(to: 0...1),
            folderDimOpacity: folderDimOpacity.clamped(
                to: LaunchConstants.Appearance.minFolderDim...LaunchConstants.Appearance.maxFolderDim
            )
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
