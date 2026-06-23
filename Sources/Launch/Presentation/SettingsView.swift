import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color.black.opacity(LaunchConstants.Appearance.settingsBackdropOpacity)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: LaunchConstants.Settings.sectionSpacing) {
                    settingsHeader

                    appearanceSection
                    gridLayoutSection
                    generalSection
                    appSourcesSection
                    permissionsSection
                }
                .padding(LaunchConstants.Settings.padding)
                .padding(.top, LaunchConstants.Settings.titleBarInset)
            }
        }
        .frame(width: LaunchConstants.Settings.width, alignment: .top)
        .frame(minHeight: LaunchConstants.Settings.height)
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LaunchConstants.App.settingsTitle)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Customize Launch")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var appearanceSection: some View {
        SettingsGlassSection(title: LaunchConstants.Settings.appearanceSection) {
            AppearancePreview(
                dimOpacity: state.appearance.backgroundDimOpacity,
                folderDimOpacity: state.appearance.folderDimOpacity
            )

            SettingsSliderRow(
                title: LaunchConstants.Settings.backgroundTransparency,
                help: LaunchConstants.Settings.backgroundTransparencyHelp,
                value: transparencyBinding,
                displayValue: "\(Int((state.appearance.backgroundTransparency * 100).rounded()))%"
            )

            SettingsSliderRow(
                title: LaunchConstants.Settings.folderDim,
                help: LaunchConstants.Settings.folderDimHelp,
                value: folderDimBinding,
                range: LaunchConstants.Appearance.minFolderDim...LaunchConstants.Appearance.maxFolderDim,
                displayValue: "\(Int((state.appearance.folderDimOpacity * 100).rounded()))%"
            )
        }
    }

    private var gridLayoutSection: some View {
        SettingsGlassSection(title: LaunchConstants.Settings.gridLayoutSection) {
            Picker(LaunchConstants.Settings.gridPreset, selection: $state.gridLayout) {
                ForEach(GridLayoutSettings.presets) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Picker(LaunchConstants.Settings.displayMode, selection: $state.displayMode) {
                ForEach(LauncherDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var generalSection: some View {
        SettingsGlassSection(title: LaunchConstants.Settings.generalSection) {
            SettingsToggleRow(
                title: LaunchConstants.Settings.launchAtLogin,
                isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                )
            )

            SettingsToggleRow(
                title: LaunchConstants.Settings.windowBrowsingMode,
                isOn: $state.windowBrowsingMode
            )

            SettingsActionRow(title: LaunchConstants.Menu.refreshApps) {
                state.refreshApps()
            }

            SettingsActionRow(title: LaunchConstants.Settings.importNativeLayout) {
                state.importNativeLaunchpadLayout()
            }

            if let error = state.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var appSourcesSection: some View {
        SettingsGlassSection(title: LaunchConstants.Settings.appSourcesSection) {
            if state.appSourcePaths.isEmpty {
                Text("Default application folders only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.appSourcePaths, id: \.self) { path in
                    HStack(spacing: 10) {
                        Text(path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button(LaunchConstants.Settings.removeAppSource) {
                            state.removeAppSource(path)
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                    }
                }
            }

            SettingsActionRow(title: LaunchConstants.Settings.addAppSource) {
                state.requestAppSource()
            }
        }
    }

    private var permissionsSection: some View {
        SettingsGlassSection(title: LaunchConstants.Settings.permissionsSection) {
            SettingsStatusRow(
                title: LaunchConstants.Settings.accessibility,
                status: state.accessibilityState.label,
                isPositive: state.accessibilityState == .allowed
            )

            SettingsStatusRow(
                title: LaunchConstants.Settings.trackpad,
                status: state.trackpadGateState.label,
                isPositive: state.trackpadGateState == .exactPinch
            )

            SettingsStatusRow(
                title: LaunchConstants.Settings.globalHotKey,
                status: state.globalHotKeyState.label,
                isPositive: state.globalHotKeyState == .allowed
            )

            SettingsStatusRow(
                title: LaunchConstants.Settings.f4Key,
                status: state.f4KeyState.label,
                isPositive: state.f4KeyState == .allowed
            )

            SettingsActionRow(title: LaunchConstants.Settings.requestAccessibility) {
                state.requestAccessibilityPermission()
            }
        }
    }

    private var transparencyBinding: Binding<Double> {
        Binding(
            get: { state.appearance.backgroundTransparency },
            set: { state.appearance.backgroundTransparency = $0 }
        )
    }

    private var folderDimBinding: Binding<Double> {
        Binding(
            get: { state.appearance.folderDimOpacity },
            set: { state.appearance.folderDimOpacity = $0 }
        )
    }
}

private struct SettingsGlassSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary.opacity(0.92))

            VStack(alignment: .leading, spacing: 14) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsGlassCard()
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let help: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let displayValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(displayValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range)

            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let status: String
    let isPositive: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(status)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((isPositive ? Color.green : Color.orange).opacity(0.18))
                )
                .foregroundStyle(isPositive ? .green : .orange)
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AppearancePreview: View {
    let dimOpacity: Double
    let folderDimOpacity: Double

    var body: some View {
        HStack(spacing: 12) {
            previewTile(label: "Launcher", dimOpacity: dimOpacity)
            previewTile(label: "Folder", dimOpacity: folderDimOpacity)
        }
    }

    private func previewTile(label: String, dimOpacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.55), .purple.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VisualEffectView(material: .fullScreenUI, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                RoundedRectangle(cornerRadius: 10)
                    .fill(.black.opacity(dimOpacity))
            }
            .frame(height: 52)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
