/// Maps a drag pointer (given in the launcher grid's own coordinate space) to a slot index
/// inside an open folder's grid. Returns nil when the pointer is outside the folder grid,
/// which the caller treats as "dropped outside the folder" (cancel).
///
/// All frames are in the same global coordinate space. The pointer is converted to global
/// via the launcher grid origin, then to folder-local via the folder grid origin.
public enum FolderDropGeometry {
    public static func slot(
        pointerX: Double, pointerY: Double,
        launcherGridOriginX: Double, launcherGridOriginY: Double,
        folderGridX: Double, folderGridY: Double,
        folderGridWidth: Double, folderGridHeight: Double,
        columns: Int, colPitch: Double, rowPitch: Double, count: Int
    ) -> Int? {
        let globalX = launcherGridOriginX + pointerX
        let globalY = launcherGridOriginY + pointerY
        let localX = globalX - folderGridX
        let localY = globalY - folderGridY
        guard localX >= 0, localY >= 0,
              localX <= folderGridWidth, localY <= folderGridHeight else { return nil }
        let insertionCount = max(count + 1, 1)
        let index = GridGeometry.cellIndex(
            x: localX, y: localY,
            columns: columns, colPitch: colPitch, rowPitch: rowPitch, count: insertionCount
        )
        return min(index, count)
    }
}
