# 폴더 DnD Phase 1 — Spring-loaded 드롭 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 드래그 중 폴더 위에 머물면 폴더가 열리고, 열린 폴더 안의 원하는 칸에 떨어뜨리면 그 위치에 앱이 삽입되는 네이티브 spring-loaded 드롭을 구현한다.

**Architecture:** lifted 드래그 아이콘을 그리드 레이어 밖(top-level)으로 분리해 폴더가 열려도 사라지지 않게 하고, 그리드/폴더 그리드의 frame을 `.global` 좌표로 publish해 드래그 포인터를 폴더 내 슬롯으로 변환한다. 순수 변환 로직(`FolderDropGeometry`)과 모델 변경(`FolderLayout.addApp(at:)`)은 단위 테스트로, UI 결선은 빌드+수동 검증으로 확인한다.

**Tech Stack:** Swift 6.2, SwiftUI, macOS 26, XCTest, Swift Package Manager.

## Global Constraints

- swift-tools-version: 6.2, platform macOS .v26 (`Package.swift` 기존값 유지).
- 그리드 좌표 공간 이름: `"launcherGrid"`, 폴더 그리드: `"folderGrid"` (기존 상수 그대로).
- 폴더 그리드 상수: `LaunchConstants.FolderOverlay.columns = 4`, `colPitch`, `rowPitch` 사용.
- hover 자동 열림 지연: 0.45s (450_000_000 ns).
- 코어 모델 로직은 `Sources/LaunchCore`(LaunchpadCore)에, 순수/테스트 가능하게 둔다.
- 기존 호출부 호환: 새 파라미터는 모두 기본값(`nil`)으로 추가.
- 커밋 메시지 말미: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure

- `Package.swift` — `LaunchpadCoreTests` 테스트 타깃 등록 (Task 1).
- `Sources/LaunchCore/LaunchFolder.swift` — `FolderLayout.addApp`에 `at index:` 추가 (Task 1).
- `Tests/LaunchCoreTests/FolderLayoutTests.swift` — addApp 삽입 테스트 (Task 1).
- `Sources/LaunchCore/FolderDropGeometry.swift` — 포인터→폴더 슬롯 순수 변환 (Task 2, 신규).
- `Tests/LaunchCoreTests/FolderDropGeometryTests.swift` — 변환 테스트 (Task 2).
- `Sources/LaunchApp/App/AppState.swift` — `launcherGridFrame`, `folderGridFrame`, `folderHoverOpenTask`, `draggingApp`, `folderDropSlot` (Task 3,4,5).
- `Sources/LaunchApp/Launcher/LauncherContent.swift` — 그리드 frame publish (Task 3).
- `Sources/LaunchApp/Launcher/FolderOverlay.swift` — 폴더 그리드 frame publish (Task 3).
- `Sources/LaunchApp/Launcher/LauncherView.swift` — top-level 드래그 고스트, hit testing 조건 (Task 4).
- `Sources/LaunchApp/Layout/GridDropResolution.swift` — `maybeOpenFolderOnHover` 복구, `updateItemDrag`/`endItemDrag` 폴더 분기 (Task 4,5).
- `Sources/LaunchApp/Layout/AppState+Layout.swift` — `addApp(_:toFolder:at:)` (Task 5).

---

### Task 1: `FolderLayout.addApp(at:)` 인덱스 삽입 + 테스트 타깃

**Files:**
- Modify: `Package.swift` (targets 배열)
- Modify: `Sources/LaunchCore/LaunchFolder.swift:31-43`
- Create/Test: `Tests/LaunchCoreTests/FolderLayoutTests.swift`

**Interfaces:**
- Produces: `FolderLayout.addApp(appID:toFolderID:folders:order:at:) -> (folders:[LaunchFolder], order:[String])` — `at: Int?` 기본 nil(끝에 append), 값이 있으면 `0...appIDs.count`로 clamp 후 삽입. 중복 가드 유지.

- [ ] **Step 1: 테스트 타깃 등록**

`Package.swift`의 `targets:` 배열 마지막 항목 뒤에 추가(`LaunchpadCheck` 줄 다음, 배열 닫기 전):

```swift
        .executableTarget(name: "LaunchpadCheck", dependencies: ["LaunchpadCore"], path: "Sources/LaunchCheck"),
        .testTarget(name: "LaunchpadCoreTests", dependencies: ["LaunchpadCore"], path: "Tests/LaunchCoreTests")
```

- [ ] **Step 2: 실패하는 테스트 작성**

`Tests/LaunchCoreTests/FolderLayoutTests.swift`:

