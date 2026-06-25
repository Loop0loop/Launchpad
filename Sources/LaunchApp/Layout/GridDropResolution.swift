import CoreGraphics
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

extension AppState {
    var isDraggingLauncherItem: Bool { draggingItemID != nil }
    var draggingApp: LaunchApp? { draggingItemID.flatMap(appByID) }

    func beginItemDrag(_ id: String) {
        guard query.isEmpty, openFolder == nil else { return }
        draggingItemID = id
        dragTranslation = .zero
        dragHoverTargetID = nil
        dragInsertionIndex = nil
    }

    func updateItemDrag(location: CGPoint, translation: CGSize, resolution: GridDropResolution) {
        guard let dragging = draggingItemID else { return }
        drag.location = location
        dragTranslation = translation
        // 폴더가 열린 상태(spring-loaded 드롭 중)에는 포인터만 추적한다. 그리드 reflow 불필요.
        if openFolder != nil { return }
        let hovered = (resolution.onIconID != nil && resolution.onIconID != dragging) ? resolution.onIconID : nil
        dragHoverTargetID = hovered
        maybeOpenFolderOnHover(targetID: hovered)
        let nextIndex = hovered == nil ? resolution.targetIndex : nil
        if nextIndex != dragInsertionIndex { dragInsertionIndex = nextIndex }
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
            folderHoverOpenTask?.cancel()
            folderHoverOpenTask = nil
            return
        }
        guard openFolder?.id != folder.id, folderHoverOpenTask == nil else { return }
        folderHoverOpenTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.openFolder == nil, self.draggingItemID != nil else { return }
            self.openFolder = folder
        }
    }

    func endItemDrag(onIconID: String?, slotID: String?, targetIndex: Int?) {
        defer { cancelDrag() }
        guard let dragged = draggingItemID, query.isEmpty, openFolder == nil else { return }

        if let target = onIconID, target != dragged {
            let draggedIsApp = appByID(dragged) != nil
            if draggedIsApp, appByID(target) != nil {
                createFolder(draggedID: dragged, targetID: target)
                return
            }
            if draggedIsApp, folders.contains(where: { $0.id == target }) {
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
        dragHoverTargetID = nil
        dragTranslation = .zero
        dragInsertionIndex = nil
        drag.location = .zero
        folderDragPullingOut = false
        folderHoverOpenTask?.cancel()
        folderHoverOpenTask = nil
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
            let cellCenterX = layout.horizontalPadding + CGFloat(col) * pitchX + layout.columnWidth / 2
            let cellCenterY = CGFloat(row) * layout.rowHeight + layout.rowHeight / 2
            let thresholdX = layout.iconSize * 0.75
            let thresholdY = layout.iconSize * 0.75
            let onIcon = abs(location.x - cellCenterX) < thresholdX
                && abs(location.y - cellCenterY) < thresholdY
            return GridDropResolution(onIconID: onIcon ? id : nil, slotID: id, targetIndex: targetIndex)
        } else {
            return GridDropResolution(onIconID: nil, slotID: nil, targetIndex: targetIndex)
        }
    }
}
