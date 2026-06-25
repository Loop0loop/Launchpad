import AppKit
import SwiftUI
import LaunchCore

/// Empty-space page swiping plus Launchpad-style icon-drag paging. Icon dragging is
/// owned by SwiftUI `DragGesture`; this monitor decides when horizontal movement
/// should reveal another page or when edge-hovering should page-scroll.
@MainActor
final class LauncherMouseMonitor {
    private weak var window: NSWindow?
    private weak var state: AppState?
    private var monitor: Any?
    private var isEnabled = false

    private var tracking = false
    private var dragOffset: CGFloat = 0
    private var dragStartPage = 0
    private var pageLockedUntil = Date.distantPast

    private var edgeHoverTimer: Task<Void, Never>?
    private var activeEdge: DragEdge?

    private enum DragEdge {
        case left
        case right
    }

    func configure(window: NSWindow, state: AppState) {
        self.window = window
        self.state = state
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { reset() }
    }

    func stop() {
        setEnabled(false)
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func reset() {
        tracking = false
        dragOffset = 0
        state?.pageDragOffset = 0
        edgeHoverTimer?.cancel()
        edgeHoverTimer = nil
        activeEdge = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isEnabled, let window, let state else { return event }
        guard state.launcherVisible, window.isVisible, event.window === window else { return event }
        switch event.type {
        case .leftMouseDown: return down(event, state)
        case .leftMouseDragged: return dragged(event, state)
        case .leftMouseUp: return up(event, state)
        default: return event
        }
    }

    private func down(_ event: NSEvent, _ state: AppState) -> NSEvent? {
        if state.isDraggingLauncherItem {
            LaunchLog.line("LauncherMouseMonitor down: cancelling active/stale drag")
            state.cancelDrag()
        }

        // Outside-click-to-close is handled by the SwiftUI FolderDimLayer. A hand-rolled
        // panel rect here underestimated the real panel and swallowed clicks on its edges
        // (title field, edge icons) — breaking folder rename and pull-out. Let the guard
        // below simply not start page-swipe tracking while a folder is open.
        guard state.openFolder == nil, state.query.isEmpty, state.displayMode == .paged, Date() >= pageLockedUntil else {
            tracking = false
            return event
        }
        tracking = true
        dragOffset = 0
        dragStartPage = state.currentPage
        state.pageDragOffset = 0
        return event
    }

    private func dragged(_ event: NSEvent, _ state: AppState) -> NSEvent? {
        if state.isDraggingLauncherItem {
            guard let window = self.window else { return event }
            let x = event.locationInWindow.x
            let w = window.frame.width
            let edgeWidth = LaunchConstants.Launcher.dragEdgeWidth
            
            var currentEdge: DragEdge? = nil
            if x < edgeWidth {
                currentEdge = .left
            } else if x > w - edgeWidth {
                currentEdge = .right
            }
            
            if let edge = currentEdge {
                if activeEdge != edge {
                    activeEdge = edge
                    edgeHoverTimer?.cancel()
                    edgeHoverTimer = Task {
                        var isFirst = true
                        while true {
                            do {
                                let interval = isFirst ? LaunchConstants.Launcher.dragPageScrollInterval : 0.9
                                let sleepNs = UInt64(interval * 1_000_000_000)
                                try await Task.sleep(nanoseconds: sleepNs)
                                try Task.checkCancellation()
                                
                                guard let currentWindow = self.window,
                                      let currentState = self.state,
                                      currentState.isDraggingLauncherItem else { break }
                                
                                let currentX = NSEvent.mouseLocation.x - currentWindow.frame.origin.x
                                
                                var checkEdge: DragEdge? = nil
                                if currentX < edgeWidth {
                                    checkEdge = .left
                                } else if currentX > currentWindow.frame.width - edgeWidth {
                                    checkEdge = .right
                                }
                                
                                if checkEdge == edge {
                                    var switched = false
                                    if edge == .left {
                                        if currentState.currentPage > 0 {
                                            withAnimation(LaunchConstants.Animation.pageSnap) {
                                                currentState.selectPage(currentState.currentPage - 1)
                                            }
                                            switched = true
                                        }
                                    } else {
                                        if currentState.currentPage < currentState.pageCount - 1 {
                                            withAnimation(LaunchConstants.Animation.pageSnap) {
                                                currentState.selectPage(currentState.currentPage + 1)
                                            }
                                            switched = true
                                        }
                                    }
                                    if !switched {
                                        break
                                    }
                                    isFirst = false
                                } else {
                                    break
                                }
                            } catch {
                                break
                            }
                        }
                    }
                }
            } else {
                activeEdge = nil
                edgeHoverTimer?.cancel()
                edgeHoverTimer = nil
            }
            
            return event
        }

        guard tracking else { return event }
        dragOffset += event.deltaX
        let pageWidth = window?.frame.width ?? 0
        guard pageWidth > 0 else { return event }

        let maxRubber = pageWidth * LaunchConstants.Launcher.pageRubberBandRatio
        if dragStartPage == 0, dragOffset > 0 { dragOffset = min(dragOffset, maxRubber) }
        if dragStartPage == state.pageCount - 1, dragOffset < 0 { dragOffset = max(dragOffset, -maxRubber) }
        guard abs(dragOffset - state.pageDragOffset) >= 0.75 else { return event }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            state.pageDragOffset = dragOffset
        }
        return event
    }

    private func up(_ event: NSEvent, _ state: AppState) -> NSEvent? {
        guard tracking, !state.isDraggingLauncherItem else {
            reset()
            return event
        }
        let pageWidth = window?.frame.width ?? 0
        guard pageWidth > 0 else {
            reset()
            return event
        }

        let target = abs(dragOffset) >= LaunchConstants.Launcher.dragMinimumDistance
            ? targetPage(pageWidth: pageWidth, state: state)
            : nil
        tracking = false
        dragOffset = 0
        edgeHoverTimer?.cancel()
        edgeHoverTimer = nil
        activeEdge = nil

        withAnimation(LaunchConstants.Animation.pageSnap) {
            if let target {
                state.selectPage(target)
            }
            state.pageDragOffset = 0
        }

        if target != nil {
            pageLockedUntil = Date().addingTimeInterval(LaunchConstants.Launcher.pageChangeCooldown)
        }
        return event
    }

    private func targetPage(pageWidth: CGFloat, state: AppState) -> Int? {
        let threshold = max(pageWidth * LaunchConstants.Launcher.pageSwipeThresholdRatio, LaunchConstants.Launcher.pageDragThreshold)
        var target = dragStartPage
        if dragOffset < -threshold {
            target = min(dragStartPage + 1, state.pageCount - 1)
        } else if dragOffset > threshold {
            target = max(dragStartPage - 1, 0)
        }
        return target == dragStartPage ? nil : target
    }
}
