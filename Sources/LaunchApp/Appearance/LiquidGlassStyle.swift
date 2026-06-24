import SwiftUI

extension View {
    @ViewBuilder
    func launchGlass(
        in shape: some InsettableShape,
        interactive: Bool = false,
        clear: Bool = false,
        fallbackMaterial: Material = .ultraThinMaterial
    ) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            // .clear = high-transparency variant (Liquid Glass). Use it for large
            // surfaces (folder panel/tile) so wallpaper reads through. Do NOT layer
            // materials/tints over glassEffect — that turns it into a milky card.
            let base: Glass = clear ? .clear : .regular
            let glass: Glass = interactive ? base.interactive() : base
            self.glassEffect(glass, in: shape)
        } else {
            self.background(fallbackMaterial, in: shape)
        }
        #else
        self.background(fallbackMaterial, in: shape)
        #endif
    }

    /// 닫힌 폴더 타일: Liquid Glass `.regular` 단일 표면. 틴트는 글래스에 구우고
    /// 시스템이 스페큘러/엣지/굴절을 렌더링한다 — 위에 tint/sheen/stroke를 덧칠하면
    /// milky/회색 타일이 된다. `.clear`는 어두운 카드로 보이므로 타일엔 `.regular`.
    @ViewBuilder
    func launchpadFolderChrome(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = Color(nsColor: LaunchConstants.Glass.searchBarTintColor)
            .opacity(LaunchConstants.Glass.folderTileTintOpacity)
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(LaunchConstants.Glass.folderTileMaterial, in: shape)
                .overlay(shape.fill(tint))
                .overlay(shape.strokeBorder(.white.opacity(LaunchConstants.Glass.folderTileStrokeOpacity), lineWidth: 0.8))
        }
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
