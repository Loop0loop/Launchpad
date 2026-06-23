import AppKit
import LaunchCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum LauncherItem: Identifiable {
    case app(LaunchApp)
    case folder(LaunchFolder, [LaunchApp])

    var id: String {
        switch self {
        case .app(let app): app.id
        case .folder(let folder, _): folder.id
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var apps: [LaunchApp] = []
    @Published var folders: [LaunchFolder] = []
    @Published var query = "" {
        didSet { currentPage = 0 }
    }
    @Published var currentPage = 0
    @Published var draggedAppID: String?
    @Published var openFolder: LaunchFolder?
    @Published var launchAtLogin = false
    @Published var loginItemError: String?
    @Published private var order: [String] = []

    private var iconCache: [String: NSImage] = [:]
    private let pageSize = 35
    private let layoutKey = "layoutOrder"
    private let foldersKey = "folders"

    init() {
        loadFolders()
        order = savedOrder()
        refreshLoginItemStatus()
        refreshApps()
    }

    var visibleApps: [LaunchApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var visibleItems: [LauncherItem] {
        if !query.isEmpty {
            return visibleApps.map(LauncherItem.app)
        }

        let folderedIDs = Set(folders.flatMap(\.appIDs))
        let rootApps = apps.filter { !folderedIDs.contains($0.id) }
        let appItems = rootApps.map { LauncherItem.app($0) }
        let folderItems = folders.map { folder in
            LauncherItem.folder(folder, folder.appIDs.compactMap(appByID))
        }
        let allItems = appItems + folderItems
        let byID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        let ordered = order.compactMap { byID[$0] }
        let orderedIDs = Set(ordered.map(\.id))
        return ordered + allItems.filter { !orderedIDs.contains($0.id) }
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(visibleItems.count) / Double(pageSize))))
    }

    var pageItems: [LauncherItem] {
        Array(visibleItems.dropFirst(currentPage * pageSize).prefix(pageSize))
    }

    func refreshApps() {
        apps = AppCatalog.scan()
        saveOrder()
    }

    func launch(_ app: LaunchApp) {
        NSWorkspace.shared.open(URL(fileURLWithPath: app.path))
        NSApp.hide(nil)
    }

    func icon(for app: LaunchApp) -> NSImage {
        if let icon = iconCache[app.path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        iconCache[app.path] = icon
        return icon
    }

    func move(_ id: String, before targetID: String) {
        let nextOrder = LayoutOrder.move(id, before: targetID, in: visibleItems.map(\.id))
        saveOrder(nextOrder)
    }

    func createFolder(draggedID: String, targetID: String) {
        guard folders.allSatisfy({ !$0.appIDs.contains(draggedID) && !$0.appIDs.contains(targetID) }) else {
            return
        }

        let result = FolderLayout.createFolder(
            id: "folder-\(UUID().uuidString)",
            draggedID: draggedID,
            targetID: targetID,
            folders: folders,
            order: visibleItems.map(\.id)
        )
        folders = result.folders
        saveFolders()
        saveOrder(result.order)
        openFolder = folders.last
    }

    func appByID(_ id: String) -> LaunchApp? {
        apps.first { $0.id == id }
    }

    func closeFolder() {
        openFolder = nil
    }

    func apps(in folder: LaunchFolder) -> [LaunchApp] {
        folder.appIDs.compactMap(appByID)
    }

    func itemName(_ id: String) -> String {
        appByID(id)?.name ?? id
    }

    func saveOrder(_ order: [String]? = nil) {
        self.order = order ?? visibleItems.map(\.id)
        UserDefaults.standard.set(self.order, forKey: layoutKey)
    }

    func refreshLoginItemStatus() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil

        guard #available(macOS 13.0, *) else {
            loginItemError = "Requires macOS 13 or newer."
            launchAtLogin = false
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }

        refreshLoginItemStatus()
    }

    private func loadFolders() {
        guard let data = UserDefaults.standard.data(forKey: foldersKey),
              let decoded = try? JSONDecoder().decode([LaunchFolder].self, from: data) else { return }
        folders = decoded
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: foldersKey)
    }

    private func savedOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: layoutKey) ?? []
    }

    private func folderedIDs() -> Set<String> {
        Set(folders.flatMap(\.appIDs))
    }

    func changePage(_ delta: Int) {
        currentPage = min(max(currentPage + delta, 0), pageCount - 1)
    }
}

