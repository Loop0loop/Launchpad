# Lifecycle And Phases

This document defines the runtime lifecycle and the next implementation phases.
Architecture details live in `docs/ARCHITECTURE.md`.

## Runtime Lifecycles

### 1. Boot Lifecycle

```text
Launch/main.swift
  -> NSApplication.shared
  -> AppDelegate
  -> applicationDidFinishLaunching
  -> create launcher window
  -> create menu bar item
  -> wire LauncherActions
  -> request permissions
  -> start global hotkey / hot corner / trackpad / keyboard monitors
  -> wait hidden
```

Boot must leave the launcher hidden and ready.

### 2. Launcher Window Lifecycle

`LauncherLifecycle` is the only owner of launcher window presentation.

State machine:

```text
hidden
  -> showing
  -> shown
  -> hiding
  -> hidden
```

Rules:

- `show()` is ignored while already `showing` or `shown`.
- `hide()` is ignored while already `hidden` or `hiding`.
- Every transition gets a token.
- Animation completion mutates state only when its token is still current.
- `dismiss()` skips animation and moves straight to `hidden`.

This prevents quick gesture/menu toggles from letting stale animation completions
hide the launcher after a newer show.

### 3. Input Lifecycle

Input sources become app actions:

```text
global hotkey
menu bar
hot corner
trackpad gesture
keyboard
mouse monitor
SwiftUI/AppKit controls
  -> AppDelegate / AppState
  -> LauncherLifecycle or domain action
```

Guidelines:

- Trackpad gestures call lifecycle/page actions only.
- Keyboard is handled in `AppDelegate.handleLauncherKey`.
- Search field focus stays in `SearchFocusController`.
- Mouse background dismiss/page drag stays in `LauncherMouseMonitor`.
- SwiftUI icon/folder actions call `AppState`.

### 4. Catalog And Layout Lifecycle

```text
refresh
  -> scan apps
  -> clean stale folders/order
  -> persist cleaned folders/order
  -> derive visibleItems
  -> render current page
```

Search is a temporary app-only projection. It does not mutate saved layout.

### 5. Folder Lifecycle

```text
app on app
  -> create folder
  -> persist
  -> open overlay

app on folder
  -> add app
  -> persist
  -> keep overlay open

remove from folder
  -> remove app
  -> dissolve folder if one app remains
  -> persist
```

Folder membership lives in `AppState.folders`; visual overlay state is temporary.

### 6. Settings Lifecycle

Settings window is lazy:

```text
menu Settings
  -> create NSWindow once
  -> attach SettingsView
  -> center and show
```

Settings write directly to `AppState`; persisted settings save in property
observers or domain stores.

## Current Phase Status

### Done

- Domain-oriented folder layout under `Sources/LaunchApp`.
- `LaunchCore` pure rules.
- `LaunchpadCheck` smoke assertions.
- Launcher lifecycle object.
- Menu bar item and right-click menu.
- Trackpad open/close/page gestures.
- Search field focus controller.
- Mouse monitor for background dismiss and page drag.
- Folder create/add/remove/dissolve.
- Folder drag-out (pull an app back to the grid; the grid shows through as the panel
  dissolves, then pages to where it lands).
- Folder internal reorder (drop maps to a slot via `GridGeometry.cellIndex`).
- Edge paging while dragging an icon, owned by `LauncherMouseMonitor`.
- Tahoe-style folder panel using macOS 26 glass APIs with fallback material.
- Repeatable app bundle build script.

### Active Quality Rules

- Keep one implementation concrete. No protocols until a second implementation exists.
- Keep system APIs behind `AppDelegate`, `LauncherLifecycle`, or domain adapters.
- Keep pure rules in `LaunchCore`.
- Add `LaunchpadCheck` assertions or focused `LaunchpadCoreTests` for new pure behavior.
- Run all default checks before calling work done.

Default checks:

```text
swift build
swift run LaunchpadCheck
swift test
Scripts/build-app.sh
swift run Launchpad
```

## Next Phases

These phases close the "native Launchpad feel" gaps. The drag engine
(`DragModel`, `beginItemDrag`/`updateItemDrag`/`endItemDrag`, `dropResolution`)
and glass/lifecycle work already exist; each phase below extends them, it does
not rebuild them. Order is by ROI: cheapest extension of existing code first.