```swift
import XCTest
@testable import LaunchpadCore

final class FolderLayoutTests: XCTestCase {
    private func folder() -> LaunchFolder {
        LaunchFolder(id: "f1", name: "Folder", appIDs: ["a", "b"])
    }

    func testAddAppDefaultAppends() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"])
        XCTAssertEqual(r.folders[0].appIDs, ["a", "b", "c"])
    }

    func testAddAppAtFront() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"], at: 0)
        XCTAssertEqual(r.folders[0].appIDs, ["c", "a", "b"])
    }

    func testAddAppAtMiddle() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"], at: 1)
        XCTAssertEqual(r.folders[0].appIDs, ["a", "c", "b"])
    }

    func testAddAppIndexClampedToCount() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"], at: 99)
        XCTAssertEqual(r.folders[0].appIDs, ["a", "b", "c"])
    }

    func testAddAppNegativeIndexClampedToZero() {
        let r = FolderLayout.addApp(appID: "c", toFolderID: "f1", folders: [folder()], order: ["f1"], at: -5)
        XCTAssertEqual(r.folders[0].appIDs, ["c", "a", "b"])
    }

    func testAddAppDuplicateIsNoOp() {
        let r = FolderLayout.addApp(appID: "a", toFolderID: "f1", folders: [folder()], order: ["f1"], at: 0)
        XCTAssertEqual(r.folders[0].appIDs, ["a", "b"])
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test --filter FolderLayoutTests`
Expected: 컴파일 실패 (`extra argument 'at'`) 또는 테스트 실패.

- [ ] **Step 4: 구현**

`Sources/LaunchCore/LaunchFolder.swift`의 `addApp`을 교체:

```swift
    public static func addApp(
        appID: String,
        toFolderID folderID: String,
        folders: [LaunchFolder],
        order: [String],
        at insertIndex: Int? = nil
    ) -> (folders: [LaunchFolder], order: [String]) {
        guard let index = folders.firstIndex(where: { $0.id == folderID }),
              !folders[index].appIDs.contains(appID) else { return (folders, order) }

        var nextFolders = folders
        if let insertIndex {
            let clamped = min(max(insertIndex, 0), nextFolders[index].appIDs.count)
            nextFolders[index].appIDs.insert(appID, at: clamped)
        } else {
            nextFolders[index].appIDs.append(appID)
        }
        return (nextFolders, order.filter { $0 != appID })
    }
```

- [ ] **Step 5: 통과 확인**

Run: `swift test --filter FolderLayoutTests`
Expected: PASS (6 tests).

- [ ] **Step 6: 커밋**

```bash
git add Package.swift Sources/LaunchCore/LaunchFolder.swift Tests/LaunchCoreTests/FolderLayoutTests.swift
git commit -m "feat:FolderLayout.addApp 인덱스 삽입 지원 + 테스트 타깃

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `FolderDropGeometry` 포인터→슬롯 순수 변환

**Files:**
- Create: `Sources/LaunchCore/FolderDropGeometry.swift`
- Test: `Tests/LaunchCoreTests/FolderDropGeometryTests.swift`

**Interfaces:**
- Consumes: `GridGeometry.cellIndex(x:y:columns:colPitch:rowPitch:count:)` (기존).
- Produces: `FolderDropGeometry.slot(pointerX:pointerY:launcherGridOriginX:launcherGridOriginY:folderGridX:folderGridY:folderGridWidth:folderGridHeight:columns:colPitch:rowPitch:count:) -> Int?` — 포인터(launcherGrid 로컬)를 global→folder 로컬로 변환, 폴더 그리드 밖이면 nil, 안이면 슬롯 인덱스(0..<count).

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/LaunchCoreTests/FolderDropGeometryTests.swift`:

