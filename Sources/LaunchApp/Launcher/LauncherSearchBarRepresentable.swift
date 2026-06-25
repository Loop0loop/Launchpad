import AppKit
import SwiftUI

struct LauncherSearchBarRepresentable: NSViewRepresentable {
    @Binding var text: String
    @ObservedObject var state: AppState
    var onBarReady: (LauncherSearchBarView) -> Void

    func makeNSView(context: Context) -> LauncherSearchBarView {
        let bar = LauncherSearchBarView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: LaunchConstants.Launcher.searchWidth,
                height: LaunchConstants.Launcher.searchHeight
            )
        )
        bar.textField.delegate = context.coordinator
        bar.configureHandlers(
            onTextChange: { context.coordinator.text = $0 },
            onClear: { context.coordinator.text = "" }
        )

        bar.onSortByName = { [weak state] in
            state?.sortMode = .name
        }
        bar.onRefreshApps = { [weak state] in
            state?.refreshAppsAsync()
        }
        bar.onShowSettings = {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.showSettings()
            }
        }
        bar.onQuit = {
            NSApp.terminate(nil)
        }

        bar.updateText(text)
        onBarReady(bar)
        return bar
    }

    func updateNSView(_ bar: LauncherSearchBarView, context: Context) {
        bar.textField.placeholderString = LaunchConstants.Launcher.searchPlaceholder
        bar.updateText(text)
        onBarReady(bar)
    }

    /// Pin the field to a fixed size so SwiftUI doesn't stretch the NSView to the full
    /// container width (the bar was filling the row without this).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LauncherSearchBarView, context: Context) -> CGSize? {
        CGSize(width: LaunchConstants.Launcher.searchWidth, height: LaunchConstants.Launcher.searchHeight)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

    }
}

final class LauncherSearchNSTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { (superview as? LauncherSearchBarView)?.setActive(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { (superview as? LauncherSearchBarView)?.setActive(false) }
        return ok
    }

    override func drawFocusRingMask() {
        // Suppress default active focus ring border
    }

    override var focusRingMaskBounds: NSRect {
        .zero
    }
}
