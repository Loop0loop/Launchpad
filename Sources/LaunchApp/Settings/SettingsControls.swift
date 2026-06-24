import AppKit
import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsGlassCard()
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title) {
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct SettingsSliderRow: View {
    let title: String
    let help: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let display: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(display).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SettingsActionRow: View {
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

struct AppIconPicker: View {
    @Binding var selection: AppIconOption

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppIconOption.allCases) { option in
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 6) {
                        iconView(for: option)
                            .frame(width: 38, height: 38)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                        
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 4, height: 4)
                            .opacity(selection == option ? 1 : 0)
                    }
                }
                .buttonStyle(.plain)
                .help(option.title)
            }
        }
    }

    @ViewBuilder
    private func iconView(for option: AppIconOption) -> some View {
        switch option {
        case .mono:
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                Image(systemName: "circle.grid.3x3")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.primary)
            }
        case .blue:
            ZStack {
                Color.blue
                Image(systemName: "circle.grid.3x3.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
        case .color:
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow {
                        Circle().fill(.red)
                        Circle().fill(.orange)
                        Circle().fill(.yellow)
                    }
                    GridRow {
                        Circle().fill(.green)
                        Circle().fill(.blue)
                        Circle().fill(.purple)
                    }
                    GridRow {
                        Circle().fill(.pink)
                        Circle().fill(.cyan)
                        Circle().fill(.mint)
                    }
                }
                .frame(width: 18, height: 18)
            }
        case .rocket:
            ZStack {
                LinearGradient(colors: [Color.gray, Color.black], startPoint: .top, endPoint: .bottom)
                Image(systemName: "rocket.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
            }
        }
    }
}

struct SettingsStatusRow: View {
    let title: String
    let status: String
    let positive: Bool

    var body: some View {
        SettingsRow(title: title) {
            Text(status)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill((positive ? Color.green : Color.orange).opacity(0.18)))
                .foregroundStyle(positive ? .green : .orange)
        }
    }
}
