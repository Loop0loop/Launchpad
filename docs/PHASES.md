# Phases

This plan starts after the MVP in `MVP.md`. Each phase must leave the app
buildable and gets one commit.

## Architecture Target

Keep domain boundaries:

- **Launch**: executable entry only.
- **LaunchApp**: native app domains grouped by product area.
- **AppState**: user-visible state in one file, actions split into domain
  extensions.
- **Core**: `LaunchCore` pure rules checked by `LaunchCheck`.

Do not add protocol layers until there are two real implementations. Do not
split into more SwiftPM targets until dependency cycles prove the need.

## Lifecycle Target

The app has four stable runtime loops:

1. **Boot loop**
   `NSApplication` starts, creates windows/status item, asks for permissions,
   starts monitors, then waits hidden.

2. **Launcher loop**
   trigger opens launcher, stores previous app, handles search/grid/folders,
   then closes back to the previous app unless an app was launched.

3. **Catalog loop**
   app scan builds `LaunchApp` list, applies folders and order, then feeds the
   grid. Refresh is manual for now.

4. **Input loop**
   global/local events become `TrackpadIntent`, then state actions. Private
   4-finger data only gates public magnify events.

## Phase A - File Boundaries

Goal: make architecture visible in the filesystem without changing behavior.

- Keep `AppState` storage in `Sources/LaunchApp/App/AppState.swift`.
- Move state actions into domain extensions such as `Catalog/AppState+Catalog.swift`.
- Move SwiftUI, AppKit, persistence, permissions, and input code under domain
  directories.
- Do not keep a top-level `Adapters` directory.
- Keep `main.swift` as app bootstrap only.
- Run `swift run LaunchCheck`, `swift build`, `Scripts/build-app.sh`.
- Commit: `refactor: split SPA boundaries`.

Stop condition: no behavior changes.

## Phase B - Lifecycle Coordinator

Goal: make open/close/toggle/app-launch paths explicit.

- Add one `LauncherLifecycle` adapter.
- It owns previous app, show, hide, dismiss, toggle.
- `AppState` keeps callbacks but does not know AppKit windows.
- ESC, menu toggle, spread, and app launch use the same lifecycle paths.
- Run checks and build.
- Commit: `refactor: define launcher lifecycle`.

Stop condition: no new settings, no animation work.

## Phase C - Permission Lifecycle

Goal: make gesture permissions understandable and recoverable.

- Add `PermissionState` in `AppState`.
- Track Accessibility trusted/prompted/denied-ish states.
- Settings shows the current state and retry action.
- Trackpad monitor reports whether 4-finger gate is active or fallback.
- Run checks and build.
- Commit: `feat: clarify permission lifecycle`.

Stop condition: do not add onboarding screens.

## Phase D - Catalog Lifecycle

Goal: make app scan, layout, and folders stable enough for real use.

- Extract `CatalogStore` adapter for scan/refresh.
- Extract `LayoutStore` adapter for order/folders persistence.
- Keep UserDefaults unless import/export is added.
- Add stale-app cleanup when an app path disappears.
- Run checks and build.
- Commit: `refactor: isolate catalog lifecycle`.

Stop condition: no background file watcher yet.

## Phase E - Input Lifecycle

Goal: make trackpad and scroll behavior less fragile.

- Extract `TrackpadGestureMonitor` to adapter file.
- Add one debounce/throttle rule in `LaunchCore` if needed.
- Keep public `NSEvent` fallback.
- Add status logging only behind a debug flag if needed.
- Run checks and build.
- Commit: `refactor: isolate input lifecycle`.

Stop condition: no new gesture engine.

## Phase F - Visual Lifecycle

Goal: make the launcher feel like one screen, not a pile of controls.

- Add open/close scale-opacity transition.
- Add page transition animation.
- Keep current NSVisualEffectView glass.
- Verify text still fits app/folder icons.
- Run checks and build.
- Commit: `feat: polish launcher transitions`.

Stop condition: no theme/settings system.

## Phase G - Packaging Lifecycle

Goal: make `.app` use repeatable.

- Keep `Scripts/build-app.sh`.
- [x] Add `Scripts/run-app.sh`.
- [x] Add bundle identifier/version notes.
- Confirm login item behavior from `.build/Launch.app`.
- Run checks and build.
- Commit: `build: tighten app packaging`.

Stop condition: no signing/notarization until distribution starts.

## Done Definition

Every phase must prove:

- `swift run LaunchCheck` passes.
- `swift build` passes.
- `Scripts/build-app.sh` passes.
- `git status --short` is clean after commit.
