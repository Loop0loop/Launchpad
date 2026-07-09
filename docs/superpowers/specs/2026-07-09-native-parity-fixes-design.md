# Native Parity Fixes Design

날짜: 2026-07-09  
대상: macOS Launchpad 클론 — 인덱싱, 트랙패드 핀치, DnD 히트, 애니/UX  
사이클 전략: **A (최소 수정)** 로 구현, 구조는 이후 **C (엔진형)** 로 확장 가능하게 유지  
진행: Phase 단위, **phase 끝날 때마다 검증 게이트** 후 다음 phase

## 배경 / 문제

사용자 보고 이슈 4개:

1. 새로 설치한 앱이 인덱싱되지 않아 그리드에 안 보임
2. 트랙패드 오므리기(pinch)가 네이티브처럼 자연스럽지 않음
3. 앱/폴더 DnD 시 히트 영역이 시각 아이콘보다 아래쪽이라, 아이콘 중심이 아니라 더 아래에서 드롭해야 재정렬됨
4. 애니메이션·UX가 네이티브스럽지 않음

### 네이티브 Launchpad 대비 (요약)

| 영역 | Apple (대략) | 현재 Launchpad 프로젝트 |
|------|----------------|-------------------------|
| 앱 인덱싱 | Applications 감시, 설치 직후 반영 | 부팅/수동 Refresh만. FSEvents 없음 (`docs/PRIORITIES.md` Skip) |
| 트랙패드 핀치 | 연속 progress로 화면 스케일 → 끝에서 commit/cancel | 비율 임계 one-shot → `show()`/`hide()` |
| DnD 히트 | 아이콘 이미지 중심 | Core는 아이콘 중심이나 App이 `y + dragDropLowerBias(18)` 적용 |
| 애니/UX | 제스처 연동 progress + morph | one-shot lifecycle + 거친 spring. Phase 4로 미뤄둔 상태 |

### 코드상 원인 후보

- **인덱싱:** `AppState.refreshAppsAsync` 호출이 부팅·설정·수동·언어/소스 변경에 한정. `show` 시 재스캔 없음. (`Catalog/AppState+Catalog.swift`, `AppDelegate` startup)
- **핀치:** `TrackpadGestureMonitor` → `TrackpadIntent` / `TrackpadGestureSession` → `AppDelegate+Input` one-shot open/close. continuous progress 없음. (`docs/PRIORITIES.md` P3, `docs/PHASES.md` Phase 4)
- **DnD Y:** `GridDropResolution.dropResolution`이 Core 호출 전 `LaunchConstants.Launcher.dragDropLowerBias`(+18) 적용
- **UX:** `LauncherLifecycle` presentation, `LaunchConstants.Animation`, folder entrance — 튜닝/연속 제스처 연동 부족

## 목표

이번 사이클에서 네 이슈를 **A 경로**로 고치고, phase마다 검증한다.

1. DnD 히트가 아이콘 시각 중심과 맞음
2. 런처를 다시 열면 새로 설치한 앱이 보임 (재시작 불필요)
3. 핀치 중 런처가 손가락에 맞춰 progress되고, 끝에서만 commit/cancel
4. 열기/닫기·아이콘 lift·폴더 등장이 덜 거칠게 느껴짐

구조적으로는 순수 규칙을 `LaunchCore`에 모아 이후 C( hit-test 엔진 / FSEvents watcher / gesture state machine )로 키울 수 있게 한다.

## 비목표 (YAGNI)

- FSEvents / background catalog watcher (C 이후)
- 폴더 내부 재정렬, drag-out 고도화, spring-loaded 전체 재구현
- 새 애니메이션 프레임워크, 테마 시스템
- DnD geometry 엔진 전면 재작성
- 4/5손가락 핀치를 macOS와 완벽히 공유하는 것 (충돌 시 3손가락 + F4/핫코너가 신뢰 경로)

## 접근 방식

**채택: Approach A (최소 수정, phase 게이트)**  
각 phase에서 원인에 가장 가까운 경로만 고친다. 입구는 하나로 유지해 이후 C가 같은 API를 부르게 한다.

**보류: Approach B** — FSEvents + Multitouch 강화 + folder morph 풀셋 (phase가 커져 검증이 흐려짐)

**이후 목표 형태: Approach C** — geometry/gesture/catalog를 엔진형으로 승격. 이번 사이클에서는 인터페이스만 C-ready로 둔다.

### Phase 순서

```text
Phase1 DnD hit  --gate--> Phase2 catalog show-refresh --gate-->
Phase3 pinch progress --gate--> Phase4 motion polish --done-->
(later C: FSEvents / gesture state machine / hit-test engine)
```

이유: (1) 원인 명확·범위 작음 (2) 기능 결함 (3) 입력 모델 변경 (4) 1–3 위 폴리시.

## 아키텍처 경계 (유지)

- `LaunchCore` = Foundation only, 순수 규칙 + `LaunchpadCheck` / `LaunchpadCoreTests`
- `LaunchApp` = AppKit, SwiftUI, persistence, permissions, system
- `AppState` = 단일 observable UI 모델
- `LauncherLifecycle` = show/hide/presentation 소유
- SwiftUI → `AppState`; AppKit 부작용 → `LauncherActions`

## Phase 1 — DnD Y 히트

### 변경

1. `GridDropResolution.dropResolution`에서 Y bias 적용 제거. Core에 아이콘 중심을 그대로 전달.
2. `LaunchConstants.Launcher.dragDropLowerBias` 삭제 (죽은 상수 남기지 않음).
3. `GridDropGeometryTests` 회귀 유지/보강: 아이콘 중심에서 merge/reorder.
4. Core의 미사용 `labelHeight` / `iconLabelSpacing` 파라미터는 Phase 1에서 정리하지 않음 (C에서 icon-only vs cell 정책으로 정리).

