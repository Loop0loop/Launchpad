# Native Parity Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix DnD hit Y bias, show-time catalog refresh, continuous trackpad pinch, and light motion polish per `docs/superpowers/specs/2026-07-09-native-parity-fixes-design.md`.

**Architecture:** A-path minimal fixes; keep pure rules in `LaunchpadCore`; App wires lifecycle/input. Gate after each phase before continuing.

**Tech Stack:** Swift 6.2, SwiftPM, AppKit/SwiftUI, LaunchpadCheck, LaunchpadCoreTests

## Global Constraints

- `LaunchCore` imports Foundation only
- No FSEvents / new animation framework in this cycle
- Phase gate: `swift build` + `swift run LaunchpadCheck` + `swift test` + phase manual checks
- Production Swift files stay under ~300 lines; do not grow `FolderOverlay` for morph unless trivial

---

## File Map

| Phase | Touch |
|-------|--------|
| 1 | `GridDropResolution.swift`, `LaunchConstants.swift`, `GridDropGeometryTests.swift` (if needed) |
| 2 | `LauncherLifecycle.swift`, `AppState+Catalog.swift` (debounce state) |
| 3 | `TrackpadGestureSession.swift`, `TrackpadIntent.swift`, `TrackpadGestureMonitor.swift`, `AppDelegate+Input.swift`, `LauncherLifecycle.swift`, tests |
| 4 | `LaunchConstants.Animation`, lifecycle/icon springs only |

---

### Task 1: Phase 1 — Remove DnD Y bias

**Files:**
- Modify: `Sources/LaunchApp/Layout/GridDropResolution.swift`
- Modify: `Sources/LaunchApp/Shared/LaunchConstants.swift`
- Optionally reinforce: `Tests/LaunchCoreTests/GridDropGeometryTests.swift`

- [x] **Step 1: Confirm Core icon-center tests still define the contract**

Note: host has Command Line Tools only (no XCTest). Rely on existing `GridDropGeometryTests` as the contract and `LaunchpadCheck` for executable assertions.

- [x] **Step 2: Remove App-layer Y bias**

In `dropResolution(at:layout:)`, pass `iconCenter` directly to `GridDropGeometry.resolve` (no `y + dragDropLowerBias`).

Delete `LaunchConstants.Launcher.dragDropLowerBias`.

- [x] **Step 3: Phase 1 gate**

```sh
swift build && swift run LaunchpadCheck
```

(`swift test` blocked without Xcode XCTest on this machine.)

Manual: reorder A↔C at icon center; folder create/add; cancel drag opacity.

- [ ] **Step 4: Commit Phase 1**

```sh
git add Sources/LaunchApp/Layout/GridDropResolution.swift Sources/LaunchApp/Shared/LaunchConstants.swift docs/superpowers/plans/2026-07-09-native-parity-fixes.md
git commit -m "fix: align grid drop hit with icon center"
```

---

### Task 2: Phase 2 — Refresh catalog on show

**Files:**
- Modify: `Sources/LaunchApp/App/LauncherLifecycle.swift`
- Modify: `Sources/LaunchApp/Catalog/AppState+Catalog.swift` (last refresh timestamp / debounce)

- [ ] **Step 1: Add debounce helper on AppState**

e.g. `lastCatalogRefreshAt` + `refreshAppsAsyncIfStale(minInterval:)` wrapping existing `refreshAppsAsync`.

- [ ] **Step 2: Call from `LauncherLifecycle.show()`**

Use `.utility` priority; keep existing startup/manual paths.

- [ ] **Step 3: Phase 2 gate + commit**

```sh
swift build && swift run LaunchpadCheck && swift test
```

Manual: install/copy app → reopen launcher → icon appears.

```sh
git commit -m "fix: refresh app catalog when launcher shows"
```

---

### Task 3: Phase 3 — Continuous pinch progress

**Files:**
- Modify: `Sources/LaunchCore/TrackpadGestureSession.swift` (and/or new small progress type)
- Modify: `Sources/LaunchApp/Input/TrackpadGestureMonitor.swift`
- Modify: `Sources/LaunchApp/AppDelegate/AppDelegate+Input.swift`
- Modify: `Sources/LaunchApp/App/LauncherLifecycle.swift`
- Modify: `Tests/LaunchCoreTests/TrackpadIntentTests.swift` / Check assertions

- [ ] **Step 1: TDD Core progress (update while tracking, commit/cancel on end)**
- [ ] **Step 2: Wire progress to presentation scale; suppress one-shot while tracking**
- [ ] **Step 3: Keep magnify one-shot as fallback only**
- [ ] **Step 4: Phase 3 gate + commit**

```sh
git commit -m "feat: continuous trackpad pinch progress for open/close"
```

---

### Task 4: Phase 4 — Motion polish

**Files:**
- Modify: `Sources/LaunchApp/Shared/LaunchConstants.swift` (Animation / Lifecycle springs)
- Touch lightly: `LauncherLifecycle.swift` only if needed for progress-aligned curves
- Avoid growing `FolderOverlay.swift` unless trivial

- [x] **Step 1: Tune springs; verify drag opacity restore**
- [x] **Step 2: Final gate + commit**

```sh
swift build && swift run LaunchpadCheck
git commit -m "polish: tune launcher presentation and icon lift motion"
```

---

## Done

All four phase gates green; four user issues manually verified; optional `Scripts/build-app.sh`.
