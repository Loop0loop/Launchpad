import Combine
import CoreGraphics

/// 드래그 중 매 프레임 갱신되는 상태(위치·머지 대상·페이지 오프셋)만 격리한 모델.
/// 이 값들은 `AppState`(그리드 전체가 관찰)에서 빼내야 한다. AppState에 두면 드래그
/// 한 틱마다 `objectWillChange`가 LauncherView 전체 트리를 재구성해 DnD가 버벅인다.
/// 여기에 두면 `LauncherDragModifier`만 관찰 → 아이콘 모디파이어만 갱신된다.
@MainActor
final class DragModel: ObservableObject {
    @Published var translation: CGSize = .zero
    @Published var hoverTargetID: String?
    /// Icon-center location in the "launcherGrid" space; the lifted copy tracks this each frame.
    @Published var location: CGPoint = .zero
    /// Offset from the pointer to the dragged icon center, captured at drag start.
    var pointerToIconCenterOffset: CGSize = .zero
    /// Horizontal page-swipe offset; changes every drag tick.
    @Published var pageOffset: CGFloat = 0

    func iconCenter(for pointerLocation: CGPoint) -> CGPoint {
        CGPoint(
            x: pointerLocation.x + pointerToIconCenterOffset.width,
            y: pointerLocation.y + pointerToIconCenterOffset.height
        )
    }
}
