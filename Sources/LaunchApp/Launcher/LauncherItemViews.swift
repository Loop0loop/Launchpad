import LaunchCore
import SwiftUI

struct LauncherItemView: View {
    let item: LauncherItem
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat

    var body: some View {
        switch item {
        case .app(let app):
            AppIcon(app: app, state: state, layout: layout, pageOffset: pageOffset)
        case .folder(let folder, let apps):
            FolderIcon(folder: folder, apps: apps, state: state, layout: layout, pageOffset: pageOffset)
        }
    }
}

struct AppIcon: View {
    let app: LaunchApp
    @ObservedObject var state: AppState
    @Environment(\.iconCache) private var iconCache
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat

    var body: some View {
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
        .frame(width: max(layout.iconSize, layout.labelWidth))
        .contentShape(Rectangle())
        .frame(width: layout.columnWidth)
        .overlay(keyboardSelectionBackground(isSelected: state.query.isEmpty && state.showsKeyboardSelection(for: app.id)))
        .onTapGesture {
            state.launch(app)
        }
        .launcherDrag(id: app.id, state: state, layout: layout, pageOffset: pageOffset)
        .contextMenu {
            launcherAppContextMenu(app: app, state: state)
        }
    }
}

struct FolderIcon: View {
    let folder: LaunchFolder
    let apps: [LaunchApp]
    @ObservedObject var state: AppState
    @Environment(\.iconCache) private var iconCache
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat

    private var miniIconSize: CGFloat {
        layout.iconSize * LaunchConstants.Icon.folderPreviewScale
    }

    var body: some View {
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
        .frame(width: max(layout.iconSize, layout.labelWidth))
        .contentShape(Rectangle())
        .frame(width: layout.columnWidth)
        .overlay(keyboardSelectionBackground(isSelected: state.query.isEmpty && state.showsKeyboardSelection(for: folder.id)))
        .onTapGesture {
            state.openFolderFromTap(folder)
        }
        .launcherDrag(id: folder.id, state: state, layout: layout, pageOffset: pageOffset)
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

@ViewBuilder
private func keyboardSelectionBackground(isSelected: Bool) -> some View {
    if isSelected {
        RoundedRectangle(cornerRadius: LaunchConstants.Icon.folderCornerRadius)
            .strokeBorder(.white.opacity(0.45), lineWidth: 1.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
    }
}

/// Applies the lift/follow visual + drag gesture to a grid icon. The grid container must
/// declare `.coordinateSpace(name: "launcherGrid")`.
struct LauncherDragModifier: ViewModifier {
    let id: String
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat

    @GestureState private var isDragActive = false

    func body(content: Content) -> some View {
        let isDragging = state.draggingItemID == id
        let isMergeTarget = state.dragHoverTargetID == id
        
        let translation = isDragging ? CGSize(
            width: state.dragTranslation.width - pageOffset,
            height: state.dragTranslation.height
        ) : .zero

        return content
            .scaleEffect(isDragging ? 1.12 : (isMergeTarget ? 1.16 : 1))
            .opacity(isDragging ? LaunchConstants.Icon.draggedOpacity : 1)
            .offset(translation)
            .zIndex(isDragging ? 100 : 0)
            .animation(LaunchConstants.Animation.quick, value: isMergeTarget)
            .animation(isDragging ? nil : LaunchConstants.Animation.spring, value: isDragging)
            .animation(isDragging ? nil : LaunchConstants.Animation.spring, value: state.dragTranslation)
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named("launcherGrid"))
                    .updating($isDragActive) { _, dragActiveState, _ in
                        dragActiveState = true
                    }
                    .onChanged { value in
                        if state.draggingItemID == nil { state.beginItemDrag(id) }
                        let resolved = state.dropResolution(at: value.location, layout: layout)
                        state.updateItemDrag(translation: value.translation, hoveredID: resolved.onIconID)
                    }
                    .onEnded { value in
                        let resolved = state.dropResolution(at: value.location, layout: layout)
                        state.endItemDrag(onIconID: resolved.onIconID, slotID: resolved.slotID, targetIndex: resolved.targetIndex)
                    }
            )
            .onChange(of: isDragActive) { oldValue, newValue in
                if oldValue && !newValue {
                    if state.draggingItemID == id {
                        LaunchLog.line("Drag gesture cancelled/interrupted for \(id)")
                        state.cancelDrag()
                    }
                }
            }
    }
}

extension View {
    func launcherDrag(id: String, state: AppState, layout: LaunchpadLayoutMetrics, pageOffset: CGFloat) -> some View {
        modifier(LauncherDragModifier(id: id, state: state, layout: layout, pageOffset: pageOffset))
    }
}
