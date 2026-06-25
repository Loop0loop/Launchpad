import LaunchpadCore
import SwiftUI

struct FolderOverlay: View {
    let folder: LaunchFolder
    @ObservedObject var state: AppState
    let availableWidth: CGFloat
    @State private var folderName = ""

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.fixed(LaunchConstants.FolderOverlay.gridItemWidth), spacing: LaunchConstants.FolderOverlay.gridSpacing),
            count: LaunchConstants.FolderOverlay.columns
        )
    }

    var body: some View {
        // Open/close is animated by the parent `.transition` + `.animation(value: openFolder)`.
        folderContent
            .onAppear { folderName = folder.name }
            .onChange(of: folder.id) { _, _ in folderName = folder.name }
            .onChange(of: folder.name) { _, name in folderName = name }
    }

    @ViewBuilder
    private var folderContent: some View {
        folderPanel
            .background(panelSurface.opacity(state.folderDragPullingOut ? 0 : 1))
            .animation(LaunchConstants.Animation.fade, value: state.folderDragPullingOut)
            .tahoeFolderPanelChrome()
    }

    private var panelSurface: some View {
        let shape = RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius, style: .continuous)
        return shape
            .fill(.white.opacity(LaunchConstants.Glass.folderBackgroundOpacity))
            .launchGlass(in: shape, interactive: false, clear: true)
            .overlay(shape.strokeBorder(.white.opacity(LaunchConstants.Glass.folderStrokeOpacity), lineWidth: 1.0))
    }

    /// Panel hugs its content (columns × item width) instead of a fixed share of the
    /// screen. The parent ZStack centers it, so the grid reads edge-to-edge with no dead
    /// space — no widthRatio/min/max magic to tune.
    private var panelWidth: CGFloat {
        let cols = CGFloat(LaunchConstants.FolderOverlay.columns)
        let content = cols * LaunchConstants.FolderOverlay.gridItemWidth
            + max(0, cols - 1) * LaunchConstants.FolderOverlay.gridSpacing
        return content + LaunchConstants.FolderOverlay.horizontalPadding * 2
    }

    private var folderPanel: some View {
        VStack(spacing: LaunchConstants.FolderOverlay.spacing) {
            FolderTitleField(name: $folderName, width: panelWidth - LaunchConstants.FolderOverlay.horizontalPadding * 2) {
                state.renameFolder(folder.id, to: folderName)
            }
            .opacity(state.folderDragPullingOut ? 0 : 1)

            LazyVGrid(columns: columns, spacing: LaunchConstants.FolderOverlay.spacing) {
                // 재배열 중에는 옮긴 순서로 렌더해 다른 아이콘이 실시간으로 비켜난다(라이브 reflow).
                ForEach(state.folderRenderApps(folder)) { app in
                    FolderOverlayAppIcon(app: app, folderID: folder.id, state: state)
                }
            }
            .frame(maxWidth: .infinity, minHeight: LaunchConstants.FolderOverlay.minGridHeight, alignment: .topLeading)
            .coordinateSpace(name: "folderGrid")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.folderGridFrame = $0 }
            .animation(LaunchConstants.Animation.iconLift, value: state.folderDragInsertionIndex)
            .animation(LaunchConstants.Animation.iconLift, value: folder.appIDs)
        }
        .padding(.horizontal, LaunchConstants.FolderOverlay.horizontalPadding)
        .padding(.vertical, LaunchConstants.FolderOverlay.verticalPadding)
        .frame(width: panelWidth)
        // contentShape absorbs taps on the panel (so inner clicks don't close the folder)
        // without an empty onTapGesture that would steal the title field's focus tap.
        .contentShape(
            RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius, style: .continuous)
        )
    }
}

struct FolderTitleField: View {
    @Binding var name: String
    let width: CGFloat
    let commit: () -> Void

    var body: some View {
        // AppKit-backed: a SwiftUI TextField in a nonactivating NSPanel never gets the field
        // editor (no keyboard). This field makes the panel key on click, like the search bar.
        FolderTitleNSField(name: $name, commit: commit)
            .frame(height: LaunchConstants.FolderOverlay.titleFontSize + 14)
            .frame(width: width)
    }
}

private struct FolderTitleNSField: NSViewRepresentable {
    @Binding var name: String
    let commit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FolderTitleNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.isAutomaticTextCompletionEnabled = false
        field.allowsCharacterPickerTouchBarItem = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .systemFont(ofSize: LaunchConstants.FolderOverlay.titleFontSize, weight: .semibold)
        field.textColor = .white
        field.cell?.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commitFromAction(_:))
        field.stringValue = name
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Don't clobber text mid-edit (would jump the cursor).
        if field.currentEditor() == nil, field.stringValue != name {
            field.stringValue = name
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: FolderTitleNSField
        init(_ parent: FolderTitleNSField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.name = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.commit()
        }

        @MainActor @objc func commitFromAction(_ sender: NSTextField) {
            parent.name = sender.stringValue
            parent.commit()
        }
    }
}

