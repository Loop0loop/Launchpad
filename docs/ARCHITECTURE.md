# Architecture

Launch is a native macOS Launchpad replacement. The app uses SwiftUI for the
launcher surface, AppKit for process/window/event integration, and a small
`LaunchCore` module for pure rules that can be checked without a GUI.

Implementation phases live in `docs/PHASES.md`.

## References

Official Apple APIs:

- SwiftUI `NSViewRepresentable`: bridge AppKit views into SwiftUI.
  https://developer.apple.com/documentation/swiftui/nsviewrepresentable
- AppKit `NSWindow`: borderless launcher and settings windows.
  https://developer.apple.com/documentation/appkit/nswindow
- AppKit `NSEvent`: local/global gesture, scroll, and swipe monitors.
  https://developer.apple.com/documentation/appkit/nsevent
- Carbon Event Manager `RegisterEventHotKey`: process-level global hot key.
  https://developer.apple.com/documentation/carbon/1459912-registereventhotkey
- AppKit `NSWorkspace`: app scanning, app launch, frontmost app tracking.
  https://developer.apple.com/documentation/appkit/nsworkspace
- AppKit `NSVisualEffectView`: glass/blur material host.
  https://developer.apple.com/documentation/appkit/nsvisualeffectview
- ServiceManagement `SMAppService`: launch-at-login registration.
  https://developer.apple.com/documentation/servicemanagement/smappservice
- ApplicationServices Accessibility trust:
  https://developer.apple.com/documentation/applicationservices/1462083-axisprocesstrustedwithoptions

Repo references checked on 2026-06-23:

- `quicksilver/Quicksilver`: 2905 stars, mature macOS launcher, background
  catalog + command lifecycle.
  https://github.com/quicksilver/Quicksilver
- `ggkevinnnn/LaunchNow`: 792 stars, Swift Launchpad replacement.
  https://github.com/ggkevinnnn/LaunchNow
- `Punshnut/macos-launchy`: 146 stars, Swift open-source Launchpad alternative.
  https://github.com/Punshnut/macos-launchy
- `kristof12345/Launchpad`: 133 stars, Swift Launchpad-style grid.
  https://github.com/kristof12345/Launchpad

We borrow lifecycle ideas, not their internal structure. The local app stays
small until the code proves it needs more layers.

## SPA Clean Architecture

SPA here means **State, Presentation, Adapters**.

```text
Presentation  SwiftUI views, drag/drop delegates, glass UI
     |
     v
State         AppState: user-visible app state and actions
     |
     v
Core          LaunchCore pure models and rules
     ^
     |
Adapters      AppKit, NSWorkspace, UserDefaults, gestures, login item
```

Dependency rule:

- `LaunchCore` imports only `Foundation`.
- `Presentation` reads state and sends user actions to `AppState`.
- `AppState` owns current launcher state and calls adapters.
- Adapters are the only place for AppKit/system side effects.
- Views do not scan apps, write persistence, or talk to global monitors.

Current file boundaries:

```text
Sources/Launch/main.swift
Sources/LaunchApp/State/*.swift
Sources/LaunchApp/Presentation/*.swift
Sources/LaunchApp/Adapters/*.swift
Sources/LaunchCore/*.swift
```

## Modules

### `LaunchCore`

Pure code:

- `LaunchApp`: app identity, name, and path.
- `AppCatalog`: scans app bundles and extracts display names.
- `LayoutOrder`: applies and mutates app/folder ordering.
- `LaunchFolder` and `FolderLayout`: folder creation rules.
- `TrackpadIntent`: converts gesture deltas into launcher intents.

Rules:

- No AppKit.
- No UserDefaults.
- No global state.
- If behavior has branches, add one `LaunchCheck` assertion.

### `Launch`

Thin executable:

- imports `LaunchApp`
- creates `NSApplication` and `AppDelegate`
- runs the AppKit event loop

### `LaunchApp`

Native macOS app domain:

- `AppState`: observable state, derived grid items, persistence hooks, app
  launch, folder operations, permission/login state.
- SwiftUI views: launcher grid, app icon, folder icon, folder overlay,
  settings window.
- AppKit adapters: fullscreen window, status item, visual effect bridge,
  global hotkey, trackpad/global event monitor, Accessibility prompt, login item.