```swift
import XCTest
@testable import LaunchpadCore

final class FolderDropGeometryTests: XCTestCase {
    // 폴더 그리드: global (100,100), 400x200, 4열, colPitch 100, rowPitch 100, 6칸
    private func slot(px: Double, py: Double) -> Int? {
        FolderDropGeometry.slot(
            pointerX: px, pointerY: py,
            launcherGridOriginX: 0, launcherGridOriginY: 0,
            folderGridX: 100, folderGridY: 100,
            folderGridWidth: 400, folderGridHeight: 200,
            columns: 4, colPitch: 100, rowPitch: 100, count: 6
        )
    }

    func testFirstCell() {
        XCTAssertEqual(slot(px: 110, py: 110), 0)
    }

    func testSecondCellSameRow() {
        XCTAssertEqual(slot(px: 210, py: 110), 1)
    }

    func testSecondRowFirstCell() {
        XCTAssertEqual(slot(px: 110, py: 210), 4)
    }

    func testClampedToCount() {
        // 마지막 행/열 영역 → count-1 로 clamp
        XCTAssertEqual(slot(px: 490, py: 290), 5)
    }

    func testOutsideLeftReturnsNil() {
        XCTAssertNil(slot(px: 50, py: 110))
    }

    func testOutsideBelowReturnsNil() {
        XCTAssertNil(slot(px: 110, py: 350))
    }

    func testLauncherOriginOffsetApplied() {
        // 그리드 origin이 (0,50)이면 포인터 y는 50만큼 위로 보정됨
        let s = FolderDropGeometry.slot(
            pointerX: 110, pointerY: 60,
            launcherGridOriginX: 0, launcherGridOriginY: 50,
            folderGridX: 100, folderGridY: 100,
            folderGridWidth: 400, folderGridHeight: 200,
            columns: 4, colPitch: 100, rowPitch: 100, count: 6
        )
        XCTAssertEqual(s, 0) // global y = 50+60=110 → folder-local 10 → row 0
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test --filter FolderDropGeometryTests`
Expected: 컴파일 실패 (`FolderDropGeometry` 없음).

- [ ] **Step 3: 구현**

`Sources/LaunchCore/FolderDropGeometry.swift`:

```swift
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
        return GridGeometry.cellIndex(
            x: localX, y: localY,
            columns: columns, colPitch: colPitch, rowPitch: rowPitch, count: count
        )
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test --filter FolderDropGeometryTests`
Expected: PASS (7 tests).

- [ ] **Step 5: 커밋**

```bash
git add Sources/LaunchCore/FolderDropGeometry.swift Tests/LaunchCoreTests/FolderDropGeometryTests.swift
git commit -m "feat:FolderDropGeometry 포인터→폴더 슬롯 변환

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 그리드/폴더 frame을 global 좌표로 publish

**Files:**
- Modify: `Sources/LaunchApp/App/AppState.swift` (상태 추가)
- Modify: `Sources/LaunchApp/Launcher/LauncherContent.swift:40` (그리드 frame)
- Modify: `Sources/LaunchApp/Launcher/FolderOverlay.swift:67` (폴더 그리드 frame)

**Interfaces:**
- Produces: `AppState.launcherGridFrame: CGRect`, `AppState.folderGridFrame: CGRect` — 각각 `"launcherGrid"` 그리드 컨테이너와 폴더 `LazyVGrid`의 `.global` frame. Task 5의 `folderDropSlot`가 소비.

- [ ] **Step 1: AppState에 frame 상태 추가**

`Sources/LaunchApp/App/AppState.swift`의 `@Published var openFolder: LaunchFolder?` (57행) 아래에 추가:

```swift
    /// 드래그 좌표 변환용. 둘 다 `.global` 좌표. launcherGrid = 그리드 컨테이너, folderGrid = 열린 폴더 그리드.
    @Published var launcherGridFrame: CGRect = .zero
    @Published var folderGridFrame: CGRect = .zero
```

- [ ] **Step 2: 그리드 컨테이너 frame publish**

`Sources/LaunchApp/Launcher/LauncherContent.swift`의 `.coordinateSpace(name: "launcherGrid")` (40행) 바로 아래 줄에 추가:

```swift
            .coordinateSpace(name: "launcherGrid")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.launcherGridFrame = $0 }
```

- [ ] **Step 3: 폴더 그리드 frame publish**

`Sources/LaunchApp/Launcher/FolderOverlay.swift`의 `.coordinateSpace(name: "folderGrid")` (67행) 바로 아래에 추가:

```swift
            .coordinateSpace(name: "folderGrid")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.folderGridFrame = $0 }
```

- [ ] **Step 4: 빌드 확인**

Run: `swift build`
Expected: `Build complete!` (동작 변화 없음, 상태만 채워짐).

- [ ] **Step 5: 커밋**

```bash
git add Sources/LaunchApp/App/AppState.swift Sources/LaunchApp/Launcher/LauncherContent.swift Sources/LaunchApp/Launcher/FolderOverlay.swift
git commit -m "feat:그리드/폴더 그리드 frame을 global 좌표로 publish

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: hover 자동 열림 복구 + top-level 드래그 고스트