final class FolderTitleNSTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch key {
        case "a":
            if let editor = currentEditor() {
                editor.selectAll(nil)
            } else {
                selectText(nil)
            }
            return true
        case "c":
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "x":
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "z":
            if event.modifierFlags.contains(.shift) {
                currentEditor()?.undoManager?.redo()
            } else {
                currentEditor()?.undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

struct FolderOverlayAppIcon: View {
    let app: LaunchApp
    let folderID: String
    @ObservedObject var state: AppState
    @State private var dragOffset: CGSize = .zero
    @State private var dragPointer: CGPoint?
    @State private var isLaunching = false
    @GestureState private var isDragActive = false

    /// True while this icon is being dragged to reorder within the panel.
    private var isReordering: Bool {
        state.folderReorderingID == app.id && !state.folderDragPullingOut
    }

    private var isPullingOut: Bool {
        state.folderDragPullingOut && dragOffset != .zero
    }

    /// Cell center (folderGrid space) for slot `index`, matching GridGeometry.cellIndex binning.
    private func cellCenter(_ index: Int) -> CGPoint {
        let f = LaunchConstants.FolderOverlay.self
        let col = index % f.columns
        let row = index / f.columns
        return CGPoint(
            x: CGFloat(col) * f.colPitch + f.gridItemWidth / 2,
            y: CGFloat(row) * f.rowPitch + f.maxIconSize / 2
        )
    }

    /// Offset that floats the reorder copy under the pointer, independent of which cell the
    /// gap reflows to (same trick as the main grid's draggedCellCenter/floatOffset).
    private var reorderFloatOffset: CGSize {
        guard let pointer = dragPointer, let index = state.folderDragInsertionIndex else { return .zero }
        let center = cellCenter(index)
        return CGSize(width: pointer.x - center.x, height: pointer.y - center.y)
    }

    private func slotIndex(at location: CGPoint) -> Int {
        let count = state.folders.first { $0.id == folderID }?.appIDs.count ?? 0
        return GridGeometry.cellIndex(
            x: Double(location.x),
            y: Double(location.y),
            columns: LaunchConstants.FolderOverlay.columns,
            colPitch: Double(LaunchConstants.FolderOverlay.colPitch),
            rowPitch: Double(LaunchConstants.FolderOverlay.rowPitch),
            count: count
        )
    }

    private func isInsideFolderGrid(_ location: CGPoint) -> Bool {
        let size = state.folderGridFrame.size
        guard size.width > 0, size.height > 0 else { return true }
        let slop = LaunchConstants.FolderOverlay.pullOutSlop
        return location.x >= -slop && location.y >= -slop && location.x <= size.width + slop && location.y <= size.height + slop
    }

    private var iconView: some View {
        VStack(spacing: LaunchConstants.Icon.spacing) {
            LoadedIcon(app: app, displaySize: LaunchConstants.FolderOverlay.maxIconSize, loadsImage: state.launcherVisible)
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)

            Text(app.name)
                .font(.system(size: LaunchConstants.Icon.labelFontSize, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: LaunchConstants.FolderOverlay.labelWidth, height: LaunchConstants.Icon.labelHeight, alignment: .top)
                .launchLabelStyle()
        }
        .frame(width: LaunchConstants.FolderOverlay.gridItemWidth)
        .contentShape(Rectangle())
    }

    var body: some View {
        iconView
            // Reorder: the in-place cell is an invisible gap; a copy floats under the pointer.
            .offset(isPullingOut ? dragOffset : .zero)
            .scaleEffect(isLaunching ? 1.16 : 1)
            .scaleEffect(isPullingOut ? 1.12 : 1)
            .opacity(isLaunching ? 0 : (isReordering || (state.folderDragPullingOut && !isPullingOut) ? 0 : 1))
            .overlay {
                if isReordering {
                    iconView
                        .scaleEffect(1.12)
                        .offset(reorderFloatOffset)
                }
            }
            .zIndex(isReordering || isPullingOut || isLaunching ? 100 : 0)
            .onTapGesture {
                withAnimation(LaunchConstants.Animation.quick) {
                    isLaunching = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    state.launch(app)
                }
            }
            .onLongPressGesture(minimumDuration: 0.8) {
                LaunchLog.line("FolderOverlayAppIcon long press app=\(app.id) -> prompting delete")
                state.moveToTrash(app)
            }
            // Inside the folder grid: reorder. Outside it: pull the app back to the root grid.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .named("folderGrid"))
                    .updating($isDragActive) { _, dragActiveState, _ in
                        dragActiveState = true
                    }
                    .onChanged { value in
                        if isInsideFolderGrid(value.location) {
                            state.folderDragPullingOut = false
                            dragOffset = .zero
                            dragPointer = value.location
                            state.updateFolderReorder(app.id, toIndex: slotIndex(at: value.location))
                        } else {
                            state.endFolderReorder()
                            state.folderDragPullingOut = true
                            dragOffset = value.translation
                            dragPointer = nil
                        }
                    }
                    .onEnded { value in
                        if isInsideFolderGrid(value.location) {
                            let index = state.folderDragInsertionIndex ?? slotIndex(at: value.location)
                            state.reorderAppInFolder(app.id, toIndex: index, folderID: folderID)
                        } else {
                            LaunchLog.line("folder pull-out app=\(app.id) folder=\(folderID)")
                            state.removeApp(app.id, fromFolder: folderID)
                            state.closeFolder()
                            state.revealItem(app.id)
                        }
                        state.folderDragPullingOut = false
                        state.endFolderReorder()
                        dragPointer = nil
                        withAnimation(LaunchConstants.Animation.iconLift) { dragOffset = .zero }
                    }
            )
            .onChange(of: isDragActive) { oldValue, newValue in
                if oldValue && !newValue {
                    state.folderDragPullingOut = false
                    state.endFolderReorder()
                    dragPointer = nil
                    withAnimation(LaunchConstants.Animation.iconLift) { dragOffset = .zero }
                }
            }
            .onDisappear {
                state.folderDragPullingOut = false
                state.endFolderReorder()
            }
            .contextMenu {
                launcherAppContextMenu(app: app, state: state)
                Divider()
                Button(LaunchConstants.Menu.removeFromFolder) {
                    state.removeApp(app.id, fromFolder: folderID)
                }
            }
    }
}
