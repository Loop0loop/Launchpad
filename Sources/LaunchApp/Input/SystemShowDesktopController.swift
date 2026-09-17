import AppKit
import ApplicationServices
import Darwin
import LaunchAppPrivateSupport
import LaunchpadCore

@MainActor
final class SystemShowDesktopController {
    private typealias ShowDesktopCallback = @convention(c) (UInt32, UnsafeMutableRawPointer?) -> Void
    private typealias SetShowDesktopCallback = @convention(c) (ShowDesktopCallback?) -> Void
    private typealias SendNotification = @convention(c) (CFString, Int32) -> Int32

    private static let showNotification = "AXExposeShowDesktop" as CFString
    private static let exitNotification = "AXExposeExit" as CFString
    private static let toggleNotification = "com.apple.showdesktop.awake" as CFString
    nonisolated private static let windowManagerOwner = "WindowManager"
    nonisolated private static let showDesktopOverlay = "ShowDesktopOverlay"
    nonisolated private static let showDesktopLayer = 18
    nonisolated(unsafe) private static weak var current: SystemShowDesktopController?
    private static let coreDockCallback: ShowDesktopCallback = { state, _ in
        DispatchQueue.main.async {
            MainActor.assumeIsolated { SystemShowDesktopController.current?.applyDockState(state) }
        }
    }

    private var handle: UnsafeMutableRawPointer?
    private var setCallback: SetShowDesktopCallback?
    private var sendNotification: SendNotification?
    private var observer: AXObserver?
    private var dock: AXUIElement?
    private var dockRestartObserver: NSObjectProtocol?
    private var onVisibilityChange: ((SystemDesktopVisibility) -> Void)?
    private let gestureOutputQueue = DispatchQueue(
        label: "com.launchpad.show-desktop-output",
        qos: .userInteractive
    )
    private var gestureStartActive: Bool?
    private var didPostGestureBegin = false
    private(set) var visibility = SystemDesktopVisibility.unknown
    var isActive: Bool { visibility == .desktopVisible }
    private(set) var isSupported = false
    private(set) var supportsContinuousGesture = false

