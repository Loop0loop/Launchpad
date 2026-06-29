import CoreGraphics
import Foundation
import LaunchpadCore
import SwiftUI

enum LauncherItem: Identifiable {
    case app(LaunchApp)
    case folder(LaunchFolder, [LaunchApp])

    var id: String {
        switch self {
        case .app(let app): app.id
        case .folder(let folder, _): folder.id
        }
    }
}

struct GridDropResolution {
    let onIconID: String?
    let slotID: String?
    let targetIndex: Int?
}

enum DragIntent {
    case placing
    case mergeCandidate(targetID: String, since: Date)
    case mergeConfirmed(targetID: String)

    var confirmedMergeTargetID: String? {
        if case .mergeConfirmed(let targetID) = self { return targetID }
        return nil
    }
}

extension AppState {
    var isDraggingLauncherItem: Bool { draggingItemID != nil }
    var isHandlingLauncherDrag: Bool {
        isDraggingLauncherItem
            || folderReorderingID != nil
            || folderDragPullingOut
            || folderPullOutAppID != nil
            || folderDragInsertionIndex != nil
            || folderCreationAnimationID != nil
            || abs(pageDragOffset) > 0.5
    }

    var draggingApp: LaunchApp? { draggingItemID.flatMap(appByID) }
    var draggingLauncherItem: LauncherItem? {
        guard let draggingItemID else { return nil }
        return visibleItems.first { $0.id == draggingItemID }
    }

    func beginItemDrag(_ id: String) {
        guard query.isEmpty, openFolder == nil else { return }
        stopEditingLayout()
        draggingItemID = id
        dragTranslation = .zero
        resetDragIntent()
        dragInsertionIndex = nil
    }

    func updateItemDrag(location: CGPoint, translation: CGSize, resolution: GridDropResolution) {
        guard let dragging = draggingItemID else { return }
        drag.location = location
        dragTranslation = translation
        // 폴더가 열린 상태(spring-loaded 드롭 중)에는 포인터만 추적한다. 그리드 reflow 불필요.
        if openFolder != nil { return }
        let canMerge = appByID(dragging) != nil
        let candidate = canMerge && resolution.onIconID != dragging ? resolution.onIconID : nil
        updateDragIntent(candidate)
        maybeOpenFolderOnHover(targetID: candidate.flatMap { id in folders.contains(where: { $0.id == id }) ? id : nil })
        dragHoverTargetID = dragIntent.confirmedMergeTargetID
        let nextIndex = candidate == nil ? resolution.targetIndex : nil
        if nextIndex != dragInsertionIndex { dragInsertionIndex = nextIndex }
    }

    func updateDragIntent(_ candidate: String?) {
        guard let candidate else {
            resetDragIntent()
            return
        }
        switch dragIntent {
        case .mergeConfirmed(let targetID) where targetID == candidate:
            return
        case .mergeCandidate(let targetID, let since) where targetID == candidate:
            if Date().timeIntervalSince(since) >= LaunchConstants.Launcher.dragMergeDwell {
                dragIntent = .mergeConfirmed(targetID: candidate)
                dragHoverTargetID = candidate
            }
        default:
            dragIntent = .mergeCandidate(targetID: candidate, since: Date())
            dragMergeConfirmTask?.cancel()
            dragMergeConfirmTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(LaunchConstants.Launcher.dragMergeDwell * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                guard self.draggingItemID != nil, self.openFolder == nil else { return }
                if case .mergeCandidate(let targetID, _) = self.dragIntent, targetID == candidate {
                    self.dragIntent = .mergeConfirmed(targetID: candidate)
                    self.dragHoverTargetID = candidate
                }
            }
        }
    }

    func resetDragIntent() {
        dragIntent = .placing
        dragHoverTargetID = nil
        dragMergeConfirmTask?.cancel()
        dragMergeConfirmTask = nil
        folderHoverTargetID = nil
        folderHoverOpenTask?.cancel()
        folderHoverOpenTask = nil
    }

