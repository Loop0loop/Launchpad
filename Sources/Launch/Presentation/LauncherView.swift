import LaunchCore
import SwiftUI
import UniformTypeIdentifiers

struct LauncherView: View {
    @ObservedObject var state: AppState
    @StateObject private var iconCache = IconCache()

    private let columns = Array(repeating: GridItem(.fixed(112), spacing: 18), count: 7)

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Color.black.opacity(0.22).ignoresSafeArea()

            VStack(spacing: 34) {
                TextField("Search Applications", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 18)
                    .frame(width: 420, height: 44)
                    .background(.ultraThinMaterial, in: Capsule())

                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(state.pageItems) { item in
                        LauncherItemView(item: item, state: state, iconCache: iconCache)
                    }
                }
                .frame(height: 620, alignment: .top)
                .id(state.currentPage)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .animation(.easeOut(duration: 0.16), value: state.currentPage)

                HStack(spacing: 8) {
                    ForEach(0..<state.pageCount, id: \.self) { page in
                        Circle()
                            .fill(page == state.currentPage ? .white : .white.opacity(0.35))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(height: 14)
            }
            .padding(.top, 70)
            .opacity(state.launcherVisible ? 1 : 0)
            .scaleEffect(state.launcherVisible ? 1 : 0.96)
            .animation(.easeOut(duration: 0.18), value: state.launcherVisible)

            if let folder = state.openFolder {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { state.closeFolder() }

                FolderOverlay(folder: folder, state: state)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    if value.translation.width < -60 {
                        state.changePage(1)
                    } else if value.translation.width > 60 {
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
        .animation(.easeOut(duration: 0.18), value: state.openFolder?.id)
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
            VStack(spacing: 8) {
                Image(nsImage: iconCache.icon(for: app))
                    .resizable()
                    .frame(width: 72, height: 72)
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 104, height: 34, alignment: .top)
            }
            .foregroundStyle(.white)
            .opacity(state.draggedAppID == app.id ? 0.35 : 1)
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
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .frame(width: 72, height: 72)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 0), count: 2), spacing: 0) {
                        ForEach(apps.prefix(4)) { app in
                            Image(nsImage: iconCache.icon(for: app))
                                .resizable()
                                .frame(width: 22, height: 22)
                        }
                    }
                }
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 104, height: 34, alignment: .top)
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

    private let columns = Array(repeating: GridItem(.fixed(112), spacing: 18), count: 4)

    var body: some View {
        VStack(spacing: 22) {
            Text(folder.name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(state.apps(in: folder)) { app in
                    AppIcon(app: app, state: state, iconCache: iconCache)
                }
            }
            .frame(minHeight: 150, alignment: .top)
        }
        .padding(30)
        .frame(width: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}
