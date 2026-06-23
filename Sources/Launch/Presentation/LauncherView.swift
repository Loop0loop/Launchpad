import LaunchCore
import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    @ObservedObject var state: AppState
    @StateObject private var iconCache = IconCache()
    @Namespace private var folderAnimation

    private let columns = Array(
        repeating: GridItem(.fixed(LaunchConstants.Launcher.gridItemWidth), spacing: LaunchConstants.Launcher.gridSpacing),
        count: LaunchConstants.Launcher.columns
    )

    var body: some View {
        ZStack {
            LauncherBackgroundView()

            VStack(spacing: LaunchConstants.Launcher.verticalSpacing) {
                LauncherSearchField(query: $state.query)

                ZStack {
                    LazyVGrid(columns: columns, spacing: LaunchConstants.Launcher.gridRowSpacing) {
                        ForEach(state.pageItems) { item in
                            LauncherItemView(
                                item: item,
                                state: state,
                                iconCache: iconCache,
                                folderNamespace: folderAnimation
                            )
                        }
                    }
                    .frame(height: LaunchConstants.Launcher.gridHeight, alignment: .top)
                    .id(state.currentPage)
                    .transition(pageTransition(for: state.pageDirection))
                }
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: state.currentPage)

                LauncherPageIndicator(pageCount: state.pageCount, currentPage: state.currentPage)
            }
            .padding(.top, LaunchConstants.Launcher.topPadding)
            .opacity(state.launcherVisible ? 1 : 0)
            .scaleEffect(state.launcherVisible ? 1 : LaunchConstants.Launcher.contentHiddenScale)
            .animation(.spring(response: 0.28, dampingFraction: 0.88), value: state.launcherVisible)

            if let folder = state.openFolder {
                Color.black.opacity(LaunchConstants.Launcher.overlayOpacity)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { state.closeFolder() }

                FolderOverlay(folder: folder, state: state, namespace: folderAnimation)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
            }
        }
        .gesture(
            DragGesture(minimumDistance: LaunchConstants.Launcher.dragMinimumDistance)
                .onEnded { value in
                    if value.translation.width < -LaunchConstants.Launcher.pageDragThreshold {
                        state.changePage(1)
                    } else if value.translation.width > LaunchConstants.Launcher.pageDragThreshold {
                        state.changePage(-1)
                    }
                }
        )
        .onExitCommand {
            if state.query.isEmpty {
                state.closeLauncher?()
            } else {
                state.query = ""
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: state.openFolder?.id)
    }

    private func pageTransition(for direction: Int) -> AnyTransition {
        let edge: Edge = direction >= 0 ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }
}

struct LauncherSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))

            TextField(LaunchConstants.Launcher.searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: LaunchConstants.Launcher.searchFontSize, weight: .regular))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, LaunchConstants.Launcher.searchHorizontalPadding)
        .frame(width: LaunchConstants.Launcher.searchWidth, height: LaunchConstants.Launcher.searchHeight)
        .launchGlassCapsule()
    }
}

struct LauncherPageIndicator: View {
    let pageCount: Int
    let currentPage: Int

