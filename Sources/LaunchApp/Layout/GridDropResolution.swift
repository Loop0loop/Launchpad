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

    func beginItemDrag(_ id: String) {
        guard query.isEmpty, openFolder == nil else { return }
        draggingItemID = id
        dragTranslation = .zero
        dragHoverTargetID = nil
    }

    func updateItemDrag(translation: CGSize, hoveredID: String?) {
        guard let dragging = draggingItemID else { return }
        dragTranslation = translation
        dragHoverTargetID = (hoveredID != nil && hoveredID != dragging) ? hoveredID : nil
        maybeOpenFolderOnHover(targetID: dragHoverTargetID)
    }

    /// 드래그 중 폴더 타일 위에 0.45s 머물면 폴더를 자동으로 연다(네이티브 Launchpad).
    /// 대상이 폴더가 아니거나 바뀌면 타이머 취소. FolderOverlay가 열린 뒤 drag-in/out 처리.
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
        var next = orderIDs.filter { $0 != id }
        let insertIndex = min(max(targetIndex, 0), next.count)
        next.insert(id, at: insertIndex)
        saveOrder(next)
    }

    func cancelDrag() {
        draggingItemID = nil
        dragHoverTargetID = nil
        dragTranslation = .zero
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