extension AppState {
    func dropApp(_ draggedID: String, on targetID: String) {
        if draggedID == targetID { return }

        if let _ = appByID(targetID), appByID(draggedID) != nil {
            createFolder(draggedID: draggedID, targetID: targetID)
        } else {
            move(draggedID, before: targetID)
        }
    }
}

struct LauncherView: View {
    @ObservedObject var state: AppState

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
                        LauncherItemView(item: item, state: state)
                    }
                }
                .frame(height: 620, alignment: .top)

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
                NSApp.hide(nil)
            } else {
                state.query = ""
            }
        }
    }
}

struct LauncherItemView: View {
    let item: LauncherItem
    @ObservedObject var state: AppState

    var body: some View {
        switch item {
        case .app(let app):
            AppIcon(app: app, state: state)
        case .folder(let folder, let apps):
            FolderIcon(folder: folder, apps: apps, state: state)
        }
    }
}

struct AppIcon: View {
    let app: LaunchApp
    @ObservedObject var state: AppState

    var body: some View {
        Button {
            state.launch(app)
        } label: {
            VStack(spacing: 8) {
                Image(nsImage: state.icon(for: app))
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
                            Image(nsImage: state.icon(for: app))
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

    private let columns = Array(repeating: GridItem(.fixed(112), spacing: 18), count: 4)

    var body: some View {
        VStack(spacing: 22) {
            Text(folder.name)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(state.apps(in: folder)) { app in
                    AppIcon(app: app, state: state)
                }
            }
            .frame(minHeight: 150, alignment: .top)
        }
        .padding(30)
        .frame(width: 560)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct AppDropDelegate: DropDelegate {
    let targetID: String
    @ObservedObject var state: AppState

    func dropEntered(info: DropInfo) {
        guard let dragged = state.draggedAppID else { return }
        state.move(dragged, before: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let dragged = state.draggedAppID {
            state.dropApp(dragged, on: targetID)
        }
        state.draggedAppID = nil
        return true
    }
}

struct FolderDropDelegate: DropDelegate {
    let targetID: String
    @ObservedObject var state: AppState

    func dropEntered(info: DropInfo) {
        guard let dragged = state.draggedAppID else { return }
        state.move(dragged, before: targetID)
    }

    func performDrop(info: DropInfo) -> Bool {
        state.draggedAppID = nil
        return true
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))

            Button("Refresh Apps") {
                state.refreshApps()
            }

            if let error = state.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

@MainActor
final class TrackpadGestureMonitor {
    private var monitors: [Any] = []

    func start(onIntent: @escaping @MainActor (TrackpadIntent) -> Void) {
        let mask: NSEvent.EventTypeMask = [.magnify, .swipe]

        let handler: (NSEvent) -> Void = { event in
            Task { @MainActor in
                if event.type == .magnify, let intent = TrackpadIntent.pinch(magnification: event.magnification) {
                    onIntent(intent)
                } else if event.type == .swipe, let intent = TrackpadIntent.horizontalSwipe(deltaX: event.deltaX) {
                    onIntent(intent)
                }
            }
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    let trackpadMonitor = TrackpadGestureMonitor()
    var window: NSWindow?
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeWindow()
        makeStatusItem()
        startTrackpadMonitor()
        showLauncher()
    }

    func makeWindow() {
        let frame = NSScreen.main?.frame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: LauncherView(state: state))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .mainMenu
        self.window = window
    }

    func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "L"
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Launch", action: #selector(showLauncher), keyEquivalent: "l")
        menu.addItem(withTitle: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Refresh Apps", action: #selector(refreshApps), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApp.terminate), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc func showLauncher() {
        state.query = ""
        window?.setFrame(NSScreen.main?.frame ?? window?.frame ?? .zero, display: true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideLauncher() {
        window?.orderOut(nil)
    }

    @objc func refreshApps() {
        state.refreshApps()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .init(x: 0, y: 0, width: 360, height: 180),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Launch Settings"
            window.contentView = NSHostingView(rootView: SettingsView(state: state))
            settingsWindow = window
        }

        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func startTrackpadMonitor() {
        trackpadMonitor.start { [weak self] intent in
            guard let self else { return }
            switch intent {
            case .open:
                self.showLauncher()
            case .close:
                self.hideLauncher()
            case .previousPage:
                self.state.changePage(-1)
            case .nextPage:
                self.state.changePage(1)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
