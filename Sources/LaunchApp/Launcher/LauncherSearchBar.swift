import AppKit
import SwiftUI

/// Single AppKit search bar — chrome, icon, field, and clear button share one hit target.
final class LauncherSearchBarView: NSView {
    let textField = LauncherSearchNSTextField()
    private let iconView = NSImageView()
    private let clearButton = NSButton()
    private let optionButton = NSButton()
    private let contentView = NSView()
    private var chromeView: NSView?
    private var glassChromeView: NSView?
    private var visualChromeView: NSVisualEffectView?
    private var onTextChange: ((String) -> Void)?
    private var onClear: (() -> Void)?

    var onSortByName: (() -> Void)?
    var onRefreshApps: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func configureHandlers(onTextChange: @escaping (String) -> Void, onClear: @escaping () -> Void) {
        self.onTextChange = onTextChange
        self.onClear = onClear
    }

    private func configure() {
        wantsLayer = true

        configureChrome()

        if let icon = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) {
            iconView.image = icon
            iconView.contentTintColor = NSColor.white.withAlphaComponent(0.7)
            iconView.imageScaling = .scaleProportionallyDown
        }
        contentView.addSubview(iconView)

        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.isEditable = true
        textField.isSelectable = true
        textField.isEnabled = true
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.placeholderString = LaunchConstants.Launcher.searchPlaceholder
        textField.font = NSFont.systemFont(ofSize: LaunchConstants.Launcher.searchFontSize, weight: .regular)
        textField.textColor = .white
        textField.target = self
        textField.action = #selector(textDidChange)
        contentView.addSubview(textField)

        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.isHidden = true
        contentView.addSubview(clearButton)

        optionButton.isBordered = false
        optionButton.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Options")
        optionButton.imagePosition = .imageOnly
        optionButton.contentTintColor = NSColor.white.withAlphaComponent(0.75)
        optionButton.target = self
        optionButton.action = #selector(optionTapped)
        contentView.addSubview(optionButton)
    }

    private func configureChrome() {
        wantsLayer = true
        layer?.cornerRadius = LaunchConstants.Launcher.searchHeight / 2
        layer?.masksToBounds = false

        let bgView = NSView()
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = LaunchConstants.Launcher.searchHeight / 2
        bgView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        bgView.layer?.borderWidth = 0
        bgView.layer?.borderColor = NSColor.clear.cgColor
        bgView.autoresizingMask = [.width, .height]
        bgView.frame = bounds

        // 그림자 설정 (테두리 없는 부드러운 그림자)
        bgView.layer?.shadowColor = NSColor.black.cgColor
        bgView.layer?.shadowOpacity = 0.08
        bgView.layer?.shadowRadius = 8
        bgView.layer?.shadowOffset = NSSize(width: 0, height: -2)

        addSubview(bgView)
        addSubview(contentView)
        chromeView = bgView
    }

    override func layout() {
        super.layout()
        chromeView?.frame = bounds
        contentView.frame = bounds

        let padding = LaunchConstants.Launcher.searchHorizontalPadding
        let iconSide: CGFloat = 16
        iconView.frame = NSRect(x: padding, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)

        let optionSide: CGFloat = 18
        optionButton.frame = NSRect(
            x: bounds.width - padding - optionSide,
            y: (bounds.height - optionSide) / 2,
            width: optionSide,
            height: optionSide
        )

        let clearSide: CGFloat = 18
        clearButton.frame = NSRect(
            x: optionButton.frame.minX - 6 - clearSide,
            y: (bounds.height - clearSide) / 2,
            width: clearSide,
            height: clearSide
        )

        let textX = iconView.frame.maxX + 8
        let textEndX = clearButton.isHidden ? optionButton.frame.minX - 8 : clearButton.frame.minX - 6
        let textWidth = max(0, textEndX - textX)
        let textHeight: CGFloat = 22
        let textY = (bounds.height - textHeight) / 2
        textField.frame = NSRect(x: textX, y: textY, width: textWidth, height: textHeight)
    }

    private func addChromeHighlights() {
        guard let layer else { return }
        layer.sublayers?.removeAll { $0.name == "searchChromeHighlight" }

        let shape = CAShapeLayer()
        shape.name = "searchChromeHighlight"
        shape.frame = bounds
        shape.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: LaunchConstants.Launcher.searchHeight / 2,
            cornerHeight: LaunchConstants.Launcher.searchHeight / 2,
            transform: nil
        )
        shape.fillColor = NSColor.clear.cgColor
        shape.strokeColor = NSColor.clear.cgColor
        shape.lineWidth = 0.0
        layer.addSublayer(shape)
    }

    func setActive(_ active: Bool) {
        chromeView?.layer?.backgroundColor = NSColor.white.withAlphaComponent(active ? 0.12 : 0.06).cgColor
    }

    func updateText(_ text: String) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
        let wasHidden = clearButton.isHidden
        clearButton.isHidden = text.isEmpty
        if wasHidden != clearButton.isHidden {
            needsLayout = true
        }
    }

    @objc private func textDidChange() {
        let wasHidden = clearButton.isHidden
        clearButton.isHidden = textField.stringValue.isEmpty
        if wasHidden != clearButton.isHidden {
            needsLayout = true
        }
        onTextChange?(textField.stringValue)
    }

    @objc private func clearTapped() {
        textField.stringValue = ""
        clearButton.isHidden = true
        needsLayout = true
        onClear?()
        onTextChange?("")
        window?.makeFirstResponder(textField)
    }

    @objc private func optionTapped(_ sender: NSButton) {
        let menu = NSMenu()

        let sortTitle = Localized.t("이름순 정렬", "Sort by Name")
        let sortItem = NSMenuItem(title: sortTitle, action: #selector(menuSortByName), keyEquivalent: "")
        sortItem.target = self
        menu.addItem(sortItem)

        let refreshTitle = Localized.t("앱 새로고침", "Refresh Apps")
        let refreshItem = NSMenuItem(title: refreshTitle, action: #selector(menuRefreshApps), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        let settingsTitle = Localized.t("설정...", "Settings...")
        let settingsItem = NSMenuItem(title: settingsTitle, action: #selector(menuShowSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitTitle = Localized.t("종료", "Quit")
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(menuQuit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        let origin = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    @objc private func menuSortByName() {
        onSortByName?()
    }

    @objc private func menuRefreshApps() {
        onRefreshApps?()
    }

    @objc private func menuShowSettings() {
        onShowSettings?()
    }

    @objc private func menuQuit() {
        onQuit?()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(textField)
        LaunchLog.line("search bar mouseDown")
        super.mouseDown(with: event)
    }
}

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
            state?.refreshApps()
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