    @discardableResult
    func prepare() -> Bool {
        guard !isSupported else { return true }
        supportsContinuousGesture = LaunchDockSwipePrepare()
        handle = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_NOW
        )
        guard let handle,
              let callbackSymbol = dlsym(handle, "CoreDockSetShowDesktopCallback"),
              let notificationSymbol = dlsym(handle, "CoreDockSendNotification") else {
            LaunchLog.line("system show desktop control unavailable")
            return false
        }
        setCallback = unsafeBitCast(callbackSymbol, to: SetShowDesktopCallback.self)
        sendNotification = unsafeBitCast(notificationSymbol, to: SendNotification.self)
        isSupported = true
        return true
    }

    @discardableResult
    func handleGesture(_ update: SystemShowDesktopGestureUpdate) -> Bool {
        let progress: Double
        let velocity: Double
        let phase: UInt32
        switch update {
        case .began(let value):
            guard refreshVisibility() != .unknown else { return false }
            didPostGestureBegin = false
            gestureStartActive = isActive
            progress = value
            velocity = 0
            // A zero-distance begin has no direction. Start Dock on the first movement.
            return true
        case .changed(let value):
            progress = value
            velocity = 0
            guard gestureStartActive != nil, value != 0 || didPostGestureBegin else { return true }
            phase = didPostGestureBegin ? 2 : 1
        case .ended(let value, let releaseVelocity):
            progress = value
            velocity = gestureStartActive == false
                ? min(releaseVelocity, LaunchConstants.Multitouch.maximumShowDesktopReleaseVelocity)
                : releaseVelocity
            phase = 4
        case .cancelled(let value, let releaseVelocity):
            progress = value
            velocity = releaseVelocity
            phase = 8
        }
        guard supportsContinuousGesture else {
            if case .ended = update {
                guard abs(progress) >= 0.42 else { return true }
                return setDesktopVisible(progress > 0)
            }
            return false
        }
        if phase == 4 || phase == 8, !didPostGestureBegin {
            gestureStartActive = nil
            return true
        }
        let posted = gestureOutputQueue.sync {
            LaunchDockSwipePost(progress, velocity, phase)
        }
        if posted {
            switch update {
            case .ended:
                gestureStartActive = nil
                didPostGestureBegin = false
                LaunchLog.line(
                    "trackpad continuous show desktop ended progress=\(progress) velocity=\(velocity) awaitingObservedState=true"
                )
            case .cancelled:
                gestureStartActive = nil
                didPostGestureBegin = false
            case .began, .changed:
                didPostGestureBegin = true
            }
        }
        return posted
    }

    func start(onVisibilityChange: @escaping (SystemDesktopVisibility) -> Void) {
        self.onVisibilityChange = onVisibilityChange
        if prepare() {
            Self.current = self
            setCallback?(Self.coreDockCallback)
            LaunchLog.line("system show desktop control ready")
        }
        if dockRestartObserver == nil {
            dockRestartObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("NSApplicationDockDidRestartNotification"),
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshObservation() }
            }
        }
        refreshObservation()
    }

    func refreshObservation() {
        disconnect()
        refreshVisibility()
        guard AXIsProcessTrusted() else {
            LaunchLog.line("native desktop observation needs Accessibility permission")
            return
        }
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else { return }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        var created: AXObserver?
        let status = AXObserverCreate(application.processIdentifier, Self.callback, &created)
        guard status == .success, let created else {
            LaunchLog.line("native desktop observer creation failed=\(status.rawValue)")
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        let show = AXObserverAddNotification(created, element, Self.showNotification, context)
        let exit = AXObserverAddNotification(created, element, Self.exitNotification, context)
        guard show == .success, exit == .success else {
            AXObserverRemoveNotification(created, element, Self.showNotification)
            AXObserverRemoveNotification(created, element, Self.exitNotification)
            LaunchLog.line("native desktop notifications unavailable show=\(show.rawValue) exit=\(exit.rawValue)")
            return
        }
        dock = element
        observer = created
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        LaunchLog.line("native desktop AX observer ready pid=\(application.processIdentifier)")
    }

    @discardableResult
    func setDesktopVisible(_ visible: Bool) -> Bool {
        guard refreshVisibility() != .unknown else { return false }
        guard visible != isActive, let sendNotification else { return visible == isActive }
        let status = sendNotification(Self.toggleNotification, 0)
        guard status == 0 else {
            LaunchLog.line("system show desktop toggle failed status=\(status)")
            return false
        }
        setActive(visible)
        return true
    }

    func stop() {
        setCallback?(nil)
        if Self.current === self { Self.current = nil }
        if let dockRestartObserver { NotificationCenter.default.removeObserver(dockRestartObserver) }
        dockRestartObserver = nil
        disconnect()
        onVisibilityChange = nil
        gestureStartActive = nil
        visibility = .unknown
    }

    private func disconnect() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        if let dock {
            AXObserverRemoveNotification(observer, dock, Self.showNotification)
            AXObserverRemoveNotification(observer, dock, Self.exitNotification)
        }
        self.observer = nil
        dock = nil
    }

    private static let callback: AXObserverCallback = { observer, _, notification, context in
        guard let context else { return }
        let controller = Unmanaged<SystemShowDesktopController>.fromOpaque(context).takeUnretainedValue()
        let observerID = UInt(bitPattern: Unmanaged.passUnretained(observer).toOpaque())
        let name = notification as String
        // The observer's run-loop source is installed on the main run loop only.
        MainActor.assumeIsolated {
            guard let current = controller.observer,
                  UInt(bitPattern: Unmanaged.passUnretained(current).toOpaque()) == observerID else { return }
            let active = name == showNotification as String
            guard active || name == exitNotification as String else { return }
            LaunchLog.line("native desktop notification=\(name) active=\(active)")
            controller.setActive(active)
        }
    }

    private func applyDockState(_ state: UInt32) {
        LaunchLog.line("system show desktop observed Dock state=\(state)")
        switch state {
        case 1: setActive(true)
        case 2: setActive(false)
        default: LaunchLog.line("system show desktop unknown state=\(state)")
        }
    }

    private func setActive(_ active: Bool) {
        setVisibility(active ? .desktopVisible : .windowsVisible)
    }

    @discardableResult
    func refreshVisibility() -> SystemDesktopVisibility {
        setVisibility(Self.currentVisibility())
        return visibility
    }

    nonisolated static func currentVisibility() -> SystemDesktopVisibility {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return .unknown }
        let desktopVisible = windows.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == windowManagerOwner else { return false }
            return window[kCGWindowName as String] as? String == showDesktopOverlay
                || window[kCGWindowLayer as String] as? Int == showDesktopLayer
        }
        return desktopVisible ? .desktopVisible : .windowsVisible
    }

    private func setVisibility(_ visibility: SystemDesktopVisibility) {
        guard self.visibility != visibility else { return }
        self.visibility = visibility
        LaunchLog.line("system desktop visibility=\(visibility)")
        onVisibilityChange?(visibility)
    }

}
