import AppKit
import SwiftUI

struct LauncherBackgroundView: View {
    let dimOpacity: Double
    var windowed: Bool = false

    private var blendingMode: NSVisualEffectView.BlendingMode {
        windowed ? .withinWindow : .behindWindow
    }

    var body: some View {
        ZStack {
            VisualEffectView(
                material: LaunchConstants.Launcher.backgroundMaterial,
                blendingMode: blendingMode
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            Color.black.opacity(dimOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }
    }
}
