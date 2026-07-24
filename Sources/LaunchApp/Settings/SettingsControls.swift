import AppKit
import Carbon.HIToolbox
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

struct GlobalHotKeyRecorder: NSViewRepresentable {
    @Binding var shortcut: GlobalHotKeyShortcut

    func makeNSView(context: Context) -> HotKeyRecorderButton {
        let button = HotKeyRecorderButton()
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.setButtonType(.momentaryPushIn)
        button.onRecordRequested = { [weak coordinator = context.coordinator] in
            coordinator?.beginRecording()
        }
        button.onKeyEvent = { [weak coordinator = context.coordinator] event in
            coordinator?.record(event)
        }
        button.onRecordingCancelled = { [weak coordinator = context.coordinator] in
            coordinator?.endRecording()
        }
        context.coordinator.button = button
        context.coordinator.updateTitle()
        return button
    }

    func updateNSView(_ button: HotKeyRecorderButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateTitle()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleNSView(_ button: HotKeyRecorderButton, coordinator: Coordinator) {
        coordinator.endRecording()
    }

    @MainActor
    final class Coordinator {
        var parent: GlobalHotKeyRecorder
        weak var button: HotKeyRecorderButton?
        private var eventMonitor: Any?

        init(parent: GlobalHotKeyRecorder) {
            self.parent = parent
        }

        func beginRecording() {
            guard let button else { return }
            button.isRecording = true
            button.title = Localized.t("단축키 입력…", "Type Shortcut…")
            button.window?.makeFirstResponder(button)
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.button?.isRecording == true else { return event }
                self.record(event)
                return nil
            }
        }

        func record(_ event: NSEvent) {
            guard let button, button.isRecording else { return }
            if event.keyCode == UInt16(kVK_Escape) {
                endRecording()
                return
            }
            guard let shortcut = GlobalHotKeyShortcut(event: event) else {
                NSSound.beep()
                return
            }
            parent.shortcut = shortcut
            endRecording()
        }

        func endRecording() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            button?.isRecording = false
            updateTitle()
        }

        func updateTitle() {
            guard let button, !button.isRecording else { return }
            button.title = parent.shortcut.displayName
            button.toolTip = Localized.t(
                "클릭한 다음 새 단축키를 누르세요. ESC는 취소합니다.",
                "Click, then press a new shortcut. Escape cancels."
            )
        }
    }
}

final class HotKeyRecorderButton: NSButton {
    var isRecording = false
    var onRecordRequested: (() -> Void)?
    var onKeyEvent: ((NSEvent) -> Void)?
    var onRecordingCancelled: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
        onRecordRequested?()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        onKeyEvent?(event)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, isRecording {
            onRecordingCancelled?()
        }
        return resigned
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
        if let image = option.image() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Color(nsColor: .controlBackgroundColor)
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
