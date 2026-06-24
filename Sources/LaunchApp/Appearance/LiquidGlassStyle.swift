import SwiftUI

extension View {
    @ViewBuilder
    func launchGlass(
        in shape: some InsettableShape,
        interactive: Bool = false,
        clear: Bool = false
    ) -> some View {
        // .clear = high-transparency Liquid Glass. Do not layer materials/tints
        // over glassEffect; it turns the surface milky.
        let base: Glass = clear ? .clear : .regular
        let glass: Glass = interactive ? base.interactive() : base
        self.glassEffect(glass, in: shape)
    }

    /// 닫힌 폴더 타일: Liquid Glass `.regular` 단일 표면. 엣지/스페큘러/굴절은 시스템이
    /// 렌더링 — flat stroke/tint/sheen 을 얹으면 유리 위 테이프처럼 보임(스티커).
    @ViewBuilder
    func launchpadFolderChrome(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self.glassEffect(.regular, in: shape)
    }

    /// 열린 폴더 패널 크롬: 소프트 섀도만. 글래스·엣지·스페큘러는 상위 launchGlass가
    /// 단일 표면으로 처리한다. (cornerRadius는 launchGlass shape이 이미 담당.)
    func tahoeFolderPanelChrome() -> some View {
        shadow(
            color: .black.opacity(LaunchConstants.Glass.panelShadowOpacity),
            radius: LaunchConstants.Glass.panelShadowRadius,
            y: 18
        )
    }

    /// Settings panel card: native-style card with proper control background and subtle border.
    func settingsGlassCard(cornerRadius: CGFloat = LaunchConstants.Settings.cardCornerRadius) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.8)
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