### Phase 1 - Edge Paging During Drag

Goal: dragging an icon to the left/right screen edge flips the page so an app
can be moved across pages. Today a drag is stuck on the page it started on.

- Detect when the drag pointer enters a fixed edge band (left/right).
- Single dwell timer (~0.6s) advances/retreats `currentPage`, then re-arms.
- Cancel the timer when the pointer leaves the band, drops, or the drag cancels.
- `dropResolution` keeps targeting the now-visible page.
- Pure edge-band + page-step math lives in `LaunchCore`; assert in `LaunchpadCheck` or `LaunchpadCoreTests`.

Touches: `Layout/AppState+Layout.swift`, `Launcher/LauncherItemViews.swift`
(`LauncherDragModifier` already passes pointer location), `LaunchCore`.

Stop condition: one dwell timer, fixed band width, no auto-scroll animation engine.

### Phase 2 - Folder Internal Reorder

Goal: reorder apps inside an open folder by drag. Drag-out and dissolve already
work (`FolderOverlayAppIcon` pull-out, `removeApp(_:fromFolder:)`).

- Pure reorder rule over `folder.appIDs` in `LaunchCore`.
- `FolderOverlay` drag updates a preview index while dragging; commit on drop.
- Keep right-click `Remove from Folder`; keep one-app dissolve.
- Add `LaunchpadCheck` assertions or `LaunchpadCoreTests` for the new pure order rule.

Touches: `Launcher/FolderOverlay.swift`, `Layout/AppState+Layout.swift`, `LaunchCore`.

Stop condition: no nested folders, no custom animation engine.

### Phase 3 - Swipe Velocity And Inertia

Goal: page swipe follows the finger and commits by velocity, not distance alone.
`pageDragOffset` finger-follow and `Animation.pageSnap` already exist.

- On drag end, commit the page when velocity OR distance crosses threshold.
- Rubber-band back to the current page when neither threshold is met.
- Disable left/right swipe while searching.
- Pure threshold/velocity decision in `LaunchCore` (extend `TrackpadIntent`);
  assert in `LaunchpadCheck` or `LaunchpadCoreTests`.

Touches: `Input/LauncherMouseMonitor.swift`, `Input/TrackpadGestureMonitor.swift`,
`LaunchCore/TrackpadIntent.swift`.

Stop condition: one spring + two thresholds, no physics engine.

### Phase 4 - Native Feel Polish

Goal: the remaining visual native cues. Cosmetic, after interaction is solid.

- Folder open/close morph: tile expands into the panel via `matchedGeometryEffect`.
- `+n` overflow badge on the folder preview when apps exceed the 3x3 limit.
- Replace one-shot gesture intents with continuous progress while tracking,
  commit/cancel only on gesture end (open/close + page).

Touches: `Launcher/FolderOverlay.swift`, `Launcher/LauncherItemViews.swift`,
`Input/TrackpadGestureMonitor.swift`, `App/LauncherLifecycle.swift`.

Stop condition: no custom animation framework, no theme system.

### Phase 5 - Localization

Goal: remove hardcoded user-facing English strings.

- Add `Localizable.strings`.
- Move menu, settings, folder, alert, and search placeholder text.
- Keep model/default persisted values stable.

Stop condition: no language picker until the system language path works.

### Phase 6 - Logging Cleanup

Goal: keep diagnostics without noisy production output.

- Gate high-volume gesture/mouse logs.
- Keep startup and failure logs.
- Keep enough logs to debug tray, lifecycle, and trackpad issues.

Stop condition: no custom logging framework.

### Phase 7 - Packaging Hardening

Goal: make app-bundle usage reliable.

- Keep `Scripts/build-app.sh`.
- Verify resources are copied.
- Verify launch-at-login from app bundle.
- Add signing/notarization only when distribution starts.

Stop condition: no updater work beyond existing Sparkle wiring.

## Done Definition

A phase is done when:

- behavior works manually where UI is involved
- `swift build` passes
- `swift run LaunchpadCheck` passes
- `swift test` passes
- `Scripts/build-app.sh` passes
- `swift run Launchpad` starts without immediate crash
- docs are updated when lifecycle or ownership changes
