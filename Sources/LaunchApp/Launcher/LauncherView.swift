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
                    .opacity(state.openFolder == nil || state.folderDragPullingOut ? 1 : 0)
                    .allowsHitTesting(state.openFolder == nil || state.isDraggingLauncherItem)
                    .animation(LaunchConstants.Animation.fade, value: state.openFolder?.id)
                    .animation(LaunchConstants.Animation.fade, value: state.folderDragPullingOut)

                    if let folder = state.openFolder {
                        FolderDimLayer(opacity: LaunchConstants.Glass.openFolderDimOpacity) {
                            state.closeFolder()
                        }
                        .opacity(state.folderDragPullingOut ? 0 : 1)
                        .animation(LaunchConstants.Animation.fade, value: state.folderDragPullingOut)
                        // 드래그 중에는 dim의 탭 제스처가 진행 중인 그리드 드래그를 가로채지 못하게 한다.
                        .allowsHitTesting(!state.isHandlingLauncherDrag)

                        FolderOverlay(folder: folder, state: state, availableWidth: geometry.size.width)
                            .transition(
                                .scale(scale: LaunchConstants.Launcher.folderEntranceScale)
                                    .combined(with: .opacity)
                            )
                            .zIndex(21)
                    }

                    let needsDetachedGhost = state.openFolder != nil || state.draggedCellCenter(layout: layout) == nil
                    if state.isDraggingLauncherItem, needsDetachedGhost, let item = state.draggingLauncherItem {
                        let geoGlobal = geometry.frame(in: .global)
                        // launcherGrid 로컬 → ZStack(geo) 로컬 변환 오프셋. 드래그 중 안정적이라 한 번만 계산.
                        let originOffset = CGPoint(
                            x: state.launcherGridFrame.minX - geoGlobal.minX,
                            y: state.launcherGridFrame.minY - geoGlobal.minY
                        )
                        // DragModel을 직접 관찰하는 전용 뷰. LauncherView 전체 리렌더 없이 고스트만 포인터를 따라간다.
                        DragGhostView(drag: state.drag, item: item, iconSize: layout.iconSize, originOffset: originOffset)
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
    let item: LauncherItem
    let iconSize: CGFloat
    let originOffset: CGPoint

    private var miniIconSize: CGFloat {
        iconSize * LaunchConstants.Icon.folderPreviewScale
    }

    private var miniGap: CGFloat {
        iconSize * LaunchConstants.Icon.folderPreviewGapRatio
    }

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .app(let app):
            LoadedIcon(app: app, displaySize: iconSize, loadsImage: true)
                .frame(width: iconSize, height: iconSize)
        case .folder(_, let apps):
            ZStack {
                Color.clear
                    .frame(width: iconSize, height: iconSize)
                    .launchpadFolderChrome(cornerRadius: LaunchConstants.Icon.folderCornerRadius)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(miniIconSize), spacing: miniGap),
                        count: LaunchConstants.Icon.folderPreviewColumns
                    ),
                    spacing: miniGap
                ) {
                    ForEach(apps.prefix(LaunchConstants.Icon.folderPreviewLimit)) { app in
                        LoadedIcon(
                            app: app,
                            displaySize: miniIconSize,
                            loadSize: miniIconSize,
                            loadsImage: true,
                            cachesImageInMemory: false
                        )
                    }
                }
            }
            .frame(width: iconSize, height: iconSize)
        }
    }

    var body: some View {
        icon
            .scaleEffect(1.1)
            .opacity(drag.hoverTargetID == nil ? 0.95 : 0.55)
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
