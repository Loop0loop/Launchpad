import AppKit

@MainActor
final class SearchFocusController {
    weak var field: NSTextField?
    var shouldFocusOnShow = false

    func register(_ bar: LauncherSearchBarView) {
        field = bar.textField
    }

    func focus() {
        guard let field else {
            LaunchLog.line("search focus skipped field=nil")
            return
        }
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.window?.makeKey()
        let accepted = field.window?.makeFirstResponder(field) ?? false
        shouldFocusOnShow = false
        LaunchLog.line("search focus ok=\(accepted)")
    }

    func isFocused() -> Bool {
        guard let field, let firstResponder = field.window?.firstResponder else { return false }
        return firstResponder === field || firstResponder === field.currentEditor()
    }
}
