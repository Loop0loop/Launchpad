import SwiftUI

struct LauncherView: View {
    @ObservedObject var state: AppState

    init(state: AppState) {
        self.state = state
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = LaunchpadLayoutMetrics(
                size: geometry.size,
                columns: state.gridLayout.columns,
                rows: state.gridLayout.rows
            )
            let showsPageControl = state.query.isEmpty && state.displayMode == .paged && state.pageCount > 1
            let columns = Array(
                repeating: GridItem(.fixed(layout.columnWidth), spacing: layout.gridColumnSpacing),
                count: layout.columns
            )
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
                    pageWidth: geometry.size.width
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(state.openFolder == nil ? 1 : 0)
                .allowsHitTesting(state.openFolder == nil)
                .animation(LaunchConstants.Animation.fade, value: state.openFolder?.id)

                if let folder = state.openFolder {
                    FolderDimLayer(opacity: LaunchConstants.Glass.openFolderDimOpacity) {
                        state.closeFolder()
                    }

                    FolderOverlay(folder: folder, state: state, availableWidth: geometry.size.width)
                        .transition(
                            .scale(scale: LaunchConstants.Launcher.folderEntranceScale)
                                .combined(with: .opacity)
                        )
                        .zIndex(21)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(LaunchConstants.Animation.folder, value: state.openFolder?.id)
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
