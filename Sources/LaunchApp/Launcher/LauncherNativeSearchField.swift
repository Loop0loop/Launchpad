import AppKit
import SwiftUI

struct LauncherNativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var requestFocus: Bool
    var onFieldReady: (NSTextField) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> LauncherSearchNSTextField {
        let field = LauncherSearchNSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = LaunchConstants.Launcher.searchPlaceholder
        field.font = NSFont.systemFont(ofSize: LaunchConstants.Launcher.searchFontSize, weight: .regular)
        field.textColor = .white
        field.placeholderAttributedString = NSAttributedString(
            string: LaunchConstants.Launcher.searchPlaceholder,
            attributes: [.foregroundColor: NSColor.white.withAlphaComponent(0.55)]
        )
        field.stringValue = text
        onFieldReady(field)
        return field
    }

    func updateNSView(_ field: LauncherSearchNSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        onFieldReady(field)
        if requestFocus, field.window?.firstResponder !== field {
            field.window?.makeFirstResponder(field)
        }
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
        LaunchLog.line("search field mouseDown")
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        LaunchLog.line("search field becomeFirstResponder ok=\(ok)")
        return ok
    }
}
