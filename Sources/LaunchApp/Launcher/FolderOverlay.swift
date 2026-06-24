import LaunchCore
import SwiftUI

struct FolderOverlay: View {
    let folder: LaunchFolder
    @ObservedObject var state: AppState
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
        let shape = RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius, style: .continuous)
        folderPanel
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                    .clipShape(shape)
            )
            .overlay(shape.fill(.white.opacity(LaunchConstants.Glass.sheenOpacity)))
            .clipShape(shape)
            .tahoeFolderPanelChrome()
    }

    private var folderPanel: some View {
        VStack(spacing: LaunchConstants.FolderOverlay.spacing) {
            FolderTitleField(name: $folderName) {
                state.renameFolder(folder.id, to: folderName)
            }

            LazyVGrid(columns: columns, spacing: LaunchConstants.FolderOverlay.spacing) {
                ForEach(state.apps(in: folder)) { app in
                    FolderOverlayAppIcon(app: app, folderID: folder.id, state: state)
                }
            }
            .frame(minHeight: LaunchConstants.FolderOverlay.minGridHeight, alignment: .top)
        }
        .padding(LaunchConstants.FolderOverlay.padding)
        .frame(width: LaunchConstants.FolderOverlay.width)
        // contentShape absorbs taps on the panel (so inner clicks don't close the folder)
        // without an empty onTapGesture that would steal the title field's focus tap.
        .contentShape(
            RoundedRectangle(cornerRadius: LaunchConstants.FolderOverlay.cornerRadius, style: .continuous)
        )
    }
}

struct FolderTitleField: View {
    @Binding var name: String
    let commit: () -> Void

    var body: some View {
        // AppKit-backed: a SwiftUI TextField in a nonactivating NSPanel never gets the field
        // editor (no keyboard). This field makes the panel key on click, like the search bar.
        FolderTitleNSField(name: $name, commit: commit)
            .frame(height: LaunchConstants.FolderOverlay.titleFontSize + 14)
            .frame(maxWidth: LaunchConstants.FolderOverlay.width - 120)
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
        field.focusRingType = .none
        field.alignment = .center
        field.font = .systemFont(ofSize: LaunchConstants.FolderOverlay.titleFontSize, weight: .semibold)
        field.textColor = .white
        field.cell?.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
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
    }
}

final class FolderTitleNSTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

struct FolderOverlayAppIcon: View {
    let app: LaunchApp
    let folderID: String
    @ObservedObject var state: AppState
    @Environment(\.iconCache) private var iconCache
    @State private var dragOffset: CGSize = .zero

    /// Drag distance past which releasing pulls the app out of the folder.
    private static let pullOutThreshold: CGFloat = 100

    var body: some View {
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
        .contentShape(Rectangle())
        .offset(dragOffset)
        .scaleEffect(dragOffset == .zero ? 1 : 1.12)
        .zIndex(dragOffset == .zero ? 0 : 100)
        .onTapGesture {
            state.launch(app)
        }
        // Drag an app far enough to pull it out of the folder back into the grid.
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { dragOffset = $0.translation }
                .onEnded { value in
                    let pulledOut = hypot(value.translation.width, value.translation.height) > Self.pullOutThreshold
                    if pulledOut {
                        LaunchLog.line("folder pull-out app=\(app.id) folder=\(folderID)")
                        state.removeApp(app.id, fromFolder: folderID)
                    }
                    withAnimation(LaunchConstants.Animation.quick) { dragOffset = .zero }
                }
        )
        .contextMenu {
            launcherAppContextMenu(app: app, state: state)
            Divider()
            Button(LaunchConstants.Menu.removeFromFolder) {
                state.removeApp(app.id, fromFolder: folderID)
            }
        }
    }
}
