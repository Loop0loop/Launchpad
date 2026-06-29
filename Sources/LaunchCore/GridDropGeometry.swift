public struct GridDropTarget: Equatable, Sendable {
    public let onIconID: String?
    public let slotID: String?
    public let targetIndex: Int?

    public init(onIconID: String?, slotID: String?, targetIndex: Int?) {
        self.onIconID = onIconID
        self.slotID = slotID
        self.targetIndex = targetIndex
    }
}

public enum GridDropGeometry {
    public static func resolve(
        itemIDs: [String],
        page: Int,
        pageSize: Int,
        pointerX: Double,
        pointerY: Double,
        columns: Int,
        rows: Int,
        horizontalPadding: Double,
        columnWidth: Double,
        rowHeight: Double,
        iconSize: Double,
        labelHeight: Double,
        iconLabelSpacing: Double,
        gridColumnSpacing: Double = 0,
        dragMergeZoneScale: Double,
        dragFolderMergeZoneScale: Double,
        dragInsertionBandRatio: Double,
        dragHoldZoneScale: Double,
        folderIDs: Set<String>
    ) -> GridDropTarget {
        guard page >= 0, pageSize > 0, columns > 0, rows > 0, pointerY >= 0 else {
            return GridDropTarget(onIconID: nil, slotID: nil, targetIndex: nil)
        }
        let pitchX = columnWidth + gridColumnSpacing
        let x = pointerX - horizontalPadding
        guard x >= 0, pitchX > 0, rowHeight > 0 else {
            return GridDropTarget(onIconID: nil, slotID: nil, targetIndex: nil)
        }

        let col = Int(x / pitchX)
        let row = Int(pointerY / rowHeight)
        guard col >= 0, col < columns, row >= 0, row < rows else {
            return GridDropTarget(onIconID: nil, slotID: nil, targetIndex: nil)
        }

        let localPageIndex = row * columns + col
        let targetIndex = page * pageSize + localPageIndex
        let iconCenterY = iconSize / 2

        if localPageIndex < itemIDs.count {
            let id = itemIDs[localPageIndex]
            let cellMinX = horizontalPadding + Double(col) * pitchX
            let cellCenterX = cellMinX + columnWidth / 2
            let cellCenterY = Double(row) * rowHeight + iconCenterY
            let dx = abs(pointerX - cellCenterX)
            let dy = abs(pointerY - cellCenterY)
            let mergeScale = folderIDs.contains(id) ? dragFolderMergeZoneScale : dragMergeZoneScale
            let localX = pointerX - cellMinX
            let insertionBand = columnWidth * dragInsertionBandRatio
            let onIcon = dx < iconSize * mergeScale && dy < iconSize * mergeScale
            let insertionIndex: Int?
            if !onIcon && localX < insertionBand {
                insertionIndex = targetIndex
            } else if !onIcon && localX > columnWidth - insertionBand {
                insertionIndex = targetIndex + 1
            } else {
                insertionIndex = nil
            }
            let holdsIconInPlace = insertionIndex == nil && dy < iconSize * dragHoldZoneScale
            return GridDropTarget(
                onIconID: onIcon ? id : nil,
                slotID: holdsIconInPlace ? nil : id,
                targetIndex: holdsIconInPlace ? nil : insertionIndex ?? targetIndex
            )
        }

        return GridDropTarget(onIconID: nil, slotID: nil, targetIndex: targetIndex)
    }
}