    var body: some View {
        if pageCount > 1 {
            HStack(spacing: LaunchConstants.Launcher.pageDotSpacing) {
                ForEach(0..<pageCount, id: \.self) { page in
                    Circle()
                        .fill(page == currentPage ? .white : .white.opacity(LaunchConstants.Launcher.inactivePageOpacity))
                        .frame(width: LaunchConstants.Launcher.pageDotSize, height: LaunchConstants.Launcher.pageDotSize)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .launchGlass(in: Capsule(), interactive: false)
            .frame(height: LaunchConstants.Launcher.pageDotHeight)
        } else {
            Color.clear.frame(height: LaunchConstants.Launcher.pageDotHeight)
        }
    }
}

struct LauncherItemView: View {
    let item: LauncherItem
    @ObservedObject var state: AppState
    @ObservedObject var iconCache: IconCache
    var folderNamespace: Namespace.ID

    var body: some View {
        switch item {
        case .app(let app):
            AppIcon(app: app, state: state, iconCache: iconCache)
        case .folder(let folder, let apps):
            FolderIcon(folder: folder, apps: apps, state: state, iconCache: iconCache, namespace: folderNamespace)
        }
    }
}

struct AppIcon: View {
    let app: LaunchApp
    @ObservedObject var state: AppState
    @ObservedObject var iconCache: IconCache

    var body: some View {
        Button {
            state.launch(app)
        } label: {
            VStack(spacing: LaunchConstants.Icon.spacing) {
                Image(nsImage: iconCache.icon(for: app))
                    .resizable()
                    .frame(width: LaunchConstants.Icon.imageSize, height: LaunchConstants.Icon.imageSize)
                    .shadow(color: .black.opacity(0.38), radius: 2, y: 1)

                Text(app.name)
                    .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: LaunchConstants.Icon.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
                    .launchLabelStyle()
            }
            .opacity(state.draggedAppID == app.id ? LaunchConstants.Icon.draggedOpacity : 1)
        }
        .buttonStyle(.plain)
        .onDrag {
            state.draggedAppID = app.id
            return NSItemProvider(object: app.id as NSString)
        }
        .onDrop(of: [UTType.text], delegate: AppDropDelegate(targetID: app.id, state: state))
    }
}

struct FolderIcon: View {
    let folder: LaunchFolder
    let apps: [LaunchApp]
    @ObservedObject var state: AppState
    @ObservedObject var iconCache: IconCache
    var namespace: Namespace.ID

    var body: some View {
        Button {
            state.openFolder = folder
        } label: {
            VStack(spacing: LaunchConstants.Icon.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: LaunchConstants.Icon.folderCornerRadius)
                        .fill(.clear)
                        .frame(width: LaunchConstants.Icon.imageSize, height: LaunchConstants.Icon.imageSize)
                        .launchGlass(
                            in: RoundedRectangle(cornerRadius: LaunchConstants.Icon.folderCornerRadius),
                            interactive: true
                        )

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(LaunchConstants.Icon.miniGridItemWidth), spacing: 0),
                            count: LaunchConstants.Icon.folderPreviewColumns
                        ),
                        spacing: 0
                    ) {
                        ForEach(apps.prefix(LaunchConstants.Icon.folderPreviewLimit)) { app in
                            Image(nsImage: iconCache.icon(for: app))
                                .resizable()
                                .frame(width: LaunchConstants.Icon.miniImageSize, height: LaunchConstants.Icon.miniImageSize)
                        }
                    }
                }
                .modifier(FolderGlassIDModifier(folderID: folder.id, namespace: namespace, isOpen: state.openFolder?.id == folder.id))

                Text(folder.name)
                    .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .regular))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: LaunchConstants.Icon.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
                    .launchLabelStyle()
            }
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.text], delegate: FolderDropDelegate(targetID: folder.id, state: state))
    }
}

private struct FolderGlassIDModifier: ViewModifier {
    let folderID: String
    let namespace: Namespace.ID
    let isOpen: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffectID(isOpen ? "open-\(folderID)" : folderID, in: namespace)
        } else {
            content
        }
    }
}

struct FolderOverlay: View {
    let folder: LaunchFolder
    @ObservedObject var state: AppState
    @StateObject private var iconCache = IconCache()
    var namespace: Namespace.ID

    private let columns = Array(
        repeating: GridItem(.fixed(LaunchConstants.FolderOverlay.gridItemWidth), spacing: LaunchConstants.FolderOverlay.gridSpacing),
        count: LaunchConstants.FolderOverlay.columns
    )

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                folderContent
                    .launchGlass(in: RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius), interactive: false)
                    .glassEffectID("open-\(folder.id)", in: namespace)
            }
        } else {
            folderContent
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius))
        }
    }

    private var folderContent: some View {
        VStack(spacing: LaunchConstants.FolderOverlay.spacing) {
            Text(folder.name)
                .font(.system(size: LaunchConstants.FolderOverlay.titleFontSize, weight: .semibold))
                .launchLabelStyle()

            LazyVGrid(columns: columns, spacing: LaunchConstants.FolderOverlay.spacing) {
                ForEach(state.apps(in: folder)) { app in
                    AppIcon(app: app, state: state, iconCache: iconCache)
                }
            }
            .frame(minHeight: LaunchConstants.FolderOverlay.minGridHeight, alignment: .top)
        }
        .padding(LaunchConstants.FolderOverlay.padding)
        .frame(width: LaunchConstants.FolderOverlay.width)
    }
}
