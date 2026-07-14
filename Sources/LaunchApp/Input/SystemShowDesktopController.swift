import Darwin
import Foundation

@MainActor
final class SystemShowDesktopController {
    private typealias ShowDesktopCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Void
    private typealias SetShowDesktopCallback = @convention(c) (ShowDesktopCallback?) -> Void
    private typealias SendNotification = @convention(c) (CFString, Int32) -> Int32

    private static let notification = "com.apple.showdesktop.awake" as CFString
    nonisolated(unsafe) private static weak var current: SystemShowDesktopController?
    private static let callback: ShowDesktopCallback = { state, _ in
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                SystemShowDesktopController.current?.applyDockState(state)
            }
        }
    }

    private var handle: UnsafeMutableRawPointer?
    private var setCallback: SetShowDesktopCallback?
    private var sendNotification: SendNotification?
    private var onActiveChange: ((Bool) -> Void)?

    private(set) var isActive = false
    private(set) var isSupported = false

    func prepare() -> Bool {
        guard !isSupported else { return true }
        handle = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_NOW
        )
        guard let handle,
              let callbackSymbol = dlsym(handle, "CoreDockSetShowDesktopCallback"),
              let notificationSymbol = dlsym(handle, "CoreDockSendNotification") else {
            LaunchLog.line("system show desktop controller unavailable")
            return false
        }
        setCallback = unsafeBitCast(callbackSymbol, to: SetShowDesktopCallback.self)
        sendNotification = unsafeBitCast(notificationSymbol, to: SendNotification.self)
        isSupported = true
        return true
    }

    func start(onActiveChange: @escaping (Bool) -> Void) {
        guard prepare() else { return }
        self.onActiveChange = onActiveChange
        Self.current = self
        setCallback?(Self.callback)
        LaunchLog.line("system show desktop controller ready")
    }

    @discardableResult
    func toggle() -> Bool {
        guard let sendNotification else { return false }
        let status = sendNotification(Self.notification, 0)
        guard status == 0 else {
            LaunchLog.line("system show desktop toggle failed status=\(status)")
            return false
        }
        setActive(!isActive)
        return true
    }

    func stop() {
        setCallback?(nil)
        if Self.current === self { Self.current = nil }
        onActiveChange = nil
        isActive = false
    }

    private func applyDockState(_ state: UInt32) {
        switch state {
        case 1:
            setActive(true)
        case 2:
            setActive(false)
        default:
            LaunchLog.line("system show desktop unknown state=\(state)")
        }
    }

    private func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        LaunchLog.line("system show desktop active=\(active)")
        onActiveChange?(active)
    }
}
