# Architecture

Launch is a native macOS Launchpad-style launcher.

The app is intentionally small:

```text
Launch      executable entry only
LaunchApp   AppKit/SwiftUI app domains
LaunchCore  pure rules checked by LaunchCheck
```

## Dependency Rules

- `LaunchCore` imports `Foundation` only.
- `Launch` creates `NSApplication`, installs `AppDelegate`, then runs AppKit.
- `LaunchApp` owns AppKit, SwiftUI, persistence, permissions, input, and UI.
- Pure rules go in `LaunchCore`; UI and system integration stay out of it.
- No top-level `Adapters` bucket. System-facing code lives in its product domain.

Current folders:

```text
Sources/Launch/main.swift
Sources/LaunchApp/App
Sources/LaunchApp/Appearance
Sources/LaunchApp/Catalog
Sources/LaunchApp/Input
Sources/LaunchApp/Launcher
Sources/LaunchApp/Layout
Sources/LaunchApp/Permissions
Sources/LaunchApp/Settings
Sources/LaunchApp/System
Sources/LaunchCore
Sources/LaunchCheck
```

## Core Model

`LaunchCore` contains rules that should be runnable without a GUI:

- `LaunchApp`: app identity, name, path.
- `AppCatalog`: app bundle scanning and display name lookup.
- `LayoutOrder`: root grid order mutations.
- `LaunchFolder` / `FolderLayout`: create folders, add apps, remove apps, dissolve small folders.
- `TrackpadIntent`: convert raw gesture deltas/ratios into launcher intents.

If a rule has meaningful branches, add a `LaunchCheck` assertion.

## App State

`AppState` is the single observable UI model.

It stores:

- app catalog and hidden apps
- folders and root order
- current page, selection, drag id
- search query
- permission states
- appearance and display settings
- launcher visibility and page drag offset

Actions are split by domain:

```text
App/AppState.swift                 stored state
Catalog/AppState+Catalog.swift     app scan/source/import actions
Input/AppState+Input.swift         keyboard/search/page actions
Layout/AppState+Layout.swift       order/folder actions
Permissions/AppState+Permissions.swift
System/AppState+System.swift       app launch/Finder/trash/Dock actions
```

`AppState` does not own windows directly. AppKit side effects are exposed through
`LauncherActions`, wired by `AppDelegate`.

## App Boundary

`AppDelegate` owns process-level objects:

- `AppState`
- `LauncherLifecycle`
- `IconCache`
- menu bar status item/menu
- settings window
- global hot key monitor
- hot corner monitor
- trackpad monitor
- launcher mouse monitor

`AppDelegate` wires `LauncherActions`:

```text
AppState action
  -> LauncherActions
  -> AppDelegate / LauncherLifecycle / AppSystemAdapter
```

This keeps SwiftUI views calling `AppState` while AppKit remains behind one boundary.

## Launcher Lifecycle

`LauncherLifecycle` owns window visibility and presentation state.

Internal phases:

```text
hidden -> showing -> shown -> hiding -> hidden
```

The phase and transition token prevent stale hide/show animation completions
from ordering the window out after a newer transition has started.

### Show

```text
menu / hotkey / gesture / hot corner
  -> AppDelegate
  -> LauncherLifecycle.show
  -> cancel old transition token
  -> phase = showing
  -> remember previous app
  -> clear search, folder, keyboard selection
  -> launcherVisible = true
  -> apply window mode and menu bar/Dock presentation
  -> prepare presentation layer
  -> order launcher window front
  -> enable launcher mouse monitor
  -> animate scale/alpha
  -> phase = shown
```

Opening does not focus search automatically. The launcher can receive keyboard
navigation without grabbing typed input until the user clicks search.

### Hide

```text
ESC / toggle / spread
  -> LauncherLifecycle.hide
  -> phase = hiding
  -> disable launcher mouse monitor
  -> animate scale/alpha out
  -> if transition token is still current:
       launcherVisible = false
       restore menu bar/Dock
       order window out
       reset presentation
       reactivate previous app
       phase = hidden
```

### Dismiss

`dismiss()` is immediate. It disables input, restores presentation options,
sets `launcherVisible = false`, orders the window out, and resets presentation.

Use it for non-animated cleanup paths.

### Launch App

```text
app icon click
  -> AppState.launch
  -> LauncherActions.launch
  -> LauncherLifecycle.launch
  -> AppSystemAdapter.launch
  -> animate/dismiss launcher without reactivating previous app
```

The previous app is not restored after launching a new app, otherwise it can
steal focus from the launched app.

## Input Lifecycle

Input is split by source:

- `GlobalHotKeyAdapter`: Carbon global hot keys.
- `HotCornerMonitor`: pointer polling.
- `TrackpadGestureMonitor`: local/global AppKit gesture monitors plus optional private multitouch contact counts.
- `LauncherMouseMonitor`: launcher-only mouse hit testing, background dismiss, page drag.
- `AppDelegate.handleLauncherKey`: keyboard navigation and type-to-search.
- `SearchFocusController`: AppKit search field refs and focus state.

Trackpad flow:

```text
NSEvent / MultitouchSupport
  -> TrackpadIntent
  -> AppDelegate
  -> LauncherLifecycle or AppState.changePage
```

Mouse flow:

```text
local mouse monitor
  -> ignore search and item cells
  -> page drag when on background
  -> background click dismiss
```

The mouse monitor computes item hits using real grid padding/column metrics.

## Rendering

`LauncherView` renders from `AppState`.

Main surface:

```text
LauncherBackgroundView
LauncherSearchField
PagedGridView or search results grid
LauncherPageControl
FolderOverlay when openFolder != nil
```

Folder overlay uses macOS 26 `GlassEffectContainer` / `glassEffect` when
available. Older systems fall back to `ultraThinMaterial`.

Search is an `NSViewRepresentable` AppKit search bar because SwiftUI focus and
hit testing were too fragile for this app.

## Catalog And Layout

Refresh flow:

```text
AppState.refreshApps
  -> CatalogStore.scanApps
  -> LayoutCleanup.cleanup
  -> save folders and order
  -> ensure selection
```

Visible item flow:

```text
apps - hidden - folder members
  + folders with resolved children
  -> saved root order
  -> current page slice
```

Search hides folders and ranks apps only.

Folder flow:

```text
drop app on app
  -> FolderLayout.createFolder
  -> save folders/order
  -> open overlay

drop app on folder
  -> FolderLayout.addApp
  -> save folders/order

remove app from folder
  -> FolderLayout.removeApp
  -> dissolve folder when only one app remains
```

## Persistence

MVP persistence is `UserDefaults`:

- app source paths
- hidden app ids
- root order
- folders
- grid layout
- display mode
- appearance settings
- window browsing mode

Move to files only when import/export or backup becomes a user feature.

## Verification

Default checks:

```text
swift run LaunchCheck
swift build
Scripts/build-app.sh
swift run Launch
```

`swift run Launch` is the only check that proves AppKit startup does not crash.

## Current Debt

- `AppState` remains the central model. Split only when a domain has real
  independent lifecycle or a second implementation.
- Private MultitouchSupport is best-effort. Keep public `NSEvent` fallback.
- Logging is intentionally direct while input/lifecycle behavior is still
  being tuned.
- Folder UX still lacks internal reorder and drag-out removal.
