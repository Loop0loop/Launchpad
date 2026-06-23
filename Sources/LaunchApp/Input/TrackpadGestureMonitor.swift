import AppKit
import Darwin
import LaunchCore

@MainActor
final class TrackpadGestureMonitor {
    private var monitors: [Any] = []
    private let pinchMonitor = PinchContactMonitor()
    private var lastScrollIntentTime: TimeInterval = 0

    func start(
        onGateStatus: @escaping @MainActor (Bool) -> Void,
        onIntent: @escaping @MainActor (TrackpadIntent) -> Void
    ) {
        pinchMonitor.start { intent in
            onIntent(intent)
        }
        onGateStatus(pinchMonitor.isReady)

        let mask: NSEvent.EventTypeMask = [.magnify, .swipe, .scrollWheel]

        let handler: (NSEvent) -> Void = { event in
            Task { @MainActor in
                if event.type == .magnify, let intent = TrackpadIntent.pinch(magnification: event.magnification) {
                    if !self.pinchMonitor.isReady {
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
final class PinchContactMonitor {
    fileprivate struct MTPoint {
        var x: Float
        var y: Float
    }

    fileprivate struct MTVector {
        var position: MTPoint
        var velocity: MTPoint
    }

    fileprivate struct MTTouch {
        var frame: Int32
        var timestamp: Double
        var pathIndex: Int32
        var state: UInt32
        var fingerID: Int32
        var handID: Int32
        var normalizedVector: MTVector
        var zTotal: Float
        var field9: Int32
        var angle: Float
        var majorAxis: Float
        var minorAxis: Float
        var absoluteVector: MTVector
        var field14: Int32
        var field15: Int32
        var zDensity: Float
    }

    fileprivate struct TouchPoint {
        let id: Int32
        let x: Double
        let y: Double
    }

    typealias MTDeviceRef = OpaquePointer
    typealias MTDeviceCreateList = @convention(c) () -> Unmanaged<CFArray>
    typealias MTRegisterContactFrameCallback = @convention(c) (MTDeviceRef, ContactCallback) -> Void
    typealias MTDeviceStart = @convention(c) (MTDeviceRef, Int32) -> Void
    typealias ContactCallback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var devices: [MTDeviceRef] = []
    private var initialRadius: Double?
    private var lastIntentTime: Double = 0
    private var onPinch: (@MainActor (TrackpadIntent) -> Void)?
    fileprivate static weak var current: PinchContactMonitor?

    private(set) var isReady = false

    func start(onPinch: @escaping @MainActor (TrackpadIntent) -> Void) {
        guard !isReady else { return }
        self.onPinch = onPinch
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

    fileprivate func process(touches: [TouchPoint], timestamp: Double) {
        let requiredCount = LaunchConstants.Multitouch.gestureFingerCount
        guard touches.count >= requiredCount else {
            initialRadius = nil
            return
        }

        let selected = Array(touches.sorted { $0.id < $1.id }.prefix(requiredCount))
        let centerX = selected.map(\.x).reduce(0, +) / Double(selected.count)
        let centerY = selected.map(\.y).reduce(0, +) / Double(selected.count)
        let radius = selected.reduce(0) { total, touch in
            total + hypot(touch.x - centerX, touch.y - centerY)
        } / Double(selected.count)

        guard let initialRadius, initialRadius > 0 else {
            self.initialRadius = radius
            return
        }

        guard timestamp - lastIntentTime >= LaunchConstants.Multitouch.triggerCooldown,
              let intent = TrackpadIntent.pinchRadius(
                ratio: radius / initialRadius,
                pinchInThreshold: LaunchConstants.Multitouch.pinchInRatio,
                pinchOutThreshold: LaunchConstants.Multitouch.pinchOutRatio
              ) else { return }

        lastIntentTime = timestamp
        self.initialRadius = radius
        onPinch?(intent)
    }
}

private let contactCallback: PinchContactMonitor.ContactCallback = { _, touchesRawPointer, contactCount, timestamp, _ in
    guard let touchesRawPointer, contactCount > 0 else {
        Task { @MainActor in
            PinchContactMonitor.current?.process(touches: [], timestamp: timestamp)
        }
        return 0
    }

    let touchesPointer = UnsafePointer(touchesRawPointer.bindMemory(to: PinchContactMonitor.MTTouch.self, capacity: Int(contactCount)))
    let touches = UnsafeBufferPointer(start: touchesPointer, count: Int(contactCount)).map { touch in
        PinchContactMonitor.TouchPoint(
            id: touch.fingerID,
            x: Double(touch.normalizedVector.position.x),
            y: Double(touch.normalizedVector.position.y)
        )
    }

    Task { @MainActor in
        PinchContactMonitor.current?.process(touches: touches, timestamp: timestamp)
    }
    return 0
}