**Files:**
- Modify: `Sources/LaunchApp/App/AppState.swift` (`folderHoverOpenTask`, `draggingApp`)
- Modify: `Sources/LaunchApp/Layout/GridDropResolution.swift` (`maybeOpenFolderOnHover` 복구, `updateItemDrag`, `cancelDrag`)
- Modify: `Sources/LaunchApp/Launcher/LauncherView.swift` (hit testing, 고스트)

**Interfaces:**
- Consumes: `AppState.launcherGridFrame` (Task 3), `appByID(_:)` (기존).
- Produces: `AppState.folderHoverOpenTask: Task<Void, Never>?`, `AppState.draggingApp: LaunchApp?`. `maybeOpenFolderOnHover(targetID:)` 복구.

- [ ] **Step 1: AppState 상태/헬퍼 추가**

`Sources/LaunchApp/App/AppState.swift`의 `var searchDebounceTask: Task<Void, Never>?` 아래에 추가:

```swift
    /// 드래그 중 폴더 위에 머물 때 0.45s 후 폴더를 자동으로 여는 hover 타이머.
    var folderHoverOpenTask: Task<Void, Never>?
```

그리고 `var isDraggingLauncherItem`이 있는 확장(또는 AppState 본문)에 접근 가능한 위치, `Sources/LaunchApp/Layout/GridDropResolution.swift`의 `extension AppState {` 안 `isDraggingLauncherItem` 아래에 추가:

```swift
    var draggingApp: LaunchApp? { draggingItemID.flatMap(appByID) }
```

- [ ] **Step 2: `maybeOpenFolderOnHover` 복구 + `updateItemDrag` 분기**

`Sources/LaunchApp/Layout/GridDropResolution.swift`의 `updateItemDrag`를 교체:

```swift
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
```

`endItemDrag` 정의 바로 위에 `maybeOpenFolderOnHover`를 다시 추가:

```swift
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
```

`cancelDrag`에 타이머 정리 복구 — `folderDragPullingOut = false` 다음 줄에 추가:

```swift
        folderDragPullingOut = false
        folderHoverOpenTask?.cancel()
        folderHoverOpenTask = nil
```

- [ ] **Step 3: LauncherView hit testing + 드래그 고스트**

`Sources/LaunchApp/Launcher/LauncherView.swift`의 `.allowsHitTesting(state.openFolder == nil)` (54행)을 교체:

```swift
                    .allowsHitTesting(state.openFolder == nil || state.isDraggingLauncherItem)
```

폴더 오버레이 `if let folder = state.openFolder { ... }` 블록(58-71행)의 닫는 `}` 바로 다음, ZStack 안에 드래그 고스트를 추가:

```swift
                    if state.isDraggingLauncherItem, state.openFolder != nil, let app = state.draggingApp {
                        let geoGlobal = geometry.frame(in: .global)
                        let ghostPos = CGPoint(
                            x: state.launcherGridFrame.minX - geoGlobal.minX + state.drag.location.x,
                            y: state.launcherGridFrame.minY - geoGlobal.minY + state.drag.location.y
                        )
                        LoadedIcon(app: app, displaySize: layout.iconSize, loadsImage: true)
                            .frame(width: layout.iconSize, height: layout.iconSize)
                            .scaleEffect(1.1)
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                            .position(ghostPos)
                            .allowsHitTesting(false)
                            .zIndex(22)
                    }
```

- [ ] **Step 4: 빌드 확인**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: 수동 검증 (드롭 결선 전, 고스트/열림만)**

Run: `swift run Launchpad` (또는 기존 실행 방식)
확인: 앱을 폴더 위로 끌어 0.45s 머물면 폴더가 열리고, 손에 든 아이콘 고스트가 폴더 패널 위에 포인터를 따라 보인다. (아직 놓아도 추가 안 됨 — Task 5에서 결선). 놓으면 드래그가 취소되고 폴더는 열린 채 남을 수 있음(정상, 다음 태스크에서 처리).

- [ ] **Step 6: 커밋**

