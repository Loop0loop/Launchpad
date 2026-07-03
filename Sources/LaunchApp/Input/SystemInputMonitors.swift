import AppKit
import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyAdapter {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var actions: [UInt32: @MainActor () -> Void] = [:]

    func start(
        f4Enabled: Bool,
        toggleAction: @escaping @MainActor () -> Void,
        f4Action: @escaping @MainActor () -> Void
    ) -> (toggle: Bool, f4: Bool) {
        stop()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(
            GetApplicationEventTarget(),
            GlobalHotKeyAdapter.handleHotKey,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        ) == noErr else {
            stop()
            return (false, false)
        }

        let toggleRegistered = register(
            id: LaunchConstants.HotKey.toggleID,
            LaunchConstants.HotKey.toggleKeyCode,
            modifiers: LaunchConstants.HotKey.toggleModifiers,
            action: toggleAction
        )
        let f4Registered = f4Enabled
            ? register(
                id: LaunchConstants.HotKey.f4ID,
                LaunchConstants.HotKey.f4KeyCode,
                modifiers: LaunchConstants.HotKey.f4Modifiers,
                action: f4Action
            )
            : false

        return (toggleRegistered, f4Registered)
    }

    func stop() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRefs = []
        eventHandlerRef = nil
        actions = [:]
    }

    private func register(
        id: UInt32,
        _ keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping @MainActor () -> Void
    ) -> Bool {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: LaunchConstants.HotKey.signature, id: id)
        guard RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        ) == noErr, let hotKeyRef else {
            return false
        }

        hotKeyRefs.append(hotKeyRef)
        actions[id] = action
        return true
    }

    private static let handleHotKey: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }

        let adapter = Unmanaged<GlobalHotKeyAdapter>.fromOpaque(userData).takeUnretainedValue()
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == LaunchConstants.HotKey.signature else { return noErr }

        Task { @MainActor in
            adapter.actions[hotKeyID.id]?()
        }
        return noErr
    }
}

final class F4KeyTapMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var action: (@MainActor () -> Void)?

    func start(enabled: Bool, action: @escaping @MainActor () -> Void) -> Bool {
        stop()
        guard enabled else { return false }
        self.action = action
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << LaunchConstants.HotKey.cgSystemDefinedEventType)
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: F4KeyTapMonitor.handleEvent,
            userInfo: userData
        ) else {
            self.action = nil
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
        action = nil
    }

    private func f4Event(_ type: CGEventType, event: CGEvent) -> (isF4: Bool, isDown: Bool) {
        if type == .keyDown || type == .keyUp {
            return (
                event.getIntegerValueField(.keyboardEventKeycode) == Int64(LaunchConstants.HotKey.f4KeyCode),
                type == .keyDown
            )
        }
        guard type.rawValue == LaunchConstants.HotKey.cgSystemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == LaunchConstants.HotKey.systemDefinedKeySubtype else { return (false, false) }
        let keyCode = (nsEvent.data1 & 0xFFFF_0000) >> 16
        let keyState = (nsEvent.data1 & 0x0000_FF00) >> 8
        return (
            LaunchConstants.HotKey.f4SystemKeyTypes.contains(keyCode),
            keyState == LaunchConstants.HotKey.systemKeyDownState
        )
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<F4KeyTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        let f4 = monitor.f4Event(type, event: event)
        guard f4.isF4 else { return Unmanaged.passUnretained(event) }
        if f4.isDown {
            let action = monitor.action
            Task { @MainActor in action?() }
        }
        return nil
    }
}

@MainActor
final class HotCornerMonitor {
    private var timer: Timer?
    private var lastTrigger = Date.distantPast
    private var corner = "Disabled"

    func start(corner: String, action: @escaping @MainActor () -> Void) {
        stop()
        guard corner != "Disabled" else { return }
        self.corner = corner
        timer = Timer.scheduledTimer(withTimeInterval: LaunchConstants.HotCorner.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPointerInConfiguredCorner(), self.canTrigger else { return }
                self.lastTrigger = Date()
                action()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var canTrigger: Bool {
        Date().timeIntervalSince(lastTrigger) >= LaunchConstants.HotCorner.cooldown
    }

    private func isPointerInConfiguredCorner() -> Bool {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            let frame = screen.frame
            let size = LaunchConstants.HotCorner.activationSize
            switch corner {
            case "Top Left":
                return location.x >= frame.minX && location.x <= frame.minX + size
                    && location.y <= frame.maxY && location.y >= frame.maxY - size
            case "Top Right":
                return location.x <= frame.maxX && location.x >= frame.maxX - size
                    && location.y <= frame.maxY && location.y >= frame.maxY - size
            case "Bottom Left":
                return location.x >= frame.minX && location.x <= frame.minX + size
                    && location.y >= frame.minY && location.y <= frame.minY + size
            case "Bottom Right":
                return location.x <= frame.maxX && location.x >= frame.maxX - size
                    && location.y >= frame.minY && location.y <= frame.minY + size
            default:
                return false
            }
        }
    }
}
