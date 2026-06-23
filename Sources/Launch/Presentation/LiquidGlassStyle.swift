import SwiftUI

extension View {
    @ViewBuilder
    func launchGlass(
        in shape: some InsettableShape,
        interactive: Bool = false,
        fallbackMaterial: Material = .ultraThinMaterial
    ) -> some View {
        if #available(macOS 26, *) {
            let glass: Glass = interactive ? .regular.interactive() : .regular
            self.glassEffect(glass, in: shape)
        } else {
            self.background(fallbackMaterial, in: shape)
        }
    }

    /// Tahoe-style search field: light Liquid Glass capsule (Spotlight / Apps inspired).
    func tahoeSearchChrome() -> some View {
        background {
            Capsule()
                .fill(.white.opacity(0.14))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
        }
    }


    /// Tahoe-style folder tile: light frosted glass square.
    func launchpadFolderChrome(cornerRadius: CGFloat) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.white.opacity(0.16))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.38), .white.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                }
        }
    }

    /// Settings panel card: frosted glass with subtle edge highlight.
    func settingsGlassCard(cornerRadius: CGFloat = LaunchConstants.Settings.cardCornerRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.white.opacity(0.08))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

struct LaunchLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.white.opacity(0.95))
            .shadow(color: .black.opacity(0.35), radius: 0.5, y: 0.5)
    }
}

extension View {
    func launchLabelStyle() -> some View {
        modifier(LaunchLabelStyle())
    }
}
