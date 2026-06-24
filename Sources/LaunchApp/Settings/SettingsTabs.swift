import SwiftUI

extension LauncherDisplayMode {
    /// Video reference labels the vertical mode "Scroll".
    var browsingLabel: String {
        switch self {
        case .paged: "Paged"
        case .vertical: "Scroll"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, interface, apps, advanced, about

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return Localized.t("일반", "General")
        case .interface: return Localized.t("인터페이스", "Interface")
        case .apps: return Localized.t("앱", "Apps")
        case .advanced: return Localized.t("고급", "Advanced")
        case .about: return Localized.t("정보", "About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .interface: "slider.horizontal.3"
        case .apps: "square.grid.2x2"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}

struct SettingsTabBar: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                let active = tab == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage).font(.system(size: 15, weight: .medium))
                        Text(tab.title).font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.white.opacity(0.12))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

