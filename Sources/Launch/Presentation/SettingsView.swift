import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            Toggle(LaunchConstants.Settings.launchAtLogin, isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }
            ))

            Button(LaunchConstants.Menu.refreshApps) {
                state.refreshApps()
            }

            HStack {
                Text(LaunchConstants.Settings.accessibility)
                Spacer()
                Text(state.accessibilityState.label)
                    .foregroundStyle(state.accessibilityState == .allowed ? .green : .orange)
            }

            HStack {
                Text(LaunchConstants.Settings.trackpad)
                Spacer()
                Text(state.trackpadGateState.label)
                    .foregroundStyle(state.trackpadGateState == .exactFourFinger ? .green : .orange)
            }

            Button(LaunchConstants.Settings.requestAccessibility) {
                state.requestAccessibilityPermission()
            }

            if let error = state.loginItemError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(LaunchConstants.Settings.padding)
        .frame(width: LaunchConstants.Settings.width)
    }
}
