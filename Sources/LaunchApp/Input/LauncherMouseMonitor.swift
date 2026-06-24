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

        if let folder = state.openFolder {
            if let window = event.window {
                let x = event.locationInWindow.x
                let y = event.locationInWindow.y
                let w = window.frame.width
                let h = window.frame.height
                
                let folderWidth = LaunchConstants.FolderOverlay.width
                
                let appCount = state.apps(in: folder).count
                let cols = CGFloat(LaunchConstants.FolderOverlay.columns)
                let rows = ceil(CGFloat(appCount) / cols)
                let rowHeight = LaunchConstants.FolderOverlay.maxIconSize + LaunchConstants.Icon.spacing + LaunchConstants.Icon.labelHeight
                let gridHeight = max(LaunchConstants.FolderOverlay.minGridHeight, rows * rowHeight + max(0, rows - 1) * LaunchConstants.FolderOverlay.spacing)
                let folderHeight = gridHeight + LaunchConstants.FolderOverlay.titleFontSize + 14 + LaunchConstants.FolderOverlay.spacing + LaunchConstants.FolderOverlay.padding * 2
                
                let minX = (w - folderWidth) / 2
                let maxX = (w + folderWidth) / 2
                let minY = (h - folderHeight) / 2
                let maxY = (h + folderHeight) / 2
                
                let insideFolder = x >= minX && x <= maxX && y >= minY && y <= maxY
                if !insideFolder {
                    LaunchLog.line("LauncherMouseMonitor down outside folder card (x=\(x), y=\(y), w=\(w), h=\(h)) -> closing folder")
                    state.closeFolder()
                    return nil // swallow click
                }
            }
        }

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
                                            withAnimation(LaunchConstants.Animation.spring) {
                                                currentState.selectPage(currentState.currentPage - 1)
                                            }
                                            switched = true
                                        }
                                    } else {
                                        if currentState.currentPage < currentState.pageCount - 1 {
                                            withAnimation(LaunchConstants.Animation.spring) {
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

        state.pageDragOffset = dragOffset
        return event
    }

    private func up(_ event: NSEvent, _ state: AppState) -> NSEvent? {
        defer { reset() }
        guard tracking, !state.isDraggingLauncherItem else { return event }
        let pageWidth = window?.frame.width ?? 0
        guard abs(dragOffset) >= LaunchConstants.Launcher.dragMinimumDistance, pageWidth > 0 else { return event }

        if let target = targetPage(pageWidth: pageWidth, state: state) {
            state.selectPage(target)
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
