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
- `LaunchCheck` smoke assertions.
- Launcher lifecycle object.
- Menu bar item and right-click menu.
- Trackpad open/close/page gestures.
- Search field focus controller.
- Mouse monitor for background dismiss and page drag.
- Folder create/add/remove/dissolve.
- Tahoe-style folder panel using macOS 26 glass APIs with fallback material.
- Repeatable app bundle build script.

### Active Quality Rules

- Keep one implementation concrete. No protocols until a second implementation exists.
- Keep system APIs behind `AppDelegate`, `LauncherLifecycle`, or domain adapters.
- Keep pure rules in `LaunchCore`.
- Add `LaunchCheck` assertions for new pure behavior.
- Run all default checks before calling work done.

Default checks:

```text
swift run LaunchCheck
swift build
Scripts/build-app.sh
swift run Launch
```

## Next Phases

### Phase 1 - Folder UX Completion

Goal: finish the minimum Launchpad-like folder interactions.

- Add reorder inside folder.
- Add drag-out removal from folder.
- Keep right-click `Remove from Folder`.
- Keep dissolve behavior when one app remains.
- Add `LaunchCheck` assertions for new pure order rules.

Stop condition: no nested folders, no custom animation engine.

### Phase 2 - Localization

Goal: remove hardcoded user-facing English strings.

- Add `Localizable.strings`.
- Move menu, settings, folder, alert, and search placeholder text.
- Keep model/default persisted values stable.

Stop condition: no language picker until the system language path works.

### Phase 3 - Logging Cleanup

Goal: keep diagnostics without noisy production output.

- Gate high-volume gesture/mouse logs.
- Keep startup and failure logs.
- Keep enough logs to debug tray, lifecycle, and trackpad issues.

Stop condition: no custom logging framework.

### Phase 4 - Packaging Hardening

Goal: make app-bundle usage reliable.

- Keep `Scripts/build-app.sh`.
- Verify resources are copied.
- Verify launch-at-login from app bundle.
- Add signing/notarization only when distribution starts.

Stop condition: no updater.

### Phase 5 - Visual Polish

Goal: tune the current UI, not replace it.

- Verify folder panel on macOS 26 and older fallback.
- Tune text fit for long app/folder names.
- Tune windowed browsing mode.
- Keep existing SwiftUI/AppKit split.

Stop condition: no theme system.

## Done Definition

A phase is done when:

- behavior works manually where UI is involved
- `swift run LaunchCheck` passes
- `swift build` passes
- `Scripts/build-app.sh` passes
- `swift run Launch` starts without immediate crash
- docs are updated when lifecycle or ownership changes
