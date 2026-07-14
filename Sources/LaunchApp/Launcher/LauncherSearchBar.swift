import AppKit
import SwiftUI

/// Single AppKit search bar — chrome, icon, field, and clear button share one hit target.
final class LauncherSearchBarView: NSView {
    let textField = LauncherSearchNSTextField()
    private let iconView = NSImageView()
    private let clearButton = NSButton()
    private let optionButton = NSButton()
    private let contentView = NSView()
    private var glassChromeView: NSView?
    private var onTextChange: ((String) -> Void)?
    private var onClear: (() -> Void)?

    var onSortByName: (() -> Void)?
    var onRefreshApps: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    nonisolated override var isFlipped: Bool { true }

    /// 중성 white — 글래스 캡슐 위 아이콘/텍스트.
    static let lavenderIcon = NSColor.white.withAlphaComponent(0.9)
    static let lavenderText = NSColor.white.withAlphaComponent(0.95)

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
            iconView.contentTintColor = LauncherSearchBarView.lavenderIcon
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
        textField.isAutomaticTextCompletionEnabled = false
        textField.allowsCharacterPickerTouchBarItem = false
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.placeholderString = LaunchConstants.Launcher.searchPlaceholder
        textField.font = NSFont.systemFont(ofSize: LaunchConstants.Launcher.searchFontSize, weight: .regular)
        textField.textColor = LauncherSearchBarView.lavenderText
        textField.target = self
        textField.action = #selector(textDidChange)
        contentView.addSubview(textField)

        clearButton.isBordered = false
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear")
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = LauncherSearchBarView.lavenderIcon.withAlphaComponent(0.80)
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.isHidden = true
        contentView.addSubview(clearButton)

        optionButton.isBordered = false
        optionButton.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Options")
        optionButton.imagePosition = .imageOnly
        optionButton.contentTintColor = LauncherSearchBarView.lavenderIcon
        optionButton.target = self
        optionButton.action = #selector(optionTapped)
        contentView.addSubview(optionButton)
    }

    private func configureChrome() {
        wantsLayer = true
        // 진짜 리퀴드 글래스 `.clear` 단일 표면. 커스텀 그라디언트/스트로크/섀도를
        // 겹치지 않는다(황금규칙) — 엣지/스펙큘러/배경 렌즈링은 시스템이 렌더링.
        // 안은 완전 투명: 뒤의 배경이 렌즈되어 비친다.
        layer?.cornerRadius = LaunchConstants.Launcher.searchHeight / 2
        layer?.masksToBounds = false

        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.cornerRadius = LaunchConstants.Launcher.searchHeight / 2
        glass.autoresizingMask = [.width, .height]
        glass.frame = bounds
        glass.contentView = contentView
        contentView.autoresizingMask = [.width, .height]
        contentView.frame = glass.bounds
        addSubview(glass)
        glassChromeView = glass
    }

    override func layout() {
        super.layout()
        glassChromeView?.frame = bounds
        contentView.frame = glassChromeView?.bounds ?? bounds

        let padding = LaunchConstants.Launcher.searchHorizontalPadding
        let iconSide: CGFloat = 18
        iconView.frame = NSRect(x: padding, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)

        let optionSide: CGFloat = 20
        optionButton.frame = NSRect(
            x: bounds.width - padding - optionSide,
            y: (bounds.height - optionSide) / 2,
            width: optionSide,
            height: optionSide
        )

        let clearSide: CGFloat = 20
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

    func setActive(_ active: Bool) {
        // 포커스를 글래스 tint(시스템 통합)로만 표현. flat 오버레이/글로우 없음.
        (glassChromeView as? NSGlassEffectView)?.tintColor = active
            ? NSColor.white.withAlphaComponent(0.12)
            : nil
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

    @objc nonisolated private func textDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.handleTextDidChange()
        }
    }

    private func handleTextDidChange() {
        let wasHidden = clearButton.isHidden
        clearButton.isHidden = textField.stringValue.isEmpty
        if wasHidden != clearButton.isHidden {
            needsLayout = true
        }
        onTextChange?(textField.stringValue)
    }

    @objc nonisolated private func clearTapped() {
        DispatchQueue.main.async { [weak self] in
            self?.handleClearTapped()
        }
    }

    private func handleClearTapped() {
        textField.stringValue = ""
        clearButton.isHidden = true
        needsLayout = true
        onClear?()
        onTextChange?("")
        window?.makeFirstResponder(textField)
    }

    @objc nonisolated private func optionTapped(_ sender: NSButton) {
        DispatchQueue.main.async { [weak self, weak sender] in
            guard let self, let sender else { return }
            showOptions(relativeTo: sender)
        }
    }

    private func showOptions(relativeTo sender: NSButton) {
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

    @objc nonisolated private func menuSortByName() {
        DispatchQueue.main.async { [weak self] in
            self?.onSortByName?()
        }
    }

    @objc nonisolated private func menuRefreshApps() {
        DispatchQueue.main.async { [weak self] in
            self?.onRefreshApps?()
        }
    }

    @objc nonisolated private func menuShowSettings() {
        DispatchQueue.main.async { [weak self] in
            self?.onShowSettings?()
        }
    }

    @objc nonisolated private func menuQuit() {
        DispatchQueue.main.async { [weak self] in
            self?.onQuit?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(textField)
        LaunchLog.line("search bar mouseDown")
        super.mouseDown(with: event)
    }
}
