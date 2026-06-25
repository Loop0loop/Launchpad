import LaunchpadCore
import SwiftUI

struct LauncherView: View {
    @ObservedObject var state: AppState

    init(state: AppState) {
        self.state = state
    }

    var body: some View {
        GeometryReader { geometry in
            if state.launcherVisible {
                let layout = LaunchpadLayoutMetrics(
                    size: geometry.size,
                    columns: state.gridLayout.columns,
                    rows: state.gridLayout.rows
                )
                let columns = Array(
                    repeating: GridItem(.fixed(layout.columnWidth), spacing: layout.gridColumnSpacing),
                    count: layout.columns
                )
                let visibleItems = state.visibleItems
                let pageSize = state.gridLayout.pageSize
                let pageCount = max(1, Int(ceil(Double(visibleItems.count) / Double(pageSize))))
                let showsPageControl = state.searchQuery.isEmpty && state.displayMode == .paged && pageCount > 1
                let gridHeight = layout.gridHeight(showsPageControl: showsPageControl)

                ZStack {
                    LauncherBackgroundView(
                        dimOpacity: state.appearance.backgroundDimOpacity,
                        windowed: state.windowBrowsingMode
                    )

                    LauncherDismissLayer {
                        LaunchLog.line("background tap dismiss")
                        state.dismissFromBackground()
                    }

                    LauncherContent(
                        state: state,
                        layout: layout,
                        columns: columns,
                        gridHeight: gridHeight,
                        showsPageControl: showsPageControl,
                        pageWidth: geometry.size.width,
                        visibleItems: visibleItems,
                        pageCount: pageCount,
                        pageSize: pageSize
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(state.openFolder == nil ? 1 : 0)
                    .allowsHitTesting(state.openFolder == nil || state.isDraggingLauncherItem)
                    .animation(LaunchConstants.Animation.fade, value: state.openFolder?.id)

                    if let folder = state.openFolder {
                        FolderDimLayer(opacity: LaunchConstants.Glass.openFolderDimOpacity) {
                            state.closeFolder()
                        }
                        // 드래그 중에는 dim의 탭 제스처가 진행 중인 그리드 드래그를 가로채지 못하게 한다.
                        .allowsHitTesting(!state.isDraggingLauncherItem)

                        FolderOverlay(folder: folder, state: state, availableWidth: geometry.size.width)
                            .transition(
                                .scale(scale: LaunchConstants.Launcher.folderEntranceScale)
                                    .combined(with: .opacity)
                            )
                            .zIndex(21)
                    }

                    if state.isDraggingLauncherItem, state.openFolder != nil, let app = state.draggingApp {
                        let geoGlobal = geometry.frame(in: .global)
                        // launcherGrid 로컬 → ZStack(geo) 로컬 변환 오프셋. 드래그 중 안정적이라 한 번만 계산.
                        let originOffset = CGPoint(
                            x: state.launcherGridFrame.minX - geoGlobal.minX,
                            y: state.launcherGridFrame.minY - geoGlobal.minY
                        )
                        // DragModel을 직접 관찰하는 전용 뷰. LauncherView 전체 리렌더 없이 고스트만 포인터를 따라간다.
                        DragGhostView(drag: state.drag, app: app, iconSize: layout.iconSize, originOffset: originOffset)
                            .zIndex(22)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .animation(LaunchConstants.Animation.folder, value: state.openFolder?.id)
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea()
        .onExitCommand { state.handleEscape() }
    }
}

/// Spring-loaded 드롭 중 포인터를 따라다니는 드래그 고스트. `DragModel`을 `@ObservedObject`로
/// 직접 구독해, 부모(LauncherView)를 리렌더하지 않고 이 뷰만 매 프레임 위치를 갱신한다.
private struct DragGhostView: View {
    @ObservedObject var drag: DragModel
    let app: LaunchApp
    let iconSize: CGFloat
    let originOffset: CGPoint

    var body: some View {
        LoadedIcon(app: app, displaySize: iconSize, loadsImage: true)
            .frame(width: iconSize, height: iconSize)
            .scaleEffect(1.1)
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            .position(x: originOffset.x + drag.location.x, y: originOffset.y + drag.location.y)
            .allowsHitTesting(false)
    }
}

private struct FolderDimLayer: View {
    let opacity: Double
    let close: () -> Void

    var body: some View {
        Rectangle()
            .fill(.black.opacity(opacity))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture().onEnded {
                    LaunchLog.line("folder dim tapped")
                    close()
                }
            )
            .transition(.opacity)
            .zIndex(20)
    }
}
