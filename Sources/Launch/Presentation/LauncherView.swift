import LaunchCore
import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    @ObservedObject var state: AppState
    @StateObject private var iconCache = IconCache()

    private let columns = Array(
        repeating: GridItem(.fixed(LaunchConstants.Launcher.gridItemWidth), spacing: LaunchConstants.Launcher.gridSpacing),
        count: LaunchConstants.Launcher.columns
    )

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Color.black.opacity(LaunchConstants.Launcher.backgroundOpacity).ignoresSafeArea()

            VStack(spacing: LaunchConstants.Launcher.verticalSpacing) {
                TextField(LaunchConstants.Launcher.searchPlaceholder, text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: LaunchConstants.Launcher.searchFontSize, weight: .medium))
                    .padding(.horizontal, LaunchConstants.Launcher.searchHorizontalPadding)
                    .frame(width: LaunchConstants.Launcher.searchWidth, height: LaunchConstants.Launcher.searchHeight)
                    .background(.ultraThinMaterial, in: Capsule())

                LazyVGrid(columns: columns, spacing: LaunchConstants.Launcher.gridRowSpacing) {
                    ForEach(state.pageItems) { item in
                        LauncherItemView(item: item, state: state, iconCache: iconCache)
                    }
                }
                .frame(height: LaunchConstants.Launcher.gridHeight, alignment: .top)
                .id(state.currentPage)
                .transition(.opacity.combined(with: .scale(scale: LaunchConstants.Launcher.pageTransitionScale)))
                .animation(.easeOut(duration: LaunchConstants.Launcher.pageAnimationDuration), value: state.currentPage)

                HStack(spacing: LaunchConstants.Launcher.pageDotSpacing) {
                    ForEach(0..<state.pageCount, id: \.self) { page in
                        Circle()
                            .fill(page == state.currentPage ? .white : .white.opacity(LaunchConstants.Launcher.inactivePageOpacity))
                            .frame(width: LaunchConstants.Launcher.pageDotSize, height: LaunchConstants.Launcher.pageDotSize)
                    }
                }
                .frame(height: LaunchConstants.Launcher.pageDotHeight)
            }
            .padding(.top, LaunchConstants.Launcher.topPadding)
            .opacity(state.launcherVisible ? 1 : 0)
            .scaleEffect(state.launcherVisible ? 1 : LaunchConstants.Launcher.contentHiddenScale)
            .animation(.easeOut(duration: LaunchConstants.Launcher.contentAnimationDuration), value: state.launcherVisible)

            if let folder = state.openFolder {
                Color.black.opacity(LaunchConstants.Launcher.overlayOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { state.closeFolder() }

                FolderOverlay(folder: folder, state: state)
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
        .animation(.easeOut(duration: LaunchConstants.Launcher.contentAnimationDuration), value: state.openFolder?.id)
    }
}

struct LauncherItemView: View {
    let item: LauncherItem
    @ObservedObject var state: AppState
    @ObservedObject var iconCache: IconCache

    var body: some View {
        switch item {
        case .app(let app):
            AppIcon(app: app, state: state, iconCache: iconCache)
        case .folder(let folder, let apps):
            FolderIcon(folder: folder, apps: apps, state: state, iconCache: iconCache)
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
                Text(app.name)
                    .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: LaunchConstants.Icon.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
            }
            .foregroundStyle(.white)
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

    var body: some View {
        Button {
            state.openFolder = folder
        } label: {
            VStack(spacing: LaunchConstants.Icon.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: LaunchConstants.Icon.folderCornerRadius)
                        .fill(.ultraThinMaterial)
                        .frame(width: LaunchConstants.Icon.imageSize, height: LaunchConstants.Icon.imageSize)
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
                Text(folder.name)
                    .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: LaunchConstants.Icon.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.text], delegate: FolderDropDelegate(targetID: folder.id, state: state))
    }
}

struct FolderOverlay: View {
    let folder: LaunchFolder
    @ObservedObject var state: AppState
    @StateObject private var iconCache = IconCache()

    private let columns = Array(
        repeating: GridItem(.fixed(LaunchConstants.FolderOverlay.gridItemWidth), spacing: LaunchConstants.FolderOverlay.gridSpacing),
        count: LaunchConstants.FolderOverlay.columns
    )

    var body: some View {
        VStack(spacing: LaunchConstants.FolderOverlay.spacing) {
            Text(folder.name)
                .font(.system(size: LaunchConstants.FolderOverlay.titleFontSize, weight: .semibold))
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: LaunchConstants.FolderOverlay.spacing) {
                ForEach(state.apps(in: folder)) { app in
                    AppIcon(app: app, state: state, iconCache: iconCache)
                }
            }
            .frame(minHeight: LaunchConstants.FolderOverlay.minGridHeight, alignment: .top)
        }
        .padding(LaunchConstants.FolderOverlay.padding)
        .frame(width: LaunchConstants.FolderOverlay.width)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius))
    }
}
