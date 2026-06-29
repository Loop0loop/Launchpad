import LaunchpadCore
import SwiftUI

struct LauncherItemView: View {
    let item: LauncherItem
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat
    var loadsIcons = true

    var body: some View {
        let shouldLoadIcons = loadsIcons && state.launcherVisible
        switch item {
        case .app(let app):
            AppIcon(app: app, state: state, layout: layout, pageOffset: pageOffset, loadsIcon: shouldLoadIcons)
        case .folder(let folder, let apps):
            FolderIcon(folder: folder, apps: apps, state: state, layout: layout, pageOffset: pageOffset, loadsIcons: shouldLoadIcons)
        }
    }
}

struct AppIcon: View {
    let app: LaunchApp
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat
    let loadsIcon: Bool

    var body: some View {
        let isLanding = state.folderPullOutLandingID == app.id
        VStack(spacing: LaunchConstants.Icon.spacing) {
            LoadedIcon(app: app, displaySize: layout.iconSize, loadsImage: loadsIcon)
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)

            Text(app.name)
                .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: layout.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
                .launchLabelStyle()
        }
        .frame(width: max(layout.iconSize, layout.labelWidth))
        .overlay(alignment: .topLeading) {
            if state.isEditingLayout, state.canMoveToTrash(app) {
                DeleteBadge {
                    state.suppressPageControlTap()
                    state.moveToTrash(app)
                }
                .offset(x: 2, y: -8)
            }
        }
        .contentShape(Rectangle())
        .frame(width: layout.columnWidth)
        .editingJiggle(active: state.isEditingLayout, id: app.id)
        .scaleEffect(isLanding ? LaunchConstants.Launcher.folderPullOutLandingScale : 1)
        .overlay(keyboardSelectionBackground(isSelected: state.query.isEmpty && state.showsKeyboardSelection(for: app.id)))
        .animation(LaunchConstants.Animation.iconLift, value: isLanding)
        .launcherTap(enabled: !state.isEditingLayout) {
            state.suppressPageControlTap()
            state.launch(app)
        }
        .editModePress { state.startEditingLayout() }
        .launcherDrag(id: app.id, state: state, layout: layout, pageOffset: pageOffset)
        .zIndex(state.isEditingLayout ? 5 : 0)
        .contextMenu {
            launcherAppContextMenu(app: app, state: state)
        }
    }
}

struct FolderIcon: View {
    let folder: LaunchFolder
    let apps: [LaunchApp]
    @ObservedObject var state: AppState
    let layout: LaunchpadLayoutMetrics
    let pageOffset: CGFloat
    let loadsIcons: Bool

    private var miniIconSize: CGFloat {
        layout.iconSize * LaunchConstants.Icon.folderPreviewScale
    }

    private var miniGap: CGFloat {
        layout.iconSize * LaunchConstants.Icon.folderPreviewGapRatio
    }

    var body: some View {
        let isNewFolder = state.folderCreationAnimationID == folder.id
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
                        LoadedIcon(
                            app: app,
                            displaySize: miniIconSize,
                            loadSize: miniIconSize,
                            loadsImage: loadsIcons,
                            cachesImageInMemory: false
                        )
                    }
                }

                if apps.count > LaunchConstants.Icon.folderPreviewLimit {
                    Text("+\(apps.count - LaunchConstants.Icon.folderPreviewLimit)")
                        .font(.system(size: max(10, layout.iconSize * 0.13), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.42), in: Capsule())
                        .frame(width: layout.iconSize, height: layout.iconSize, alignment: .bottomTrailing)
                        .padding(layout.iconSize * 0.08)
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
        .scaleEffect(isNewFolder ? LaunchConstants.Launcher.folderCreationScale : 1)
        .overlay(keyboardSelectionBackground(isSelected: state.query.isEmpty && state.showsKeyboardSelection(for: folder.id)))
        .animation(LaunchConstants.Animation.folder, value: isNewFolder)
        .launcherTap(enabled: !state.isEditingLayout) {
            state.suppressPageControlTap()
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

private struct DeleteBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.24), .black.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.38), radius: 1, y: 0.5)
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
            .buttonStyle(.plain)
            .frame(width: 34, height: 34)
            .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
            .accessibilityLabel(Text(LaunchConstants.Menu.moveToTrash))
    }
}

private struct EditingJiggleModifier: ViewModifier {
    let active: Bool
    let id: String

    private var phase: Double {
        Double(id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 })
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = active ? sin(t * 15.0 + phase) * 0.85 : 0
            content.rotationEffect(.degrees(angle))
        }
    }
}

private extension View {
    func editingJiggle(active: Bool, id: String) -> some View {
        modifier(EditingJiggleModifier(active: active, id: id))
    }

    func editModePress(action: @escaping () -> Void) -> some View {
        simultaneousGesture(
            LongPressGesture(minimumDuration: LaunchConstants.Launcher.editModeLongPress, maximumDistance: 18)
                .onEnded { _ in
                    LaunchLog.line("AppIcon long press -> edit mode")
                    action()
                }
        )
    }

    @ViewBuilder
    func launcherTap(enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            highPriorityGesture(TapGesture().onEnded(action))
        } else {
            self
        }
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
        let draggedCenter = isDragging ? state.draggedCellCenter(layout: layout) : nil
        let floatOffset = draggedCenter.map {
            CGSize(width: drag.location.x - $0.x, height: drag.location.y - $0.y)
        } ?? .zero

        return Group {
            if isDragging {
                ZStack {
                    content.opacity(0)
                    if draggedCenter != nil {
                        content
                            .scaleEffect(1.1)
                            .opacity(drag.hoverTargetID == nil ? 0.95 : 0.55)
                            .offset(floatOffset)
                    }
                }
            } else {
                content
                    .scaleEffect(isMergeTarget ? 1.04 : 1)
                    .brightness(isMergeTarget ? 0.04 : 0)
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
                        let startLocation = pageLocal(value.startLocation)
                        let location = pageLocal(value.location)
                        if state.draggingItemID == nil {
                            state.beginItemDrag(id, at: startLocation, layout: layout)
                        }
                        let iconCenter = state.drag.iconCenter(for: location)
                        let resolved = state.dropResolution(at: iconCenter, layout: layout)
                        state.updateItemDrag(pointerLocation: location, translation: value.translation, resolution: resolved)
                    }
                    .onEnded { value in
                        let iconCenter = state.drag.iconCenter(for: pageLocal(value.location))
                        let resolved = state.dropResolution(at: iconCenter, layout: layout)
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

    private func pageLocal(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - pageOffset, y: point.y)
    }
}

extension View {
    func launcherDrag(id: String, state: AppState, layout: LaunchpadLayoutMetrics, pageOffset: CGFloat) -> some View {
        modifier(LauncherDragModifier(id: id, state: state, layout: layout, pageOffset: pageOffset))
    }
}
