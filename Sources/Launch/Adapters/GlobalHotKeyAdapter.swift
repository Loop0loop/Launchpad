import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyAdapter {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var actions: [UInt32: @MainActor () -> Void] = [:]

    func start(
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
        let f4Registered = register(
            id: LaunchConstants.HotKey.f4ID,
            LaunchConstants.HotKey.f4KeyCode,
            modifiers: LaunchConstants.HotKey.f4Modifiers,
            action: f4Action
        )

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