```bash
git add Sources/LaunchApp/App/AppState.swift Sources/LaunchApp/Layout/GridDropResolution.swift Sources/LaunchApp/Launcher/LauncherView.swift
git commit -m "feat:hover 폴더 자동 열림 복구 + top-level 드래그 고스트

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 열린 폴더 드롭 결선 (endItemDrag)

**Files:**
- Modify: `Sources/LaunchApp/Layout/AppState+Layout.swift:101-115` (`addApp`에 `at:`)
- Modify: `Sources/LaunchApp/Layout/GridDropResolution.swift` (`endItemDrag` 폴더 분기, `folderDropSlot`)

**Interfaces:**
- Consumes: `FolderLayout.addApp(...at:)` (Task 1), `FolderDropGeometry.slot(...)` (Task 2), `launcherGridFrame`/`folderGridFrame` (Task 3), `drag.location`.
- Produces: `AppState.addApp(_:toFolder:at:)`, `AppState.folderDropSlot(forCount:) -> Int?`.

- [ ] **Step 1: `addApp`에 인덱스 파라미터 추가**

`Sources/LaunchApp/Layout/AppState+Layout.swift`의 `addApp(_:toFolder:)`를 교체:

```swift
    func addApp(_ appID: String, toFolder folderID: String, at index: Int? = nil) {
        guard query.isEmpty else { return }
        guard folders.allSatisfy({ !$0.appIDs.contains(appID) }) else { return }
        LaunchLog.line("add app to folder app=\(appID) folder=\(folderID) at=\(index.map(String.init) ?? "end")")
        let result = FolderLayout.addApp(
            appID: appID,
            toFolderID: folderID,
            folders: folders,
            order: visibleItems.map(\.id),
            at: index
        )
        folders = result.folders
        LayoutStore.saveFolders(folders)
        saveOrder(result.order)
        openFolder = folders.first { $0.id == folderID }
    }
```

- [ ] **Step 2: `folderDropSlot` 헬퍼 추가**

`Sources/LaunchApp/Layout/GridDropResolution.swift`의 `extension AppState` 안(예: `cancelDrag` 위)에 추가:

```swift
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
```

- [ ] **Step 3: `endItemDrag` 폴더 분기 추가**

`Sources/LaunchApp/Layout/GridDropResolution.swift`의 `endItemDrag`를 교체:

```swift
    func endItemDrag(onIconID: String?, slotID: String?, targetIndex: Int?) {
        defer { cancelDrag() }
        guard let dragged = draggingItemID, query.isEmpty else { return }

        // Spring-loaded: 폴더가 열린 상태로 드롭 — 포인터가 폴더 안이면 해당 슬롯에 추가, 밖이면 취소.
        if let folder = openFolder {
            if appByID(dragged) != nil, !folder.appIDs.contains(dragged),
               let slot = folderDropSlot(forCount: folder.appIDs.count) {
                addApp(dragged, toFolder: folder.id, at: slot)
            } else {
                closeFolder()
            }
            return
        }

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
```

- [ ] **Step 4: 빌드 + 회귀 테스트**

Run: `swift build && swift test`
Expected: `Build complete!`, Task 1·2 테스트 PASS.

- [ ] **Step 5: 수동 검증 (전체 시나리오)**

Run: `swift run Launchpad`
확인:
1. 2개짜리 폴더 위로 3번째 앱을 끌어 0.45s 머무름 → 폴더 열림.
2. 폴더 안 **첫 칸**에 놓음 → 맨 앞에 삽입(`["c","a","b"]` 순).
3. 다시 다른 앱을 끌어 **마지막 칸** 근처에 놓음 → 뒤쪽에 삽입.
4. 폴더가 열린 뒤 패널 **바깥**(dim 영역)에 놓음 → 추가 안 되고 폴더 닫힘, 앱은 원위치.
5. (회귀) 닫힌 폴더 타일에 빠르게(머무르지 않고) 드롭 → 기존대로 끝에 추가.
6. (회귀) 앱+앱 드롭 → 폴더 생성 정상.

- [ ] **Step 6: 커밋**

```bash
git add Sources/LaunchApp/Layout/AppState+Layout.swift Sources/LaunchApp/Layout/GridDropResolution.swift
git commit -m "feat:열린 폴더 안 슬롯에 spring-loaded 드롭 결선

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## 후속 (별도 플랜)

- Phase 2 애니메이션, Phase 3 생성, Phase 4 끌어내기는 본 Phase 1의 top-level 고스트 + 좌표 브리지(`launcherGridFrame`/`folderGridFrame`/`FolderDropGeometry`)를 재사용하여 각각 별도 플랜으로 진행한다. 설계: `docs/superpowers/specs/2026-06-25-folder-dnd-native-design.md`.

## 알려진 한계 (Phase 1)

- 슬롯 계산 `count`는 현재 폴더 아이템 수라 spring-loaded 드롭의 삽입 인덱스는 `0..<count`. 맨 끝(append)은 닫힌 타일 빠른 드롭으로 커버됨. 마지막 칸 뒤 정확한 append는 Phase 2 라이브 reflow에서 다룬다.
- 드롭 시 폴더 내부 라이브 미리보기(아이콘이 비켜나는 모션) 없음 — Phase 2.
