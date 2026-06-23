import LaunchCore
import SwiftUI
import UniformTypeIdentifiers

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

                launcherContent(
                    layout: layout,
                    columns: columns,
                    gridHeight: gridHeight,
                    showsPageControl: showsPageControl,
                    pageWidth: geometry.size.width
                )
                .frame(width: geometry.size.width, height: geometry.size.height)

                if let folder = state.openFolder {
                    Color.black.opacity(state.appearance.folderDimOpacity)
                        .ignoresSafeArea()
                        .onTapGesture { state.closeFolder() }
                        .zIndex(20)

                    FolderOverlay(folder: folder, state: state)
                        .zIndex(21)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .onExitCommand { state.handleEscape() }
    }

    @ViewBuilder
    private func launcherContent(
        layout: LaunchpadLayoutMetrics,
        columns: [GridItem],
        gridHeight: CGFloat,
        showsPageControl: Bool,
        pageWidth: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: layout.safeTopInset)

            LauncherSearchField(
                query: $state.query,
                isVisible: state.launcherVisible,
                onFieldReady: { state.searchField = $0 }
            )
                .frame(height: layout.searchBarHeight)

            Spacer(minLength: layout.searchToGridGap)

            Group {
                if state.query.isEmpty, state.displayMode == .paged {
                    PagedGridView(
                        state: state,
                        layout: layout,
                        columns: columns,
                        pageWidth: pageWidth,
                        gridHeight: gridHeight
                    )
                } else {
                    searchResultsGrid(layout: layout, columns: columns)
                }
            }
            .frame(height: gridHeight)

            if showsPageControl {
                Spacer(minLength: layout.gridToPagerGap)

                LauncherPageControl(
                    state: state,
                    selectPage: state.selectPage
                )
                .frame(height: layout.pageControlHeight)
            }

            Spacer(minLength: layout.safeBottomInset)
        }
    }

    @ViewBuilder
    private func searchResultsGrid(layout: LaunchpadLayoutMetrics, columns: [GridItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: layout.gridRowSpacing) {
                ForEach(state.visibleItems) { item in
                    LauncherItemView(item: item, state: state, layout: layout)
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
            .frame(minHeight: layout.gridHeight(showsPageControl: false), alignment: .top)
        }
    }
}

struct PagedGridView: View {
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let columns: [GridItem]
    let pageWidth: CGFloat
    let gridHeight: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<state.pageCount, id: \.self) { page in
                LazyVGrid(columns: columns, spacing: layout.gridRowSpacing) {
                    ForEach(state.items(forPage: page)) { item in
                        LauncherItemView(item: item, state: state, layout: layout)
                    }
                }
                .frame(width: pageWidth, height: gridHeight, alignment: .top)
            }
        }
        .offset(x: pageOffset)
        .frame(width: pageWidth, alignment: .leading)
        .clipped()
        .animation(LaunchConstants.Animation.spring, value: state.currentPage)
        .animation(LaunchConstants.Animation.spring, value: state.pageDragOffset)
        .frame(height: gridHeight)
    }

    private var pageOffset: CGFloat {
        -CGFloat(state.currentPage) * pageWidth + state.pageDragOffset
    }
}

struct LauncherSearchField: View {
    @Binding var query: String
    let isVisible: Bool
    var onFieldReady: (NSTextField) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .allowsHitTesting(false)

