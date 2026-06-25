# 폴더 DnD 네이티브화 설계

날짜: 2026-06-25
대상: macOS Launchpad 클론 — 폴더 드래그 앤 드롭을 네이티브 Launchpad에 가깝게 다듬기

## 배경 / 문제

현재 폴더 DnD는 다음만 동작한다.

- 앱→앱 = 폴더 생성 (`createFolder`)
- 앱→닫힌 폴더 타일 = 폴더에 추가 (`addApp`, 끝에 append)
- 폴더 내부: 재정렬, 끌어내기(pull-out, 고정 100pt 임계)

빠진/거친 부분:

- **Spring-loaded 드롭 없음.** 네이티브는 드래그 중 폴더 위에 잠깐 머물면 폴더가 열리고, 열린 폴더 안 특정 칸에 떨어뜨리면 그 위치에 삽입된다. 이전 구현은 hover로 폴더를 열기만 하고 받는 핸들러가 없어 드롭이 사라지는 버그였고, 해당 자동 열림 코드는 제거된 상태.
- 드래그/머지/생성/끌어내기 애니메이션이 거칠다.

### 핵심 아키텍처 제약

폴더가 열리면 그리드 레이어가 통째로 `.opacity(0)` + `.allowsHitTesting(false)` 처리된다
(`LauncherView.swift`). 그런데 드래그 중인 lifted 아이콘도 그 그리드 레이어 안에서
그려진다(`LauncherDragModifier`의 `floatOffset` ZStack). 따라서 드래그 중 폴더가 열리면
손에 든 아이콘이 같이 사라지고 드롭 타깃이 없어진다. 이것이 spring-loaded가 막혀 있던 근본 원인.

## 목표

네이티브 Launchpad에 가까운 폴더 DnD:

1. 드래그 중 폴더 위 머무름 → 폴더 자동 열림 → 안의 원하는 칸에 드롭 → 그 위치 삽입 (spring-loaded)
2. lift/머지/생성/끌어내기 애니메이션 다듬기
3. 끌어내기를 거리 임계가 아니라 패널 경계 기준으로

## 비목표 (YAGNI)

- 페이지 간 드래그 이동 개선(별도 항목)
- 폴더 안 다중 페이지
- 폴더 색/커스텀 그리드 크기

## 설계

전체를 4개 phase로 진행한다. **Phase 1이 top-level 드래그 고스트와 좌표 브리지 인프라를
깔고, Phase 2~4가 이를 재사용한다.**

### Phase 1 — Spring-loaded 드롭 (기반)

**1. Top-level 드래그 고스트**

`LauncherView`의 최상위 ZStack에 드래그 중 앱 아이콘을 `drag.location` 위치에 렌더하는
오버레이를 추가한다. zIndex 22 (폴더 패널 zIndex 21 위). 표시 조건은
`isDraggingLauncherItem && openFolder != nil` — 폴더가 열린 상태로 드래그할 때만. 폴더가
닫힌 일반 드래그는 기존 in-grid lifted 복사본을 그대로 쓴다(변경 없음). `LoadedIcon` 재사용.

**2. 제스처 생존 보장**

그리드 레이어의 hit testing 조건을 드래그 중에는 유지한다:
`allowsHitTesting(openFolder == nil || isDraggingLauncherItem)`.
진행 중인 `DragGesture`가 폴더 열림 이후에도 `onChanged`/`onEnded`를 계속 받도록 보장.
레이어는 opacity 0이지만 폴더 dim/패널 뒤에 있고 드래그 중이라 오작동 탭은 발생하지 않음.

**3. Hover 자동 열림 복구**

`maybeOpenFolderOnHover`를 되살린다. 드래그 중 `updateItemDrag`에서 hover 대상이 폴더이고
0.45s 유지되면 `openFolder = folder`로 설정. 대상이 바뀌거나 폴더가 아니면 타이머 취소.
이번에는 받는 드롭 핸들러(아래 5)가 있으므로 안전.

**4. 좌표 브리지**

- 그리드 컨테이너와 폴더 그리드의 frame을 각각 `.global` 좌표로 state에 publish한다
  (background `GeometryReader` 2개 → `state.launcherGridFrame`, `state.folderGridFrame`).
- 드래그 포인터는 `launcherGrid` 로컬(`value.location`). 변환:
  `globalPoint = launcherGridFrame.origin + value.location`,
  `folderLocalPoint = globalPoint - folderGridFrame.origin`.
- `folderLocalPoint`을 `GridGeometry.cellIndex`(폴더 columns/pitch 상수)로 넘겨 삽입 칸 계산.
- 포인터가 `folderGridFrame` 밖이면 "폴더 밖" 으로 판정.

**5. 드롭 처리**

`endItemDrag`에서 `openFolder != nil`인 경우 분기:

