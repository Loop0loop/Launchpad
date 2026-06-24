import AppKit
import SwiftUI

/// Tabbed settings panel (General / Interface / Apps / Advanced / About), liquid-glass styled.
/// Stage 1 wires every control that already has backing in `AppState`; new-backend controls
/// (menu bar icon, app icon, configurable hotkey, hot corner, trackpad fingers) land in later stages.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @State private var tab: SettingsTab = .general

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            Color.black.opacity(LaunchConstants.Appearance.settingsBackdropOpacity)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsTabBar(selection: $tab)
                    .padding(.top, LaunchConstants.Settings.titleBarInset)
                    .padding(.horizontal, LaunchConstants.Settings.padding)
                    .padding(.bottom, 8)

                Divider().opacity(0.12)

                ScrollView {
                    VStack(alignment: .leading, spacing: LaunchConstants.Settings.sectionSpacing) {
                        switch tab {
                        case .general: generalTab
                        case .interface: interfaceTab
                        case .apps: appsTab
                        case .advanced: advancedTab
                        case .about: aboutTab
                        }
                    }
                    .padding(LaunchConstants.Settings.padding)
                }
            }
        }
        .frame(
            width: LaunchConstants.Settings.width,
            height: LaunchConstants.Settings.height,
            alignment: .top
        )
        .foregroundStyle(.white)
    }

    // MARK: General

    private var generalTab: some View {
        Group {
            SettingsSection(title: Localized.t("실행", "Launch")) {
                SettingsToggleRow(
                    title: LaunchConstants.Settings.launchAtLogin,
                    isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })
                )
                if let error = state.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            SettingsSection(title: LaunchConstants.Settings.appearanceSection) {
                SettingsToggleRow(title: LaunchConstants.Settings.showMenuBarIcon, isOn: $state.showMenuBarIcon)
                SettingsRow(title: LaunchConstants.Settings.appIcon) {
                    AppIconPicker(selection: $state.appIcon)
                }
                SettingsRow(title: Localized.t("언어", "Language")) {
                    Picker("", selection: $state.appLanguage) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: Interface

    private var interfaceTab: some View {
        Group {
            SettingsSection(title: Localized.t("레이아웃", "Layout")) {
                SettingsRow(title: LaunchConstants.Settings.sortBy) {
                    Picker("", selection: $state.sortMode) {
                        ForEach(SortMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsRow(title: Localized.t("탐색 방식", "Browsing Style")) {
                    Picker("", selection: $state.displayMode) {
                        ForEach(LauncherDisplayMode.allCases) { mode in
                            Text(mode.browsingLabel).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                SettingsRow(title: Localized.t("아이콘 그리드", "Icon Grid")) {
                    HStack(spacing: 8) {
                        Stepper(value: columnsBinding, in: 4...12) {
                            Text("\(state.gridLayout.columns)").monospacedDigit()
                        }
                        .fixedSize()
                        Text("×").foregroundStyle(.secondary)
                        Stepper(value: rowsBinding, in: 3...10) {
                            Text("\(state.gridLayout.rows)").monospacedDigit()
                        }
                        .fixedSize()
                    }
                }
            }

            SettingsSection(title: Localized.t("배경", "Background")) {
                SettingsSliderRow(
                    title: LaunchConstants.Settings.backgroundTransparency,
                    help: LaunchConstants.Settings.backgroundTransparencyHelp,
                    value: bind(\.appearance.backgroundTransparency),
                    display: percent(state.appearance.backgroundTransparency)
                )
                SettingsSliderRow(
                    title: LaunchConstants.Settings.folderDim,
                    help: LaunchConstants.Settings.folderDimHelp,
                    value: bind(\.appearance.folderDimOpacity),
                    range: LaunchConstants.Appearance.minFolderDim...LaunchConstants.Appearance.maxFolderDim,
                    display: percent(state.appearance.folderDimOpacity)
                )
            }
        }
    }

    // MARK: Apps

    private var appsTab: some View {
        Group {
            SettingsSection(title: LaunchConstants.Settings.appSourcesSection) {
                if state.appSourcePaths.isEmpty {
                    Text(Localized.t("기본 응용 프로그램 폴더만", "Default application folders only"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(state.appSourcePaths, id: \.self) { path in
                        HStack(spacing: 10) {
                            Text(path).font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(LaunchConstants.Settings.removeAppSource) { state.removeAppSource(path) }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                        }
                    }
                }
                SettingsActionRow(title: LaunchConstants.Settings.addAppSource) { state.requestAppSource() }
            }

            SettingsSection(title: Localized.t("카탈로그", "Catalog")) {
                SettingsActionRow(title: LaunchConstants.Menu.refreshApps) { state.refreshApps() }
                SettingsActionRow(title: LaunchConstants.Settings.importNativeLayout) { state.importNativeLaunchpadLayout() }
            }
        }
    }

    // MARK: Advanced

    private var advancedTab: some View {
        Group {
            SettingsSection(title: LaunchConstants.Settings.permissionsSection) {
                SettingsStatusRow(title: LaunchConstants.Settings.accessibility, status: state.accessibilityState.label, positive: state.accessibilityState == .allowed)
                SettingsStatusRow(title: LaunchConstants.Settings.trackpad, status: state.trackpadGateState.label, positive: state.trackpadGateState == .exactPinch)
                SettingsStatusRow(title: LaunchConstants.Settings.globalHotKey, status: state.globalHotKeyState.label, positive: state.globalHotKeyState == .allowed)
                SettingsStatusRow(title: LaunchConstants.Settings.f4Key, status: state.f4KeyState.label, positive: state.f4KeyState == .allowed)
                SettingsActionRow(title: LaunchConstants.Settings.requestAccessibility) { state.requestAccessibilityPermission() }
            }

            SettingsSection(title: Localized.t("창", "Window")) {
                SettingsToggleRow(title: LaunchConstants.Settings.windowBrowsingMode, isOn: $state.windowBrowsingMode)
            }
        }
    }

    // MARK: About

    private var aboutTab: some View {
        SettingsSection(title: Localized.t("정보", "About")) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LaunchConstants.App.settingsTitle.replacingOccurrences(of: " Settings", with: ""))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("\(Localized.t("버전", "Version")) \(Self.appVersion)").font(.subheadline).foregroundStyle(.secondary)
                    Text(Self.bundleID).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: Bindings / helpers

    private var columnsBinding: Binding<Int> {
        Binding(get: { state.gridLayout.columns },
                set: { state.gridLayout = GridLayoutSettings(columns: $0, rows: state.gridLayout.rows) })
    }
    private var rowsBinding: Binding<Int> {
        Binding(get: { state.gridLayout.rows },
                set: { state.gridLayout = GridLayoutSettings(columns: state.gridLayout.columns, rows: $0) })
    }
    private func bind(_ keyPath: ReferenceWritableKeyPath<AppState, Double>) -> Binding<Double> {
        Binding(get: { state[keyPath: keyPath] }, set: { state[keyPath: keyPath] = $0 })
    }
    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "—" }
}
