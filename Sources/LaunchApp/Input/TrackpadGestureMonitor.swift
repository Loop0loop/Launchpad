import AppKit
import Darwin
import LaunchpadCore

@MainActor
final class TrackpadGestureMonitor {
    private var monitors: [Any] = []
    private let pinchMonitor = PinchContactMonitor()
    private var scrollSession = TrackpadGestureSession()
    private var lastPinchIntentTime: TimeInterval = 0

    func start(
        requiredFingerCounts: [Int],
        preservesSystemShowDesktop: Bool,
        controlsSystemShowDesktop: Bool,
        onGateStatus: @escaping @MainActor (Bool) -> Void,
        onIntent: @escaping @MainActor (TrackpadIntent) -> Void,
        onPinchUpdate: (@MainActor (TrackpadPinchUpdate) -> Void)? = nil,
        onSystemShowDesktop: @escaping @MainActor (SystemShowDesktopGestureDecision) -> Void
    ) {
        pinchMonitor.requiredFingerCounts = requiredFingerCounts
        pinchMonitor.preservesSystemShowDesktop = preservesSystemShowDesktop
        pinchMonitor.controlsSystemShowDesktop = controlsSystemShowDesktop
        guard monitors.isEmpty else {
            onGateStatus(pinchMonitor.isReady)
            return
        }
        LaunchLog.line("trackpad monitor start")
        pinchMonitor.start(
            onPinchUpdate: { update in
                if let onPinchUpdate {
                    onPinchUpdate(update)
                    return
                }
                if case .commit(let intent) = update {
                    let now = Date().timeIntervalSinceReferenceDate
                    guard now - self.lastPinchIntentTime >= LaunchConstants.Multitouch.lifecycleBounceCooldown else { return }
                    self.lastPinchIntentTime = now
                    onIntent(intent)
                }
            },
            onSystemShowDesktop: onSystemShowDesktop
        )
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
                        return
                    }
                    
                    if let intent = TrackpadIntent.horizontalSwipe(deltaX: event.deltaX) {
                        onIntent(intent)
                    }
                } else if event.type == .scrollWheel {
                    guard !self.pinchMonitor.hasRecentQualifiedTouch else { return }
                    let hasPhase = !event.phase.isEmpty || !event.momentumPhase.isEmpty
                    let isEnded = event.phase.contains(.ended)
                        || event.phase.contains(.cancelled)
                        || event.momentumPhase.contains(.ended)
                    guard let intent = self.scrollSession.updateHorizontalScroll(
                        deltaX: Double(event.scrollingDeltaX),
                        deltaY: Double(event.scrollingDeltaY),
                        ended: hasPhase && isEnded
                    ) else { return }
                    onIntent(intent)
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
        lastPinchIntentTime = 0
        scrollSession = TrackpadGestureSession()
        pinchMonitor.stop()
    }

    func yieldCurrentGestureToSystem() {
        pinchMonitor.yieldCurrentGestureToSystem()
    }

    func setSystemShowDesktopActive(_ active: Bool) {
        pinchMonitor.systemShowDesktopActive = active
    }

    func setLauncherVisible(_ visible: Bool) {
        pinchMonitor.launcherVisible = visible
    }
}

final class PinchContactMonitor: @unchecked Sendable {
    private struct DeviceGestureState {
        var gestureSession = TrackpadGestureSession()
        var contactGate = TrackpadContactGate()
        var baselineTouches: [TrackpadTouchSample]?
        var intentArbiter: TrackpadGestureIntentArbiter?
        var showDesktopOwner: SystemShowDesktopGestureOwner?
        var filteredScaleRatio: Double?
        var lastScaleTimestamp: Double?
    }

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

    typealias MTDeviceRef = OpaquePointer
    typealias MTDeviceCreateList = @convention(c) () -> Unmanaged<CFArray>
    typealias MTRegisterContactFrameCallback = @convention(c) (MTDeviceRef, ContactCallback) -> Void
    typealias MTDeviceStart = @convention(c) (MTDeviceRef, Int32) -> Int32
    typealias ContactCallback = @convention(c) (
        MTDeviceRef,
        UnsafeMutableRawPointer?,
        Int32,
        Double,
        Int32
    ) -> Void

