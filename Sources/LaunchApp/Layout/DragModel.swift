import Combine
import CoreGraphics

@MainActor
final class DragPositionModel: ObservableObject {
    @Published var location: CGPoint = .zero
}

/// 드래그 상태를 AppState에서 격리한다. 위치는 다시 작은 모델로 분리해 포인터가
/// 움직일 때 들린 아이콘 하나만 다시 그린다.
@MainActor
final class DragModel: ObservableObject {
    @Published var hoverTargetID: String?
    let position = DragPositionModel()
    var location: CGPoint {
        get { position.location }
        set { position.location = newValue }
    }
    /// Offset from the pointer to the dragged icon center, captured at drag start.
    var pointerToIconCenterOffset: CGSize = .zero
    /// Horizontal page-swipe offset.
    @Published var pageOffset: CGFloat = 0

    func iconCenter(for pointerLocation: CGPoint) -> CGPoint {
        CGPoint(
            x: pointerLocation.x + pointerToIconCenterOffset.width,
            y: pointerLocation.y + pointerToIconCenterOffset.height
        )
    }
}