            LauncherNativeSearchField(
                text: $query,
                requestFocus: isVisible,
                onFieldReady: onFieldReady
            )
            .frame(minWidth: 180, maxWidth: .infinity, minHeight: LaunchConstants.Launcher.searchHeight)

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LaunchConstants.Launcher.searchHorizontalPadding)
        .frame(width: LaunchConstants.Launcher.searchWidth, height: LaunchConstants.Launcher.searchHeight)
        .background {
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
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LauncherPageControl: View {
    @ObservedObject var state: AppState
    let selectPage: (Int) -> Void

    var body: some View {
        HStack(spacing: LaunchConstants.Launcher.pageDotSpacing) {
            ForEach(0..<state.pageCount, id: \.self) { page in
                Circle()
                    .fill(page == state.currentPage ? .white : .white.opacity(LaunchConstants.Launcher.inactivePageOpacity))
                    .frame(
                        width: LaunchConstants.Launcher.pageDotSize,
                        height: LaunchConstants.Launcher.pageDotSize
                    )
                    .scaleEffect(page == state.currentPage ? LaunchConstants.Launcher.pageIndicatorActiveScale : 1)
                    .padding(6)
                    .contentShape(Rectangle())
                    .animation(LaunchConstants.Animation.fade, value: state.currentPage)
                    .onTapGesture {
                        LaunchLog.line("page dot tapped page=\(page)")
                        withAnimation(LaunchConstants.Animation.spring) {
                            selectPage(page)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

@ViewBuilder
private func keyboardSelectionBackground(isSelected: Bool) -> some View {
    if isSelected {
        RoundedRectangle(cornerRadius: LaunchConstants.Icon.folderCornerRadius)
            .strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }
}

struct LauncherItemView: View {
    let item: LauncherItem
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics

    var body: some View {
        switch item {
        case .app(let app):
            AppIcon(app: app, state: state, layout: layout)
        case .folder(let folder, let apps):
            FolderIcon(folder: folder, apps: apps, state: state, layout: layout)
        }
    }
}

struct AppIcon: View {
    let app: LaunchApp
    @ObservedObject var state: AppState
    @Environment(\.iconCache) private var iconCache
    let layout: LaunchpadLayoutMetrics

    var body: some View {
        Button {
            state.launch(app)
        } label: {
            VStack(spacing: LaunchConstants.Icon.spacing) {
                Image(nsImage: iconCache.icon(for: app, size: layout.iconSize))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: layout.iconSize, height: layout.iconSize)
                    .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)

                Text(app.name)
                    .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: layout.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
                    .launchLabelStyle()
            }
            .frame(width: layout.columnWidth)
            .opacity(state.draggedAppID == app.id ? LaunchConstants.Icon.draggedOpacity : 1)
            .overlay(keyboardSelectionBackground(isSelected: state.showsKeyboardSelection(for: app.id)))
        }
        .buttonStyle(.plain)
        .onDrag {
            state.draggedAppID = app.id
            return dockItemProvider(for: app)
        }
        .contextMenu {
            launcherAppContextMenu(app: app, state: state)
        }
        .onDrop(of: [UTType.text], delegate: AppDropDelegate(targetID: app.id, state: state))
    }
}

@MainActor @ViewBuilder
func launcherAppContextMenu(app: LaunchApp, state: AppState) -> some View {
    Button(LaunchConstants.Menu.openApp) { state.launch(app) }
    Button(LaunchConstants.Menu.showInFinder) { state.revealInFinder(app) }
    Button(LaunchConstants.Menu.addToDock) { state.addToDock(app) }
    Divider()
    Button(LaunchConstants.Menu.hide) { state.hide(app) }
    Divider()
    Button(LaunchConstants.Menu.moveToTrash, role: .destructive) { state.moveToTrash(app) }
}

struct FolderIcon: View {
    let folder: LaunchFolder
    let apps: [LaunchApp]
    @ObservedObject var state: AppState
    @Environment(\.iconCache) private var iconCache
    let layout: LaunchpadLayoutMetrics

    private var miniIconSize: CGFloat {
        layout.iconSize * LaunchConstants.Icon.folderPreviewScale
    }

    var body: some View {
        Button {
            state.openFolder = folder
        } label: {
            VStack(spacing: LaunchConstants.Icon.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: LaunchConstants.Icon.folderCornerRadius)
                        .frame(width: layout.iconSize, height: layout.iconSize)
                        .launchpadFolderChrome(cornerRadius: LaunchConstants.Icon.folderCornerRadius)

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(miniIconSize), spacing: 0),
                            count: LaunchConstants.Icon.folderPreviewColumns
                        ),
                        spacing: 0
                    ) {
                        ForEach(apps.prefix(LaunchConstants.Icon.folderPreviewLimit)) { app in
                            Image(nsImage: iconCache.icon(for: app, size: layout.iconSize))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: miniIconSize, height: miniIconSize)
                        }
                    }
                }

                Text(folder.name)
                    .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: layout.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
                    .launchLabelStyle()
            }
            .frame(width: layout.columnWidth)
            .overlay(keyboardSelectionBackground(isSelected: state.showsKeyboardSelection(for: folder.id)))
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.text], delegate: FolderDropDelegate(targetID: folder.id, state: state))
    }
}