### `LaunchCheck`

One executable smoke check:

- validates fallback display name
- validates missing app roots
- validates layout order
- validates folder creation
- validates trackpad intent thresholds

This is deliberately not a test framework. The current Command Line Tools
environment does not expose XCTest/Swift Testing reliably.

## Runtime Lifecycle

### App Start

```text
NSApplication.shared
  -> AppDelegate.applicationDidFinishLaunching
  -> set accessory activation policy
  -> create borderless launcher window
  -> create menu bar status item
  -> connect AppState close/dismiss callbacks
  -> request Accessibility permission
  -> register global hotkey
  -> start trackpad monitor
```

The launcher no longer opens automatically on boot. The user triggers it from
the menu bar or trackpad.

### Open Launcher

```text
menu/hotkey/gesture
  -> AppDelegate
  -> LauncherLifecycle.show
  -> remember frontmost app
  -> clear search
  -> resize window to current screen
  -> make launcher key/front
  -> activate Launch
```

### Close Launcher

```text
ESC/spread/toggle
  -> AppDelegate
  -> LauncherLifecycle.hide
  -> order launcher window out
  -> reactivate previous app
```

Launching an app uses a different path:

```text
app icon click
  -> AppState.launch
  -> NSWorkspace.open(app.path)
  -> dismiss launcher without restoring previous app
```

That prevents the old app from stealing focus from the newly launched app.

### App Scan

```text
AppState.refreshApps
  -> AppCatalog.scan
  -> scan /Applications, /System/Applications, ~/Applications
  -> dedupe by bundle id or path
  -> sort by localized name
  -> preserve saved order in UserDefaults
```

### Grid Render

```text
AppState.visibleItems
  -> root apps excluding folder members
  -> folders with resolved child apps
  -> saved order
  -> current page slice
  -> SwiftUI LazyVGrid
```

Icons are cached in memory by app path. No disk cache yet.

### Search

```text
query changes
  -> currentPage = 0
  -> visibleApps filters by localized case-insensitive substring
  -> folders are hidden while searching
```

### Drag Reorder

```text
onDrag(app)
  -> state.draggedAppID = app.id

dropEntered(target)
  -> LayoutOrder.move
  -> save order

performDrop(target)
  -> if app-on-app: create folder
  -> else: keep reorder
```

### Folder Lifecycle

```text
app dropped on app
  -> FolderLayout.createFolder
  -> remove both apps from root order
  -> insert folder at earlier position
  -> persist folders as JSON in UserDefaults
  -> open folder overlay
```

Folder overlay is presentation only. Folder membership lives in `AppState`.

### Trackpad Lifecycle

```text
TrackpadGestureMonitor.start
  -> optional MultitouchSupport contact-count monitor
  -> NSEvent local/global monitors for magnify, swipe, scrollWheel
```

Intent mapping:

- 4-finger-gated pinch in: open launcher.
- 4-finger-gated spread: close launcher.
- horizontal swipe: previous/next page.
- horizontal scroll wheel: previous/next page.

`NSEvent` does not expose finger count, so exact 4-finger gating uses private
MultitouchSupport contact counts when available. If it is unavailable, pinch
falls back to public `NSEvent` behavior.

### Settings Lifecycle

```text
menu Settings
  -> create settings NSWindow lazily
  -> show SwiftUI SettingsView
```

Settings owns only MVP controls:

- launch at login
- app refresh
- Accessibility status and prompt

## Ownership Rules

Add code where it belongs:

- Pure ordering/folder/gesture threshold rule: `LaunchCore`.
- UI-only layout: SwiftUI view.
- System API call: adapter section in `Launch`.
- State mutation visible to UI: `AppState`.
- Build/run packaging: `Scripts` or `Resources`.

Do not add:

- repositories/interfaces for one implementation
- dependency injection containers
- coordinator trees
- disk icon cache before profiling proves memory cache is not enough
- a settings model separate from `AppState` before settings grows

## Known Architecture Debt

- `AppState` still owns several user actions and adapter callbacks.
  Split further only when one action needs a second implementation.
- Private MultitouchSupport is best-effort.
  Keep the public `NSEvent` fallback.
- `UserDefaults` is enough for MVP layout data.
  Move to JSON files only when import/export or user-visible backup exists.
