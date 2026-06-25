import LaunchpadCore
import SwiftUI

struct LauncherItemView: View {
    let item: LauncherItem
    let state: AppState
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
    let state: AppState
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat

    var body: some View {
        VStack(spacing: LaunchConstants.Icon.spacing) {
            LoadedIcon(app: app, displaySize: layout.iconSize)
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
        .onLongPressGesture(minimumDuration: 0.8) {
            LaunchLog.line("AppIcon long press app=\(app.id) -> prompting delete")
            state.moveToTrash(app)
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
    let state: AppState
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat

    private var miniIconSize: CGFloat {
        layout.iconSize * LaunchConstants.Icon.folderPreviewScale
    }

    private var miniGap: CGFloat {
        layout.iconSize * LaunchConstants.Icon.folderPreviewGapRatio
    }

    var body: some View {
        VStack(spacing: LaunchConstants.Icon.spacing) {
            ZStack {
                // `.clear` 글래스 타일 — 안은 투명, 배경이 비침. 미니 아이콘은 그 위에
                // 3×3 으로 띄운다(네이티브 Launchpad 폴더 정석).
                Color.clear
                    .frame(width: layout.iconSize, height: layout.iconSize)
                    .launchpadFolderChrome(cornerRadius: LaunchConstants.Icon.folderCornerRadius)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(miniIconSize), spacing: miniGap),
                        count: LaunchConstants.Icon.folderPreviewColumns
                    ),
                    spacing: miniGap
                ) {
                    ForEach(apps.prefix(LaunchConstants.Icon.folderPreviewLimit)) { app in
                        LoadedIcon(app: app, displaySize: miniIconSize, loadSize: layout.iconSize)
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
    let state: AppState
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat

    @EnvironmentObject private var drag: DragModel
    @GestureState private var isDragActive = false

    func body(content: Content) -> some View {
        let isDragging = state.draggingItemID == id
        let isMergeTarget = drag.hoverTargetID == id

        // The dragged item reserves its preview cell as a gap so the others reflow around it,
        // while a lifted copy is offset to sit under the pointer wherever the gap lands.
        let floatOffset: CGSize = {
            guard isDragging, let center = state.draggedCellCenter(layout: layout) else { return .zero }
            return CGSize(width: drag.location.x - center.x, height: drag.location.y - center.y)
        }()

        return Group {
            if isDragging {
                ZStack {
                    content.opacity(0)
                    content
                        .scaleEffect(1.1)
                        .opacity(0.95)
                        .offset(floatOffset)
                }
            } else {
                content
                    .scaleEffect(isMergeTarget ? 1.16 : 1)
                    .opacity(1)
            }
        }
        .zIndex(isDragging ? 100 : 0)
            .animation(LaunchConstants.Animation.iconLift, value: isMergeTarget)
            .animation(isDragging ? nil : LaunchConstants.Animation.iconLift, value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named("launcherGrid"))
                    .updating($isDragActive) { _, dragActiveState, _ in
                        dragActiveState = true
                    }
                    .onChanged { value in
                        if state.draggingItemID == nil { state.beginItemDrag(id) }
                        let resolved = state.dropResolution(at: value.location, layout: layout)
                        state.updateItemDrag(location: value.location, translation: value.translation, resolution: resolved)
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
