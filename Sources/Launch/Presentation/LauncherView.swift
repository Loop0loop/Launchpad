import LaunchCore
import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    @ObservedObject var state: AppState

    var body: some View {
        GeometryReader { geometry in
            let layout = LaunchpadLayoutMetrics(size: geometry.size)
            let showsPageControl = state.query.isEmpty
            let columns = Array(
                repeating: GridItem(.fixed(layout.columnWidth), spacing: layout.gridColumnSpacing),
                count: layout.columns
            )
            let gridHeight = layout.gridHeight(showsPageControl: showsPageControl)

            ZStack {
                LauncherBackgroundView(dimOpacity: state.appearance.backgroundDimOpacity)
                    .contentShape(Rectangle())
                    .onTapGesture { state.handleEscape() }

                VStack(spacing: 0) {
                    Color.clear.frame(height: layout.safeTopInset)

                    LauncherSearchField(query: $state.query, isVisible: state.launcherVisible)
                        .frame(height: layout.searchBarHeight)

                    Color.clear.frame(height: layout.searchToGridGap)

                    if state.query.isEmpty {
                        PagedGridView(
                            state: state,
                            layout: layout,
                            columns: columns,
                            pageWidth: geometry.size.width,
                            gridHeight: gridHeight
                        )
                        .frame(height: gridHeight)
                    } else {
                        searchResultsGrid(layout: layout, columns: columns)
                            .frame(height: gridHeight)
                    }

                    if showsPageControl {
                        Color.clear.frame(height: layout.gridToPagerGap)

                        LauncherPageControl(state: state)
                            .frame(height: layout.pageControlHeight)
                    }

                    Color.clear.frame(height: layout.safeBottomInset)
                }
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
    private func searchResultsGrid(layout: LaunchpadLayoutMetrics, columns: [GridItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: layout.gridRowSpacing) {
                ForEach(state.visibleItems) { item in
                    LauncherItemView(item: item, state: state, layout: layout)
                }
            }
            .padding(.horizontal, layout.horizontalPadding)
        }
    }
}

struct PagedGridView: View {
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let columns: [GridItem]
    let pageWidth: CGFloat
    let gridHeight: CGFloat

    @State private var dragOffset: CGFloat = 0
    @State private var dragStartPage = 0
    @State private var pageLockedUntil = Date.distantPast

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
        .animation(isDragging ? nil : LaunchConstants.Animation.spring, value: state.currentPage)
        .animation(isDragging ? nil : LaunchConstants.Animation.spring, value: dragOffset)
        .gesture(pageDragGesture)
        .clipped()
    }

    private var isDragging: Bool {
        dragOffset != 0
    }

    private var pageOffset: CGFloat {
        -CGFloat(state.currentPage) * pageWidth + dragOffset
    }

    private var pageDragGesture: some Gesture {
        DragGesture(minimumDistance: LaunchConstants.Launcher.dragMinimumDistance)
            .onChanged { value in
                guard state.query.isEmpty, state.openFolder == nil else { return }
                guard Date() >= pageLockedUntil else { return }

                if dragOffset == 0 {
                    dragStartPage = state.currentPage
                }

                let maxRubber = pageWidth * LaunchConstants.Launcher.pageRubberBandRatio
                var next = value.translation.width

                if dragStartPage == 0, next > 0 {
                    next = min(next, maxRubber)
                }
                if dragStartPage == state.pageCount - 1, next < 0 {
                    next = max(next, -maxRubber)
                }

                dragOffset = next
            }
            .onEnded { value in
                guard state.query.isEmpty, state.openFolder == nil else {
                    dragOffset = 0
                    return
                }

                let threshold = max(pageWidth * LaunchConstants.Launcher.pageSwipeThresholdRatio, LaunchConstants.Launcher.pageDragThreshold)
                var target = dragStartPage

                if value.translation.width < -threshold {
                    target = min(dragStartPage + 1, state.pageCount - 1)
                } else if value.translation.width > threshold {
                    target = max(dragStartPage - 1, 0)
                }

                withAnimation(LaunchConstants.Animation.spring) {
                    if target != dragStartPage {
                        state.goToPage(target)
                    }
                    dragOffset = 0
                }

                if target != dragStartPage {
                    pageLockedUntil = Date().addingTimeInterval(LaunchConstants.Launcher.pageChangeCooldown)
                }
            }
    }
}

struct LauncherSearchField: View {
    @Binding var query: String
    let isVisible: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))

                TextField(LaunchConstants.Launcher.searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: LaunchConstants.Launcher.searchFontSize, weight: .regular))
                    .foregroundStyle(.white.opacity(0.95))
                    .focused($focused)
            }
            .padding(.horizontal, LaunchConstants.Launcher.searchHorizontalPadding)
            .frame(width: LaunchConstants.Launcher.searchWidth, height: LaunchConstants.Launcher.searchHeight)
            .launcherSearchChrome()
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
        .onChange(of: isVisible) { _, visible in
            if visible { focused = true }
        }
    }
}

struct LauncherPageControl: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: LaunchConstants.Launcher.pageControlSpacing) {
            pageNavButton(systemName: "chevron.left", enabled: state.currentPage > 0) {
                withAnimation(LaunchConstants.Animation.spring) {
                    state.changePage(-1)
                }
            }

            HStack(spacing: LaunchConstants.Launcher.pageDotSpacing) {
                ForEach(0..<state.pageCount, id: \.self) { page in
                    Circle()
                        .fill(page == state.currentPage ? .white : .white.opacity(LaunchConstants.Launcher.inactivePageOpacity))
                        .frame(
                            width: LaunchConstants.Launcher.pageDotSize,
                            height: LaunchConstants.Launcher.pageDotSize
                        )
                        .scaleEffect(page == state.currentPage ? LaunchConstants.Launcher.pageIndicatorActiveScale : 1)
                        .animation(LaunchConstants.Animation.fade, value: state.currentPage)
                        .onTapGesture {
                            withAnimation(LaunchConstants.Animation.spring) {
                                state.goToPage(page)
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .launcherPageDotsChrome()

            pageNavButton(systemName: "chevron.right", enabled: state.currentPage < state.pageCount - 1) {
                withAnimation(LaunchConstants.Animation.spring) {
                    state.changePage(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pageNavButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.9 : 0.35))
                .frame(
                    width: LaunchConstants.Launcher.pageNavButtonSize,
                    height: LaunchConstants.Launcher.pageNavButtonSize
                )
                .launcherPageNavChrome()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .shadow(color: .black.opacity(enabled ? 0.3 : 0), radius: 8, y: 3)
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
            return NSItemProvider(object: app.id as NSString)
        }
        .contextMenu {
            appContextMenu
        }
        .onDrop(of: [UTType.text], delegate: AppDropDelegate(targetID: app.id, state: state))
    }

    @ViewBuilder
    private var appContextMenu: some View {
        Button(LaunchConstants.Menu.openApp) {
            state.launch(app)
        }

        Button(LaunchConstants.Menu.showInFinder) {
            state.revealInFinder(app)
        }
    }
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
            return NSItemProvider(object: app.id as NSString)
        }
        .contextMenu {
            appContextMenu
        }
        .onDrop(of: [UTType.text], delegate: AppDropDelegate(targetID: app.id, state: state))
    }

    @ViewBuilder
    private var appContextMenu: some View {
        Button(LaunchConstants.Menu.openApp) {
            state.launch(app)
        }

        Button(LaunchConstants.Menu.showInFinder) {
            state.revealInFinder(app)
        }
    }
}
