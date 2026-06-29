# Launchpad
![alt text](public/img/ex.png)
[한국어](README.md)

Launchpad is a native macOS app launcher for macOS 26. It aims to bring back the feel of Apple's Launchpad: smooth gestures, page transitions, folders, search, and drag-and-drop organization.

## Features

- Scans `/Applications`, `/System/Applications`, and `~/Applications`
- Launchpad-style 7x5 paged grid
- App search and keyboard navigation
- Launch apps, show in Finder, add to Dock, or move to Trash
- Drag to reorder apps
- Drop app onto app to create folders
- Add, remove, reorder, and rename apps inside folders
- Page dots, mouse drag paging, and trackpad swipe paging
- 4/5-finger trackpad pinch/spread open and close
- F4 key, global hotkey, menu bar item, and hot corner support
- Native Launchpad layout import
- Grid, appearance, and app source settings
- Downsampled icon cache and scoped SwiftUI update paths for performance

## Run

Build the local app bundle:

```sh
Scripts/build-app.sh
open .build/Launchpad.app
```

You can also run through SwiftPM:

```sh
swift run Launchpad
```

Use `.build/Launchpad.app` when testing features tied to the app bundle identity, such as login items, accessibility permission, and global hotkeys.

## Verification

Run these after code changes:

```sh
swift build
swift run LaunchpadCheck
```

For app bundle checks:

```sh
Scripts/build-app.sh
open .build/Launchpad.app
```

Manual checks:

- Clicking empty background closes the launcher or open folder.
- ESC closes folder, search, and launcher in order.
- Dragging app onto app creates a folder.
- Dragging app onto folder adds it to the folder.
- Failed or cancelled drag restores icon opacity.
- Page swipe does not fight icon drag.

## Architecture

```text
Launch        executable entry point
LaunchApp     AppKit, SwiftUI, input, permissions, settings, system integration
LaunchCore    pure rules that import Foundation only
LaunchpadCheck executable checks for LaunchCore rules
```

Rules:

- `LaunchCore` imports `Foundation` only.
- AppKit, SwiftUI, permissions, persistence, and system APIs live in `LaunchApp`.
- `AppState` is the single observable UI model.
- `AppDelegate` owns process-level AppKit wiring.
- SwiftUI views call `AppState`; AppKit side effects go through `LauncherActions`.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

## Packaging

Build an app bundle:

```sh
swift run LaunchpadPackager app
```

Build a DMG:

```sh
swift run LaunchpadPackager dmg
```

Signing and notarization are documented in [docs/PACKAGING.md](docs/PACKAGING.md).

## Status

The project has moved past the MVP scaffold and is focused on real interaction quality: native-feeling gestures, smooth page transitions, reliable folder dragging, and low memory use.

## license
MIT
