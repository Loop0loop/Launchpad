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
                    // Visible when no folder is open, and while pulling an app out of a folder
                    // (the panel dissolves) so the user sees the grid it's dropping back onto.
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

                        FolderOverlay(folder: folder, state: state, availableWidth: geometry.size.width)
                            .transition(
                                .scale(scale: LaunchConstants.Launcher.folderEntranceScale)
                                    .combined(with: .opacity)
                            )
                            .zIndex(21)
                    }

                    if state.isDraggingLauncherItem, state.openFolder != nil, let app = state.draggingApp {
                        let geoGlobal = geometry.frame(in: .global)
                        let ghostPos = CGPoint(
                            x: state.launcherGridFrame.minX - geoGlobal.minX + state.drag.location.x,
                            y: state.launcherGridFrame.minY - geoGlobal.minY + state.drag.location.y
                        )
                        LoadedIcon(app: app, displaySize: layout.iconSize, loadsImage: true)
                            .frame(width: layout.iconSize, height: layout.iconSize)
                            .scaleEffect(1.1)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                            .position(ghostPos)
                            .allowsHitTesting(false)
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