    private let lock = NSLock()
    private var handle: UnsafeMutableRawPointer?
    private var devices: [MTDeviceRef] = []
    private var deviceStates: [UInt: DeviceGestureState] = [:]
    private var activeDeviceID: UInt?
    private var lastQualifiedTouchTime: TimeInterval = 0
    private var onPinchUpdate: (@MainActor (TrackpadPinchUpdate) -> Void)?
    private var onSystemShowDesktop: (@MainActor (SystemShowDesktopGestureDecision) -> Void)?
    private var pendingTrackingUpdate: TrackpadPinchUpdate?
    private var pendingTerminalUpdate: TrackpadPinchUpdate?
    private var deliveryScheduled = false
    private let diagnosticsEnabled = ProcessInfo.processInfo.environment["LAUNCH_TRACKPAD_DIAGNOSTICS"] == "1"
    private var lastDiagnosticFrameTime: TimeInterval = 0
    private var lastDiagnosticFrameSignature = ""
    private var lastDiagnosticDeliveryTime: TimeInterval = 0
    private var systemShowDesktopGestureState = SystemShowDesktopGestureState()
    nonisolated(unsafe) fileprivate static var current: PinchContactMonitor?
    private var _requiredFingerCounts = [LaunchConstants.Multitouch.defaultGestureFingerCount]
    private var _preservesSystemShowDesktop = false
    private var _controlsSystemShowDesktop = false
    private var _systemShowDesktopActive = false
    private var _launcherVisible = false
    var requiredFingerCounts: [Int] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _requiredFingerCounts
        }
        set {
            lock.lock()
            _requiredFingerCounts = newValue
            lock.unlock()
        }
    }

    var preservesSystemShowDesktop: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _preservesSystemShowDesktop
        }
        set {
            lock.lock()
            _preservesSystemShowDesktop = newValue
            if !newValue { systemShowDesktopGestureState.reset() }
            lock.unlock()
        }
    }

    var controlsSystemShowDesktop: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _controlsSystemShowDesktop
        }
        set {
            lock.lock()
            _controlsSystemShowDesktop = newValue
            lock.unlock()
        }
    }

    var systemShowDesktopActive: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _systemShowDesktopActive
        }
        set {
            lock.lock()
            _systemShowDesktopActive = newValue
            lock.unlock()
        }
    }

    var launcherVisible: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _launcherVisible
        }
        set {
            lock.lock()
            _launcherVisible = newValue
            lock.unlock()
        }
    }

    private var _isReady = false
    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isReady
    }

    func start(
        onPinchUpdate: @escaping @MainActor (TrackpadPinchUpdate) -> Void,
        onSystemShowDesktop: @escaping @MainActor (SystemShowDesktopGestureDecision) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.onPinchUpdate = onPinchUpdate
        self.onSystemShowDesktop = onSystemShowDesktop
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
            _ = startDevice(device, 0)
        }

        _isReady = !devices.isEmpty
        LaunchLog.line("private multitouch devices=\(devices.count)")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        onPinchUpdate = nil
        onSystemShowDesktop = nil
        deviceStates = [:]
        activeDeviceID = nil
        lastQualifiedTouchTime = 0
        pendingTrackingUpdate = nil
        pendingTerminalUpdate = nil
        deliveryScheduled = false
        systemShowDesktopGestureState.reset()
        _systemShowDesktopActive = false
    }

    var hasRecentQualifiedTouch: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSinceReferenceDate - lastQualifiedTouchTime < 0.45
    }

    fileprivate func process(
        device: MTDeviceRef,
        touches: [TrackpadTouchSample],
        timestamp: Double
    ) {
        lock.lock()
        defer { lock.unlock() }

        let deviceID = UInt(bitPattern: device)
        var deviceState = deviceStates[deviceID] ?? DeviceGestureState()
        var observedFingerCounts = _requiredFingerCounts
        if _preservesSystemShowDesktop, !observedFingerCounts.contains(4) {
            observedFingerCounts.append(4)
        }
        let selected: [TrackpadTouchSample]
        switch deviceState.contactGate.update(
            touches: touches,
            requiredFingerCounts: observedFingerCounts,
            timestamp: timestamp
        ) {
        case .provisional(let touches), .qualified(let touches):
            guard activeDeviceID == nil || activeDeviceID == deviceID else {
                deviceStates[deviceID] = deviceState
                return
            }
            activeDeviceID = deviceID
            selected = touches
        case .ended:
            let ownership = deviceState.intentArbiter?.ownership
            let isLauncherOwned = ownership == .launcherRadialIn || ownership == .launcherRadialOut
            if ownership == .ignoredUntilLift {
                let owner = deviceState.showDesktopOwner ?? .undecided
                LaunchLog.line("trackpad session end owner=\(owner) reason=allTouchesLifted")
            } else if diagnosticsEnabled {
                LaunchLog.line("trackpad diagnostic gate=ended device=\(deviceID) ownership=\(String(describing: ownership))")
            }
            let update = activeDeviceID == deviceID && isLauncherOwned
                ? deviceState.gestureSession.trackPinch(radius: nil, timestamp: timestamp)
                : nil
            if activeDeviceID == deviceID { activeDeviceID = nil }
            deviceStates[deviceID] = DeviceGestureState()
            guard let update else { return }
            enqueuePinchUpdate(update)
            return
        case .rejected:
            let wasActiveDevice = activeDeviceID == deviceID
            let ownership = deviceState.intentArbiter?.ownership
            let isLauncherOwned = ownership == .launcherRadialIn || ownership == .launcherRadialOut
            if diagnosticsEnabled {
                LaunchLog.line("trackpad diagnostic gate=rejected device=\(deviceID) active=\(wasActiveDevice)")
            }
            let update = wasActiveDevice && isLauncherOwned
                ? deviceState.gestureSession.cancelPinch()
                : nil
            if wasActiveDevice {
                activeDeviceID = nil
                deviceState = DeviceGestureState()
            }
            deviceStates[deviceID] = deviceState
            guard let update else { return }
            enqueuePinchUpdate(update)
            return
        case .waiting:
            deviceStates[deviceID] = deviceState
            return
        }
        lastQualifiedTouchTime = Date().timeIntervalSinceReferenceDate

        let centerX = selected.map(\.x).reduce(0, +) / Double(selected.count)
        let centerY = selected.map(\.y).reduce(0, +) / Double(selected.count)
        if deviceState.baselineTouches == nil {
            deviceState.baselineTouches = selected
            deviceState.intentArbiter = TrackpadGestureIntentArbiter(
                baseline: selected,
                timestamp: timestamp
            )
            let showDesktopOwner = SystemShowDesktopGestureOwner(
                launcherIsVisible: _launcherVisible,
                systemShowDesktopIsActive: _systemShowDesktopActive
            )
            deviceState.showDesktopOwner = showDesktopOwner
            let launcherIntent = showDesktopOwner.launcherIntent.map { String(describing: $0) } ?? "none"
            LaunchLog.line("trackpad candidate fingers=\(selected.count) owner=\(showDesktopOwner) launcherIntent=\(launcherIntent)")
        }
        guard let baselineTouches = deviceState.baselineTouches,
              var intentArbiter = deviceState.intentArbiter,
              let rawRadius = TrackpadContactQuality.medianPairScaleRatio(
                baseline: baselineTouches,
                current: selected
              ) else { return }
        let radius = TrackpadContactQuality.lowPassScaleRatio(
            previous: deviceState.filteredScaleRatio,
            current: rawRadius,
            elapsed: timestamp - (deviceState.lastScaleTimestamp ?? timestamp),
            responseTime: LaunchConstants.Multitouch.scaleFilterResponse
        )
        deviceState.filteredScaleRatio = radius
        if deviceState.lastScaleTimestamp == nil || timestamp > (deviceState.lastScaleTimestamp ?? timestamp) {
            deviceState.lastScaleTimestamp = timestamp
        }

        let previousOwnership = intentArbiter.ownership
        let ownership = intentArbiter.update(current: selected, timestamp: timestamp)
        deviceState.intentArbiter = intentArbiter
        if previousOwnership == .undecided, ownership != .undecided {
            let radial = ownership == .launcherRadialIn ? "in" : "out"
            LaunchLog.line("trackpad radial=\(radial)")
        }
        let claimedIntent: TrackpadIntent?
        switch ownership {
        case .launcherRadialIn:
            claimedIntent = .open
        case .launcherRadialOut:
            claimedIntent = .close
        case .undecided, .ignoredUntilLift:
            claimedIntent = nil
        }
        if _controlsSystemShowDesktop, let claimedIntent {
            let decision = TrackpadIntent.systemShowDesktopDecision(
                fingerCount: selected.count,
                intent: claimedIntent,
                scaleRatio: radius,
                owner: deviceState.showDesktopOwner ?? .undecided,
                isEnabled: _preservesSystemShowDesktop
            )
            switch decision {
            case .launcher:
                break
            case .wait:
                deviceState.gestureSession = TrackpadGestureSession()
                deviceStates[deviceID] = deviceState
                return
            case .ignore:
                deviceState.intentArbiter?.ignoreUntilLift()
                deviceState.contactGate.ignoreUntilAllTouchesLift()
                deviceState.gestureSession = TrackpadGestureSession()
                deviceStates[deviceID] = deviceState
                return
            case .show, .restore:
                deviceState.intentArbiter?.ignoreUntilLift()
                deviceState.contactGate.ignoreUntilAllTouchesLift()
                deviceState.gestureSession = TrackpadGestureSession()
                deviceState.showDesktopOwner = .desktop
                deviceStates[deviceID] = deviceState
                LaunchLog.line("trackpad direct system show desktop action=\(decision) fingers=4")
                let callback = onSystemShowDesktop
                Task { @MainActor in callback?(decision) }
                return
            }
        } else if deviceState.showDesktopOwner != .launcher,
                  let claimedIntent,
                  systemShowDesktopGestureState.shouldYield(
            fingerCount: selected.count,
            intent: claimedIntent,
            systemGestureEnabled: _preservesSystemShowDesktop
        ) {
            deviceState.intentArbiter?.ignoreUntilLift()
            deviceState.contactGate.ignoreUntilAllTouchesLift()
            deviceState.gestureSession = TrackpadGestureSession()
            deviceStates[deviceID] = deviceState
            let phase = claimedIntent == .close ? "show" : "return"
            LaunchLog.line("trackpad system show desktop \(phase) fingers=4")
            let callback = onSystemShowDesktop
            let action: SystemShowDesktopGestureDecision = claimedIntent == .close ? .show : .restore
            Task { @MainActor in callback?(action) }
            return
        }
        if ownership != .undecided, !_requiredFingerCounts.contains(selected.count) {
            deviceState.intentArbiter?.ignoreUntilLift()
            deviceState.gestureSession = TrackpadGestureSession()
            deviceStates[deviceID] = deviceState
            return
        }
        switch ownership {
        case .undecided:
            _ = deviceState.gestureSession.trackPinch(
                radius: radius,
                centerX: centerX,
                centerY: centerY,
                timestamp: timestamp
            )
            deviceStates[deviceID] = deviceState
            return
        case .ignoredUntilLift:
            deviceStates[deviceID] = deviceState
            return
        case .launcherRadialIn, .launcherRadialOut:
            deviceState.contactGate.claim()
        }

        guard let lockedIntent = deviceState.showDesktopOwner?.launcherIntent else {
            deviceState.intentArbiter?.ignoreUntilLift()
            deviceState.contactGate.ignoreUntilAllTouchesLift()
            deviceState.gestureSession = TrackpadGestureSession()
            deviceStates[deviceID] = deviceState
            return
        }

        let update = deviceState.gestureSession.trackPinch(
            radius: radius,
            centerX: centerX,
            centerY: centerY,
            timestamp: timestamp,
            lockedIntent: lockedIntent
        )
        deviceStates[deviceID] = deviceState
        guard let update else { return }
        enqueuePinchUpdate(update)
    }

    func yieldCurrentGestureToSystem() {
        lock.lock()
        defer { lock.unlock() }
        guard let activeDeviceID, var deviceState = deviceStates[activeDeviceID] else { return }
        deviceState.intentArbiter?.ignoreUntilLift()
        deviceState.contactGate.ignoreUntilAllTouchesLift()
        deviceState.gestureSession = TrackpadGestureSession()
        deviceStates[activeDeviceID] = deviceState
        pendingTrackingUpdate = nil
    }

    fileprivate func logDiagnosticFrame(
        device: MTDeviceRef,
        touches: [MTTouch],
        timestamp _: Double
    ) {
        guard diagnosticsEnabled else { return }
        let orderedTouches = touches.sorted { $0.pathIndex < $1.pathIndex }
        let signature = orderedTouches.map { "\($0.pathIndex):\($0.fingerID):\($0.state)" }.joined(separator: ",")
        let now = Date().timeIntervalSinceReferenceDate
        lock.lock()
        let shouldLog = signature != lastDiagnosticFrameSignature || now - lastDiagnosticFrameTime >= 0.08
        if shouldLog {
            lastDiagnosticFrameSignature = signature
            lastDiagnosticFrameTime = now
        }
        lock.unlock()
        guard shouldLog else { return }

        let samples = orderedTouches.map {
            "p=\($0.pathIndex) f=\($0.fingerID) s=\($0.state) x=\(String(format: "%.3f", $0.normalizedVector.position.x)) y=\(String(format: "%.3f", $0.normalizedVector.position.y))"
        }.joined(separator: " | ")
        LaunchLog.line("trackpad raw device=\(UInt(bitPattern: device)) count=\(touches.count) [\(samples)]")
    }

    private func enqueuePinchUpdate(_ update: TrackpadPinchUpdate) {
        switch update {
        case .tracking:
            guard pendingTerminalUpdate == nil else { return }
            pendingTrackingUpdate = update
        case .commit, .cancel:
            pendingTerminalUpdate = update
        }
        guard !deliveryScheduled else { return }
        deliveryScheduled = true
        Task { @MainActor [weak self] in
            self?.deliverLatestPinchUpdate()
        }
    }

    @MainActor
    private func deliverLatestPinchUpdate() {
        lock.lock()
        let trackingUpdate = pendingTrackingUpdate
        let terminalUpdate = pendingTerminalUpdate
        pendingTrackingUpdate = nil
        pendingTerminalUpdate = nil
        deliveryScheduled = false
        let callback = onPinchUpdate
        let now = Date().timeIntervalSinceReferenceDate
        let shouldLogTracking = diagnosticsEnabled
            && trackingUpdate != nil
            && now - lastDiagnosticDeliveryTime >= 0.08
        if shouldLogTracking { lastDiagnosticDeliveryTime = now }
        lock.unlock()
        if shouldLogTracking, let trackingUpdate {
            LaunchLog.line("trackpad diagnostic deliver=\(String(describing: trackingUpdate))")
        }
        if diagnosticsEnabled, let terminalUpdate {
            LaunchLog.line("trackpad diagnostic deliver=\(String(describing: terminalUpdate))")
        }
        if let trackingUpdate { callback?(trackingUpdate) }
        if let terminalUpdate { callback?(terminalUpdate) }
    }
}

