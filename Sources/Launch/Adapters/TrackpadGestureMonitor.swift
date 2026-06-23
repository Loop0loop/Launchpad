import AppKit
import Darwin
import LaunchCore

@MainActor
final class TrackpadGestureMonitor {
    private var monitors: [Any] = []
    private let fourFingerMonitor = FourFingerContactMonitor()
    private var lastScrollIntentTime: TimeInterval = 0

    func start(
        onGateStatus: @escaping @MainActor (Bool) -> Void,
        onIntent: @escaping @MainActor (TrackpadIntent) -> Void
    ) {
        fourFingerMonitor.start()
        onGateStatus(fourFingerMonitor.isReady)

        let mask: NSEvent.EventTypeMask = [.magnify, .swipe, .scrollWheel]

        let handler: (NSEvent) -> Void = { event in
            Task { @MainActor in
                if event.type == .magnify, let intent = TrackpadIntent.pinch(magnification: event.magnification) {
                    if self.fourFingerMonitor.isReady {
                        let allowed = TrackpadIntent.isRecentFourFingerFrame(
                            eventTime: event.timestamp,
                            lastFourFingerTime: self.fourFingerMonitor.lastFourFingerTime
                        )
                        if allowed { onIntent(intent) }
                    } else {
                        // ponytail: fallback keeps pinch usable when private MultitouchSupport is unavailable.
                        onIntent(intent)
                    }
                } else if event.type == .swipe, let intent = TrackpadIntent.horizontalSwipe(deltaX: event.deltaX) {
                    onIntent(intent)
                } else if event.type == .scrollWheel,
                          abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                          let intent = TrackpadIntent.horizontalScroll(deltaX: event.scrollingDeltaX),
                          TrackpadIntent.shouldAcceptScrollIntent(
                            eventTime: event.timestamp,
                            lastIntentTime: self.lastScrollIntentTime
                          ) {
                    self.lastScrollIntentTime = event.timestamp
                    onIntent(intent)
                }
            }
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(global)
        }
    }
}

@MainActor
final class FourFingerContactMonitor {
    typealias MTDeviceRef = OpaquePointer
    typealias MTDeviceCreateList = @convention(c) () -> Unmanaged<CFArray>
    typealias MTRegisterContactFrameCallback = @convention(c) (MTDeviceRef, ContactCallback) -> Void
    typealias MTDeviceStart = @convention(c) (MTDeviceRef, Int32) -> Void
    typealias ContactCallback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var devices: [MTDeviceRef] = []
    fileprivate static weak var current: FourFingerContactMonitor?

    private(set) var isReady = false
    private(set) var lastFourFingerTime: Double?

    func start() {
        guard !isReady else { return }
        handle = dlopen(LaunchConstants.Multitouch.frameworkPath, RTLD_NOW)
        guard let handle,
              let createListSymbol = dlsym(handle, LaunchConstants.Multitouch.createListSymbol),
              let registerSymbol = dlsym(handle, LaunchConstants.Multitouch.registerContactFrameCallbackSymbol),
              let startSymbol = dlsym(handle, LaunchConstants.Multitouch.deviceStartSymbol) else { return }

        let createList = unsafeBitCast(createListSymbol, to: MTDeviceCreateList.self)
        let register = unsafeBitCast(registerSymbol, to: MTRegisterContactFrameCallback.self)
        let startDevice = unsafeBitCast(startSymbol, to: MTDeviceStart.self)
        let deviceList = createList().takeRetainedValue()

        Self.current = self
        for index in 0..<CFArrayGetCount(deviceList) {
            guard let rawDevice = CFArrayGetValueAtIndex(deviceList, index) else { continue }
            let device = OpaquePointer(rawDevice)
            devices.append(device)
            register(device, contactCallback)
            startDevice(device, 0)
        }

        isReady = !devices.isEmpty
    }

    fileprivate func sawContactFrame(count: Int32, timestamp: Double) {
        guard count == LaunchConstants.Multitouch.fourFingerCount else { return }
        lastFourFingerTime = timestamp
    }
}

private let contactCallback: FourFingerContactMonitor.ContactCallback = { _, _, contactCount, timestamp, _ in
    Task { @MainActor in
        FourFingerContactMonitor.current?.sawContactFrame(count: contactCount, timestamp: timestamp)
    }
    return 0
}
