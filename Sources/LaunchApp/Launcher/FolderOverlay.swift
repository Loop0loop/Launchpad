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
        // Surface (glass/stroke) and title fade out while pulling an app out, so the folder
        // visibly dissolves and only the dragged icon remains. No clipShape: the dragged icon
        // must stay visible as it crosses the panel edge.
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
                ForEach(state.apps(in: folder)) { app in
                    FolderOverlayAppIcon(app: app, folderID: folder.id, state: state)
                }
            }
            .frame(maxWidth: .infinity, minHeight: LaunchConstants.FolderOverlay.minGridHeight, alignment: .topLeading)
            .coordinateSpace(name: "folderGrid")
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

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKey()
        window?.makeFirstResponder(self)
        selectText(nil)
        super.mouseDown(with: event)
    }
}

struct FolderOverlayAppIcon: View {
    let app: LaunchApp
    let folderID: String
    @ObservedObject var state: AppState
    @State private var dragOffset: CGSize = .zero
    @GestureState private var isDragActive = false

    /// Drag distance past which releasing pulls the app out of the folder.
    private static let pullOutThreshold: CGFloat = 100

    var body: some View {
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
        // Other icons fade while one is pulled out; the dragged one stays in hand.
        .opacity(state.folderDragPullingOut && dragOffset == .zero ? 0 : 1)
        .offset(dragOffset)
        .scaleEffect(dragOffset == .zero ? 1 : 1.12)
        .zIndex(dragOffset == .zero ? 0 : 100)
        .onTapGesture {
            state.launch(app)
        }
        .onLongPressGesture(minimumDuration: 0.8) {
            LaunchLog.line("FolderOverlayAppIcon long press app=\(app.id) -> prompting delete")
            state.moveToTrash(app)
        }
        // Drag within the panel reorders; drag far enough out pulls the app back to the grid.
        .simultaneousGesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("folderGrid"))
                .updating($isDragActive) { _, dragActiveState, _ in
                    dragActiveState = true
                }
                .onChanged { value in
                    dragOffset = value.translation
                    // Past the threshold the folder dissolves so the app is "in hand".
                    state.folderDragPullingOut = hypot(value.translation.width, value.translation.height) > Self.pullOutThreshold
                }
                .onEnded { value in
                    let pulledOut = hypot(value.translation.width, value.translation.height) > Self.pullOutThreshold
                    state.folderDragPullingOut = false
                    if pulledOut {
                        LaunchLog.line("folder pull-out app=\(app.id) folder=\(folderID)")
                        state.removeApp(app.id, fromFolder: folderID)
                        // Close + page to the app so it's visibly dropped back on the grid.
                        state.closeFolder()
                        state.revealItem(app.id)
                    } else {
                        // Stayed in the panel: drop maps to a slot and reorders.
                        let count = state.folders.first { $0.id == folderID }?.appIDs.count ?? 0
                        let index = GridGeometry.cellIndex(
                            x: Double(value.location.x),
                            y: Double(value.location.y),
                            columns: LaunchConstants.FolderOverlay.columns,
                            colPitch: Double(LaunchConstants.FolderOverlay.colPitch),
                            rowPitch: Double(LaunchConstants.FolderOverlay.rowPitch),
                            count: count
                        )
                        state.reorderAppInFolder(app.id, toIndex: index, folderID: folderID)
                    }
                    withAnimation(LaunchConstants.Animation.iconLift) { dragOffset = .zero }
                }
        )
        .onChange(of: isDragActive) { oldValue, newValue in
            if oldValue && !newValue {
                state.folderDragPullingOut = false
                withAnimation(LaunchConstants.Animation.iconLift) { dragOffset = .zero }
            }
        }
        .onDisappear {
            state.folderDragPullingOut = false
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