### 성공 기준

- A B C 재정렬 시 **아이콘 이미지 중앙** 근처에서 insertion/reorder
- 앱→앱 폴더 생성, 앱→폴더 추가가 아이콘 위에서 동작
- 라벨만 가리킨 채 merge가 과발화하지 않음 (기존 icon-center 정책)

### 검증 게이트

```sh
swift build
swift run LaunchpadCheck
swift test
```

수동: 같은 페이지 재정렬, 폴더 생성/추가, 취소 드래그 후 opacity 복구.

### 이후 C

`GridDropGeometry`를 cell pick / icon hit / insertion band로 분리. bias·padding은 Core 입력으로만.

## Phase 2 — 새 앱 인덱싱

### 변경

1. `LauncherLifecycle.show()`에서 `state.refreshAppsAsync(priority: .utility, delay: …)` 호출.
2. Debounce: 마지막 성공 스캔 후 N초(권장 2–5s) 안이면 skip.
3. 기존 경로 유지: Settings/메뉴 Refresh, 소스 add/remove, 부팅 refresh.
4. `applyScannedApps`의 `scanned == apps` early return 유지. 새 앱은 기존 `ordered + missing`로 맨 끝 추가.
5. Watcher 타입/프로토콜 추가하지 않음. 이후 FSEvents가 같은 `refreshAppsAsync`만 호출.

### 성공 기준

- `/Applications`에 설치 후 런처를 다시 열면 새 아이콘 표시 (재시작 불필요)
- 짧은 연속 show/hide로 스캔 폭주 없음
- 숨김/폴더 소속 규칙은 기존과 동일

### 검증 게이트

동일 빌드 3종 + 수동: 앱 설치/복사 후 show, Settings Refresh, 레이아웃/폴더 유지.

### 이후 C

`CatalogWatcher` (FSEvents on default+extra roots) → debounce → `refreshAppsAsync`. show 시 refresh는 fallback.

## Phase 3 — 트랙패드 오므리기

### 변경

1. **LaunchCore continuous progress:** 세션이 progress(또는 scale)를 갱신. 제스처 중 commit 안 함. 끝에서 threshold로 commit/cancel.
2. **LaunchApp:** progress → `LauncherLifecycle` presentation scale/alpha 재사용. tracking 중 one-shot open/close 억제.
3. **활성화 계약 유지:** F4/핫코너 = 신뢰 경로. Trackpad Automatic/`[3,4]`, 충돌 시 reserve, 명시 3손가락은 reserve 안 함. Multitouch 실패 시 `.magnify` one-shot은 fallback.
4. 임계/쿨다운은 `LaunchConstants.Multitouch` + Core 테스트로 고정. 큰 리라이트 없음.

### 성공 기준

- 오므리기 중 런처가 손가락에 맞춰 스케일(또는 fade+scale)
- 임계 미달로 손 떼면 열리지 않고 복귀
- 3손가락 모드 안정. 4/5는 best-effort
- 페이지 스와이프·아이콘 드래그와 충돌하지 않음

### 검증 게이트

동일 빌드 3종 + 수동: 3손가락 pinch in/out, 중간 취소, F4/핫코너 회귀, 드래그 중 핀치.

### 이후 C

제스처 상태머신(`idle → tracking → committing/cancelling`), page swipe와 progress 모델 공유.

## Phase 4 — 애니/UX 폴리시

### 변경

1. Lifecycle presentation 스프링을 Phase 3 progress와 맞춤 (`response`/`damping` 튜닝). token 규칙 유지.
2. 아이콘 `iconLift` / 드롭 안착, ghost opacity·취소 복구 재확인.
3. 폴더: 기존 folder spring + dim dismiss. `matchedGeometryEffect` morph는 가벼우면 포함, `FolderOverlay` 비대화 시 다음 사이클로 미룸.
4. 새 애니 프레임워크 / live reflow 엔진 / spring-loaded 재구현 없음.

### 성공 기준

- 열기/닫기·페이지 스냅·아이콘 lift가 덜 끊김
- ESC / dim / 드래그 취소가 애니 때문에 깨지지 않음
- Phase 1–3 회귀 없음

### 검증 게이트

동일 빌드 3종 + 수동: 폴더 dim 닫기, ESC 순서, 드래그 opacity, 페이지 스와이프 vs 아이콘 드래그.

## 리스크와 완화

| 리스크 | 완화 |
|--------|------|
| bias 제거 후 merge 과민 | Core 테스트 + merge scale만 미세 조정 |
| show마다 스캔 버벅임 | debounce + `.utility` + early return |
| continuous pinch vs show/hide 경쟁 | lifecycle token + tracking 중 one-shot 억제 |
| Phase 4가 FolderOverlay를 키움 | morph 보류, 상수/스프링만 |

## Done 정의

- Phase 1–4 각각 검증 게이트 통과
- 네 이슈 수동 체크 통과
- `swift build` / `swift run LaunchpadCheck` / `swift test` 최종 통과
- 필요 시 `Scripts/build-app.sh`로 번들 확인
- 이 스펙 기준으로 implementation plan 작성 후 phase 단위 구현

## 관련 문서

- `docs/PRIORITIES.md` — P0–P4, Skip background watcher
- `docs/PHASES.md` — lifecycle, Phase 3 swipe / Phase 4 native feel
- `docs/ARCHITECTURE.md` — Core/App 경계
- `docs/superpowers/plans/2026-06-29-trackpad-launch-gesture.md` — 활성화 계약
- `docs/superpowers/specs/2026-06-25-folder-dnd-native-design.md` — 폴더 DnD (별도 트랙)
