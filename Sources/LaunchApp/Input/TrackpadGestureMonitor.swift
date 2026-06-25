import AppKit
import Darwin
import LaunchpadCore

@MainActor
final class TrackpadGestureMonitor {
    private var monitors: [Any] = []
    private let pinchMonitor = PinchContactMonitor()
    private var lastScrollIntentTime: TimeInterval = 0
    private var lastPinchIntentTime: TimeInterval = 0
    private var isScrollLocked = false
    private var scrollUnlockTask: Task<Void, Never>?

    func start(
        onGateStatus: @escaping @MainActor (Bool) -> Void,
        onIntent: @escaping @MainActor (TrackpadIntent) -> Void
    ) {
        guard monitors.isEmpty else {
            onGateStatus(pinchMonitor.isReady)
            return
        }
        LaunchLog.line("trackpad monitor start")
        pinchMonitor.start { intent in
            let now = Date().timeIntervalSinceReferenceDate
            guard now - self.lastPinchIntentTime >= LaunchConstants.Multitouch.triggerCooldown else { return }
            self.lastPinchIntentTime = now
            onIntent(intent)
        }
        onGateStatus(pinchMonitor.isReady)
        LaunchLog.line("private pinch ready=\(pinchMonitor.isReady)")

        let localMask: NSEvent.EventTypeMask = pinchMonitor.isReady ? [.swipe, .scrollWheel] : [.magnify, .swipe, .scrollWheel]
        let handler: (NSEvent) -> Void = { event in
            Task { @MainActor in
                if event.type == .magnify, let intent = TrackpadIntent.pinch(magnification: event.magnification) {
                    LaunchLog.line("magnify event magnification=\(event.magnification) intent=\(intent) privateReady=\(self.pinchMonitor.isReady)")
                    if !self.pinchMonitor.isReady {
                        // ponytail: fallback keeps pinch usable when private MultitouchSupport is unavailable.
                        onIntent(intent)
                    }
                } else if event.type == .swipe {
                    guard !self.pinchMonitor.hasRecentQualifiedTouch else { return }
                    if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                        self.isScrollLocked = false
                        self.scrollUnlockTask?.cancel()
                        return
                    }
                    if event.phase.contains(.began) {
                        self.isScrollLocked = false
                        self.scrollUnlockTask?.cancel()
                    }
                    if self.isScrollLocked { return }
                    
                    if let intent = TrackpadIntent.horizontalSwipe(deltaX: event.deltaX) {
                        self.isScrollLocked = true
                        self.unlockScrollAfter(0.8)
                        onIntent(intent)
                    }
                } else if event.type == .scrollWheel {
                    guard !self.pinchMonitor.hasRecentQualifiedTouch else { return }
                    let hasPhase = !event.phase.isEmpty || !event.momentumPhase.isEmpty
                    if hasPhase {
                        let isEnded = event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.momentumPhase.contains(.ended)
                        if isEnded {
                            self.isScrollLocked = false
                            self.scrollUnlockTask?.cancel()
                            return
                        }
                        if event.phase.contains(.began) {
                            self.isScrollLocked = false
                            self.scrollUnlockTask?.cancel()
                        }
                    }
                    
                    if self.isScrollLocked {
                        return
                    }
                    
                    if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                       let intent = TrackpadIntent.horizontalScroll(deltaX: event.scrollingDeltaX) {
                            let now = event.timestamp
                            let timeDiff = now - self.lastScrollIntentTime
                            let minInterval = hasPhase ? 0.1 : 0.7
                            
                            if timeDiff > minInterval {
                                self.lastScrollIntentTime = now
                                self.isScrollLocked = true
                                if !hasPhase {
                                    self.unlockScrollAfter(0.8)
                                }
                                onIntent(intent)
                            }
                    }
                }
            }
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: localMask, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
            LaunchLog.line("local trackpad monitor installed")
        }

    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        lastScrollIntentTime = 0
        lastPinchIntentTime = 0
        isScrollLocked = false
        scrollUnlockTask?.cancel()
        scrollUnlockTask = nil
        pinchMonitor.stop()
    }

    private func unlockScrollAfter(_ interval: TimeInterval) {
        scrollUnlockTask?.cancel()
        scrollUnlockTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                try Task.checkCancellation()
            } catch {
                return
            }
            await MainActor.run {
                self?.isScrollLocked = false
            }
        }
    }
}

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

    private let lock = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private var devices: [MTDeviceRef] = []
    private var initialRadius: Double?
    private var lastIntentTime: Double = 0
    private var lastQualifiedTouchTime: TimeInterval = 0
    private var onPinch: (@MainActor (TrackpadIntent) -> Void)?
    nonisolated(unsafe) fileprivate static var current: PinchContactMonitor?

    private var _isReady = false
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isReady
    }

    func start(onPinch: @escaping @MainActor (TrackpadIntent) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.onPinch = onPinch
        guard !_isReady else { return }
        handle = dlopen(LaunchConstants.Multitouch.frameworkPath, RTLD_NOW)
        guard let handle,
              let createListSymbol = dlsym(handle, LaunchConstants.Multitouch.createListSymbol),
              let registerSymbol = dlsym(handle, LaunchConstants.Multitouch.registerContactFrameCallbackSymbol),
              let startSymbol = dlsym(handle, LaunchConstants.Multitouch.deviceStartSymbol) else {
            LaunchLog.line("private multitouch unavailable")
            return
        }

        let createList = unsafeBitCast(createListSymbol, to: MTDeviceCreateList.self)
        let register = unsafeBitCast(registerSymbol, to: MTRegisterContactFrameCallback.self)
        let startDevice = unsafeBitCast(startSymbol, to: MTDeviceStart.self)
        let deviceList = createList().takeRetainedValue()

        PinchContactMonitor.current = self
        for index in 0..<CFArrayGetCount(deviceList) {
            guard let rawDevice = CFArrayGetValueAtIndex(deviceList, index) else { continue }
            let device = OpaquePointer(rawDevice)
            devices.append(device)
            register(device, contactCallback)
            startDevice(device, 0)
        }

        _isReady = !devices.isEmpty
        LaunchLog.line("private multitouch devices=\(devices.count)")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        onPinch = nil
        initialRadius = nil
        lastIntentTime = 0
        lastQualifiedTouchTime = 0
    }

    var hasRecentQualifiedTouch: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSinceReferenceDate - lastQualifiedTouchTime < 0.45
    }

    fileprivate func process(touches: [TouchPoint], timestamp: Double) {
        lock.lock()
        defer { lock.unlock() }

        let requiredCount = LaunchConstants.Multitouch.gestureFingerCount
        guard touches.count >= requiredCount else {
            initialRadius = nil
            return
        }
        lastQualifiedTouchTime = Date().timeIntervalSinceReferenceDate

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

        let callback = onPinch
        Task { @MainActor in
            callback?(intent)
        }
    }
}

private let contactCallback: PinchContactMonitor.ContactCallback = { _, touchesRawPointer, contactCount, timestamp, _ in
    guard let touchesRawPointer, contactCount > 0 else {
        PinchContactMonitor.current?.process(touches: [], timestamp: timestamp)
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

    PinchContactMonitor.current?.process(touches: touches, timestamp: timestamp)
    return 0
}