    /// Visible items reordered to the live drag preview (dragged moved to the target slot).
    /// Identical move rule as the committed drop, so preview == result.
    var dragRenderItems: [LauncherItem] {
        let items = visibleItems
        guard let dragging = draggingItemID, let index = dragInsertionIndex else { return items }
        let ids = LayoutOrder.move(dragging, toIndex: index, in: items.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// Center of the dragged icon's current preview cell, in "launcherGrid" space, so the
    /// lifted copy can be offset to sit under the pointer regardless of where it reflows to.
    func draggedCellCenter(layout: LaunchpadLayoutMetrics) -> CGPoint? {
        guard let dragging = draggingItemID,
              let global = dragRenderItems.firstIndex(where: { $0.id == dragging }) else { return nil }
        let idx = global - currentPage * gridLayout.pageSize
        guard idx >= 0, idx < gridLayout.pageSize else { return nil }
        let col = idx % layout.columns
        let row = idx / layout.columns
        let pitchX = layout.columnWidth + layout.gridColumnSpacing
        let x = layout.horizontalPadding + CGFloat(col) * pitchX + layout.columnWidth / 2
        let y = CGFloat(row) * layout.rowHeight + layout.rowHeight / 2
        return CGPoint(x: x, y: y)
    }

    /// 드래그 중 폴더 타일 위에 0.45s 머물면 폴더를 자동으로 연다(네이티브 spring-loaded).
    /// 열린 뒤에는 endItemDrag가 폴더 안 슬롯에 드롭을 받는다.
    func maybeOpenFolderOnHover(targetID: String?) {
        guard let targetID, let folder = folders.first(where: { $0.id == targetID }) else {
            folderHoverTargetID = nil
            folderHoverOpenTask?.cancel()
            folderHoverOpenTask = nil
            return
        }
        guard openFolder?.id != folder.id else { return }
        guard folderHoverTargetID != folder.id || folderHoverOpenTask == nil else { return }
        folderHoverTargetID = folder.id
        folderHoverOpenTask?.cancel()
        folderHoverOpenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.openFolder == nil, self.draggingItemID != nil else { return }
            guard self.folderHoverTargetID == folder.id else { return }
            self.openFolder = folder
        }
    }

    /// 현재 드래그 포인터가 열린 폴더 그리드의 어느 슬롯을 가리키는지. 폴더 밖이면 nil.
    func folderDropSlot(forCount count: Int) -> Int? {
        let loc = drag.location
        return FolderDropGeometry.slot(
            pointerX: Double(loc.x), pointerY: Double(loc.y),
            launcherGridOriginX: Double(launcherGridFrame.minX),
            launcherGridOriginY: Double(launcherGridFrame.minY),
            folderGridX: Double(folderGridFrame.minX),
            folderGridY: Double(folderGridFrame.minY),
            folderGridWidth: Double(folderGridFrame.width),
            folderGridHeight: Double(folderGridFrame.height),
            columns: LaunchConstants.FolderOverlay.columns,
            colPitch: Double(LaunchConstants.FolderOverlay.colPitch),
            rowPitch: Double(LaunchConstants.FolderOverlay.rowPitch),
            count: count
        )
    }

    func endItemDrag(onIconID: String?, slotID: String?, targetIndex: Int?) {
        defer { cancelDrag() }
        guard let dragged = draggingItemID, query.isEmpty else { return }

        // Spring-loaded: 폴더가 열린 상태로 드롭 — 포인터가 폴더 안이면 해당 슬롯에 추가, 밖이면 취소.
        if let folder = openFolder {
            if appByID(dragged) != nil, !folder.appIDs.contains(dragged) {
                if let slot = folderDropSlot(forCount: folder.appIDs.count) {
                    addApp(dragged, toFolder: folder.id, at: slot)
                } else {
                    // 패널 밖에서 놓음 → 취소.
                    closeFolder()
                }
            } else {
                closeFolder()
            }
            return
        }

        let draggedIsApp = appByID(dragged) != nil
        let mergeTarget = dragIntent.confirmedMergeTargetID
        if draggedIsApp, let target = mergeTarget, target != dragged {
            if appByID(target) != nil {
                createFolder(draggedID: dragged, targetID: target)
                return
            }
            if folders.contains(where: { $0.id == target }) {
                addApp(dragged, toFolder: target)
                return
            }
        }

        if let index = targetIndex {
            move(dragged, toIndex: index)
        } else if let slot = slotID, slot != dragged {
            move(dragged, before: slot)
        }
    }

    func move(_ id: String, toIndex targetIndex: Int) {
        guard query.isEmpty else { return }
        let orderIDs = visibleItems.map(\.id)
        guard orderIDs.contains(id) else { return }
        saveOrder(LayoutOrder.move(id, toIndex: targetIndex, in: orderIDs))
    }

    func cancelDrag() {
        draggingItemID = nil
        resetDragIntent()
        dragTranslation = .zero
        dragInsertionIndex = nil
        pageDragOffset = 0
        drag.location = .zero
        folderDragPullingOut = false
        folderPullOutAppID = nil
        endFolderReorder()
    }

    /// Maps a pointer location (in the `"launcherGrid"` coordinate space) to the item under it.
    func dropResolution(at location: CGPoint, layout: LaunchpadLayoutMetrics) -> GridDropResolution {
        let items = items(forPage: currentPage)
        guard location.y >= 0 else { return GridDropResolution(onIconID: nil, slotID: nil, targetIndex: nil) }
        let pitchX = layout.columnWidth + layout.gridColumnSpacing
        let x = location.x - layout.horizontalPadding
        guard x >= 0 else { return GridDropResolution(onIconID: nil, slotID: nil, targetIndex: nil) }
        let col = Int(x / pitchX)
        let row = Int(location.y / layout.rowHeight)
        guard col >= 0, col < layout.columns, row >= 0, row < layout.rows else {
            return GridDropResolution(onIconID: nil, slotID: nil, targetIndex: nil)
        }
        let index = row * layout.columns + col
        let targetIndex = currentPage * gridLayout.pageSize + index

        if index < items.count {
            let id = items[index].id
            let cellMinX = layout.horizontalPadding + CGFloat(col) * pitchX
            let cellCenterX = layout.horizontalPadding + CGFloat(col) * pitchX + layout.columnWidth / 2
            let cellCenterY = CGFloat(row) * layout.rowHeight + layout.rowHeight / 2
            let dx = abs(location.x - cellCenterX)
            let dy = abs(location.y - cellCenterY)
            let mergeScale = folders.contains { $0.id == id }
                ? LaunchConstants.Launcher.dragFolderMergeZoneScale
                : LaunchConstants.Launcher.dragMergeZoneScale
            let localX = location.x - cellMinX
            let insertionBand = layout.columnWidth * LaunchConstants.Launcher.dragInsertionBandRatio
            let onIcon = dx < layout.iconSize * mergeScale && dy < layout.iconSize * mergeScale
            let insertionIndex: Int? = if !onIcon && localX < insertionBand {
                targetIndex
            } else if !onIcon && localX > layout.columnWidth - insertionBand {
                targetIndex + 1
            } else {
                nil
            }
            // In the icon row, keep the occupied cell stable so a direct app->app/folder
            // drag can reach the merge zone instead of pushing the target away.
            let holdsIconInPlace = insertionIndex == nil && dy < layout.iconSize * LaunchConstants.Launcher.dragHoldZoneScale
            return GridDropResolution(
                onIconID: onIcon ? id : nil,
                slotID: holdsIconInPlace ? nil : id,
                targetIndex: holdsIconInPlace ? nil : insertionIndex ?? targetIndex
            )
        } else {
            return GridDropResolution(onIconID: nil, slotID: nil, targetIndex: targetIndex)
        }
    }
}
