import SwiftUI

struct LauncherBackgroundView: View {
    let dimOpacity: Double

    var body: some View {
        ZStack {
            VisualEffectView(
                material: LaunchConstants.Launcher.backgroundMaterial,
                blendingMode: .behindWindow
            )
            .ignoresSafeArea()

            Color.black.opacity(dimOpacity)
                .ignoresSafeArea()
        }
    }
}
