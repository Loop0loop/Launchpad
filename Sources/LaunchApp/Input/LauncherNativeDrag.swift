import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    static let launcherInternalItem = Self("app.launchpad.mvp.internal-item")
}

struct LauncherNativeDragGesture: NSGestureRecognizerRepresentable {
    let itemID: String
    let state: AppState
    let layout: LaunchpadLayoutMetrics

    func makeNSGestureRecognizer(context: Context) -> NSPanGestureRecognizer {
        let recognizer = NSPanGestureRecognizer()
        recognizer.buttonMask = 1
        recognizer.isCancellableByScrollGesture = false
        return recognizer
    }

    func handleNSGestureRecognizerAction(_ recognizer: NSPanGestureRecognizer, context: Context) {
        guard recognizer.state == .began else { return }
        state.nativeDragController.begin(itemID: itemID, recognizer: recognizer, state: state, layout: layout)
    }
}

@MainActor
final class LauncherNativeDragController: NSObject, NSDraggingSource {
    private enum Edge { case left, right }

    private weak var state: AppState?
    private weak var window: NSWindow?
    private var layout: LaunchpadLayoutMetrics?
    private var edge: Edge?
    private var edgeTask: Task<Void, Never>?

    func begin(itemID: String, recognizer: NSPanGestureRecognizer, state: AppState, layout: LaunchpadLayoutMetrics) {
        guard self.state == nil, let view = recognizer.view, let window = view.window else { return }

        guard let pointer = gridPoint(screenPoint: NSEvent.mouseLocation, window: window, state: state) else { return }
        state.beginItemDrag(itemID, at: pointer, layout: layout)
        guard state.draggingItemID == itemID else { return }

        self.state = state
        self.window = window
        self.layout = layout

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(itemID, forType: .launcherInternalItem)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let location = recognizer.location(in: view)
        draggingItem.setDraggingFrame(NSRect(x: location.x, y: location.y, width: 1, height: 1), contents: NSImage(size: NSSize(width: 1, height: 1)))

        guard let session = view.beginDraggingSession(items: [draggingItem], gesture: recognizer, source: self) else {
            state.cancelDrag(reason: "native-session-failed")
            reset()
            return
        }

        session.animatesToStartingPositionsOnCancelOrFail = false
        update(screenPoint: NSEvent.mouseLocation)
        LaunchLog.line("native drag session requested item=\(itemID)")
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        LaunchLog.line("native drag began sequence=\(session.draggingSequenceNumber)")
        update(screenPoint: screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        update(screenPoint: screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer { reset() }
        guard let state, let layout else { return }
        update(screenPoint: screenPoint)
        LaunchLog.line("native drag ended sequence=\(session.draggingSequenceNumber) operation=\(operation.rawValue)")
        guard operation.contains(.move) else {
            state.cancelDrag(reason: "native-drop-rejected")
            return
        }
        if state.dragAwaitingMouseUp {
            state.finishCommittedMergeDrag()
            return
        }
        let resolution = state.dropResolution(at: state.drag.location, layout: layout)
        state.endItemDrag(slotID: resolution.slotID, targetIndex: resolution.targetIndex)
    }

    private func update(screenPoint: NSPoint) {
        guard let state, let window, let layout,
              let pointer = gridPoint(screenPoint: screenPoint, window: window, state: state) else { return }
        let iconCenter = state.drag.iconCenter(for: pointer)
        let resolution = state.dropResolution(at: iconCenter, layout: layout)
        state.updateItemDrag(
            pointerLocation: pointer,
            resolution: resolution
        )
        updateEdgePaging(screenPoint: screenPoint, window: window, state: state)
    }

    private func gridPoint(screenPoint: NSPoint, window: NSWindow, state: AppState) -> CGPoint? {
        guard let contentView = window.contentView else { return nil }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let rootPoint = contentView.convert(windowPoint, from: nil)
        return CGPoint(
            x: rootPoint.x - state.launcherGridFrame.minX,
            y: rootPoint.y - state.launcherGridFrame.minY
        )
    }

    private func updateEdgePaging(screenPoint: NSPoint, window: NSWindow, state: AppState) {
        let x = window.convertPoint(fromScreen: screenPoint).x
        let width = window.frame.width
        let edgeWidth = LaunchConstants.Launcher.dragEdgeWidth
        let nextEdge: Edge? = x < edgeWidth ? .left : (x > width - edgeWidth ? .right : nil)
        guard nextEdge != edge else { return }
        edge = nextEdge
        edgeTask?.cancel()
        guard let nextEdge else { return }
        edgeTask = Task { [weak self, weak state] in
            var first = true
            while !Task.isCancelled {
                let delay = first ? LaunchConstants.Launcher.dragPageScrollInterval : 0.9
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, let state, self.edge == nextEdge, state.isDraggingLauncherItem else { return }
                let nextPage = state.currentPage + (nextEdge == .left ? -1 : 1)
                guard nextPage >= 0, nextPage < state.pageCount else { return }
                withAnimation(LaunchConstants.Animation.pageSnap) { state.selectPage(nextPage) }
                first = false
            }
        }
    }

    private func reset() {
        edgeTask?.cancel()
        edgeTask = nil
        edge = nil
        state = nil
        window = nil
        layout = nil
    }
}