private let contactCallback: PinchContactMonitor.ContactCallback = { device, touchesRawPointer, contactCount, timestamp, _ in
    guard let touchesRawPointer, contactCount > 0 else {
        PinchContactMonitor.current?.logDiagnosticFrame(device: device, touches: [], timestamp: timestamp)
        PinchContactMonitor.current?.process(device: device, touches: [], timestamp: timestamp)
        return
    }

    let touchesPointer = touchesRawPointer.bindMemory(
        to: PinchContactMonitor.MTTouch.self,
        capacity: Int(contactCount)
    )
    let rawTouches = Array(UnsafeBufferPointer(start: touchesPointer, count: Int(contactCount)))
    PinchContactMonitor.current?.logDiagnosticFrame(device: device, touches: rawTouches, timestamp: timestamp)
    let touches = rawTouches.map { touch in
        TrackpadTouchSample(
            id: touch.pathIndex,
            x: Double(touch.normalizedVector.position.x),
            y: Double(touch.normalizedVector.position.y),
            majorAxis: Double(touch.majorAxis),
            minorAxis: Double(touch.minorAxis),
            zTotal: Double(touch.zTotal),
            state: touch.state
        )
    }

    PinchContactMonitor.current?.process(device: device, touches: touches, timestamp: timestamp)
}