- 포인터가 폴더 그리드 안 → `addApp(dragged, toFolder: openFolder.id, atIndex: slot)`.
  `FolderLayout.addApp`에 `at index: Int?` 파라미터 추가(기본 nil = 끝에 append, 기존 동작 유지).
- 포인터가 패널 밖 → 드래그 취소 + 폴더 닫기(끌어내서 무효화).
- 닫힌 타일에 빠르게 드롭하는 기존 경로(`onIconID` → `addApp` append)는 fallback으로 유지.

**산출물:** 폴더 위 머무름 → 열림 → 원하는 칸에 드롭 → 해당 위치 삽입.

**검증:** `FolderLayout.addApp(at:)`의 인덱스 삽입을 단위 테스트(경계: 0, count, 범위 밖).
앱 실행 후 2개짜리 폴더에 3번째를 머물러 열고 첫 칸/마지막 칸에 떨어뜨려 위치 확인.

### Phase 2 — 애니메이션

- lift: 들어올릴 때 스프링 스케일 + 그림자 확대(기존 `iconLift` 튜닝).
- hover 폴더 열림 타이밍/transition 튜닝(기존 `folderEntranceScale` 활용).
- **열린 폴더 안 라이브 reflow:** 드래그 포인터가 가리키는 칸으로 폴더 내 아이콘들이 비켜나는
  미리보기. Phase 1의 좌표 브리지로 hover 슬롯을 계산해 `FolderOverlay` 그리드에 반영
  (그리드의 `dragInsertionIndex` 패턴을 폴더용으로 재현).
- 드롭 "흡수" 바운스(놓을 때 아이콘이 칸에 살짝 튕기며 안착).

### Phase 3 — 생성 애니메이션

- 앱+앱 머지 시: 드래그 아이콘이 타깃 위에 겹치면 타깃 뒤로 폴더 윤곽이 형성되는 인텐트 표시
  (현재는 1.16 스케일만). 드롭하면 두 아이콘이 새 폴더로 모이며 zoom-open.
- `createFolder`가 이미 `openFolder`를 새 폴더로 설정하므로, 진입 transition을 머지 모션과
  연결.

### Phase 4 — 끌어내기

- 고정 100pt 임계 대신 Phase 1의 `folderGridFrame`을 이용해 **포인터가 패널 밖으로 나가면**
  끌어내기로 판정.
- 끌어낸 뒤 곧장 그리드 드롭하지 않고, top-level 고스트를 이용해 그리드에서 계속 드래그하여
  슬롯을 지정할 수 있게 한다(네이티브 동작). 현재의 `removeApp` + `revealItem` 즉시 배치를
  연속 드래그로 대체.

## 데이터 흐름 (Phase 1)

```
DragGesture.onChanged (launcherGrid 로컬)
  → updateItemDrag(location, resolution)
      → maybeOpenFolderOnHover(hoverTarget)  // 0.45s 후 openFolder 설정
  → (folder 열림) top-level 고스트가 drag.location에 렌더
DragGesture.onEnded
  → endItemDrag
      → openFolder != nil?
          → 좌표 브리지로 folderLocalPoint 계산
          → 폴더 안: addApp(at: slot) / 밖: cancel + closeFolder
      → else: 기존 grid 드롭(생성/추가/재정렬)
```

## 영향 파일

- `Sources/LaunchApp/Layout/GridDropResolution.swift` — `maybeOpenFolderOnHover` 복구,
  `endItemDrag` 폴더 분기, 좌표 변환 헬퍼.
- `Sources/LaunchApp/App/AppState.swift` — `launcherGridFrame`, `folderGridFrame`,
  `folderHoverOpenTask` 상태 복구/추가.
- `Sources/LaunchApp/Launcher/LauncherView.swift` — top-level 드래그 고스트, hit testing 조건,
  그리드 frame publish.
- `Sources/LaunchApp/Launcher/FolderOverlay.swift` — 폴더 그리드 frame publish, 라이브 reflow(P2).
- `Sources/LaunchApp/Layout/AppState+Layout.swift` — `addApp(atIndex:)` 경유.
- `Sources/LaunchCore/LaunchFolder.swift` — `FolderLayout.addApp(at index: Int?)`.
- `Sources/LaunchApp/Launcher/LauncherItemViews.swift` — 머지 인텐트 비주얼(P3).

## 리스크

- **제스처 생존:** 폴더 열림 후 DragGesture가 계속 이벤트를 받는지 — Phase 1에서 가장 먼저
  실측 확인. 안 되면 그리드 hit testing을 끄지 않는 것으로 보강(설계에 반영됨).
- **좌표 정합:** `.global` 기준 두 frame 비교로 좌표계 일치. 폴더 패널이 ZStack 중앙 정렬이라
  GeometryReader publish가 분석적 계산보다 안전.