struct FolderOverlay: View {
    let folder: LaunchFolder
    @ObservedObject var state: AppState
    @State private var isVisible = false

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(LaunchConstants.FolderOverlay.gridItemWidth), spacing: LaunchConstants.FolderOverlay.gridSpacing),
            count: LaunchConstants.FolderOverlay.columns
        )
    }

    var body: some View {
        folderContent
            .scaleEffect(isVisible ? 1 : LaunchConstants.Launcher.folderEntranceScale)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(LaunchConstants.Animation.spring) {
                    isVisible = true
                }
            }
            .onChange(of: folder.id) { _, _ in
                isVisible = false
                withAnimation(LaunchConstants.Animation.spring) {
                    isVisible = true
                }
            }
    }

    @ViewBuilder
    private var folderContent: some View {
        if #available(macOS 26, *) {
            folderPanel
                .launchGlass(in: RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius), interactive: false)
        } else {
            folderPanel
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius))
        }
    }

    private var folderPanel: some View {
        VStack(spacing: LaunchConstants.FolderOverlay.spacing) {
            Text(folder.name)
                .font(.system(size: LaunchConstants.FolderOverlay.titleFontSize, weight: .semibold))
                .launchLabelStyle()

            LazyVGrid(columns: columns, spacing: LaunchConstants.FolderOverlay.spacing) {
                ForEach(state.apps(in: folder)) { app in
                    FolderOverlayAppIcon(app: app, state: state)
                }
            }
            .frame(minHeight: LaunchConstants.FolderOverlay.minGridHeight, alignment: .top)
        }
        .padding(LaunchConstants.FolderOverlay.padding)
        .frame(width: LaunchConstants.FolderOverlay.width)
    }
}

struct FolderOverlayAppIcon: View {
    let app: LaunchApp
    @ObservedObject var state: AppState
    @Environment(\.iconCache) private var iconCache

    var body: some View {
        Button {
            state.launch(app)
        } label: {
            VStack(spacing: LaunchConstants.Icon.spacing) {
                Image(nsImage: iconCache.icon(for: app, size: LaunchConstants.FolderOverlay.maxIconSize))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: LaunchConstants.FolderOverlay.maxIconSize, height: LaunchConstants.FolderOverlay.maxIconSize)
                    .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)

                Text(app.name)
                    .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: LaunchConstants.FolderOverlay.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
                    .launchLabelStyle()
            }
            .frame(width: LaunchConstants.FolderOverlay.gridItemWidth)
            .opacity(state.draggedAppID == app.id ? LaunchConstants.Icon.draggedOpacity : 1)
        }
        .buttonStyle(.plain)
        .onDrag {
            state.draggedAppID = app.id
            return dockItemProvider(for: app)
        }
        .contextMenu {
            launcherAppContextMenu(app: app, state: state)
        }
        .onDrop(of: [UTType.text], delegate: AppDropDelegate(targetID: app.id, state: state))
    }
}

private func dockItemProvider(for app: LaunchApp) -> NSItemProvider {
    let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: app.path))
        ?? NSItemProvider()
    provider.registerObject(app.id as NSString, visibility: .all)
    return provider
}
