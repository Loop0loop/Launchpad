import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalHotKeyAdapter {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var action: (@MainActor () -> Void)?
    private let hotKeyID = EventHotKeyID(
        signature: LaunchConstants.HotKey.signature,
        id: LaunchConstants.HotKey.toggleID
    )

    func start(action: @escaping @MainActor () -> Void) -> Bool {
        stop()
        self.action = action

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
            return false
        }

        var nextHotKeyRef: EventHotKeyRef?
        guard RegisterEventHotKey(
            LaunchConstants.HotKey.toggleKeyCode,
            LaunchConstants.HotKey.toggleModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &nextHotKeyRef
        ) == noErr else {
            stop()
            return false
        }

        hotKeyRef = nextHotKeyRef
        return true
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        action = nil
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
              hotKeyID.signature == adapter.hotKeyID.signature,
              hotKeyID.id == adapter.hotKeyID.id else { return noErr }

        Task { @MainActor in
            adapter.action?()
        }
        return noErr
    }
}
