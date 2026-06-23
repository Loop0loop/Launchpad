import SwiftUI

struct LauncherBackgroundView: View {
    var body: some View {
        ZStack {
            VisualEffectView(
                material: LaunchConstants.Launcher.backgroundMaterial,
                blendingMode: .behindWindow
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.22)],
                center: .center,
                startRadius: 120,
                endRadius: 820
            )
            .ignoresSafeArea()

            Color.black.opacity(LaunchConstants.Launcher.backgroundOpacity)
                .ignoresSafeArea()
        }
    }
}
