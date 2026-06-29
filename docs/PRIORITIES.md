# Priorities And Review Policy

This file defines what matters first when changing Launch.

## Policy

### P0 - Must Not Break

- App starts without an immediate crash.
- Launcher opens and closes.
- App launch does not restore the previous app over the launched app.
- Menu bar item works, including right-click menu.
- No stale lifecycle animation completion can hide a newer launcher state.

Required checks:

```text
swift build
swift run LaunchpadCheck
swift test
Scripts/build-app.sh
swift run Launchpad
```

### P1 - Core Launcher UX

- Search focuses only when clicked and accepts typing.
- Page navigation works through dots, keyboard/gesture, and mouse drag.
- Folder create/open/add/remove/dissolve works.
- Empty launcher space dismisses; app/folder/search clicks do not.
- Drag state is transient: cancel, failed drop, successful drop, launcher hide,
  and a fresh non-drag click must restore icon opacity.
- Drop policy is explicit:
  - app target creates a folder
  - folder target adds the app to that folder
  - root reorder is separate from folder create/add
- Grid icon drag is owned by SwiftUI gesture state, not pasteboard drag/drop.
  `LauncherMouseMonitor` only handles empty-space page dragging.

Required checks:

```text
swift build
swift run LaunchpadCheck
swift test
manual launcher interaction
```

### P2 - Persistence And Settings

- App sources, hidden apps, folders, order, grid, appearance, and mode persist.
- Refresh cleans stale app/folder/order state.
- Settings mutate `AppState` through existing stores.

Required checks:

```text
swift build
swift run LaunchpadCheck
swift test
manual restart when persistence changed
```

### P3 - Platform Polish

- macOS-style visual behavior.
- Tahoe/Liquid Glass path on macOS 26.
- Material fallback on older macOS.
- Text remains readable and fits.
- Menu/window behavior follows platform expectations.
- Native-grade gestures should use continuous progress state while tracking and
  commit/cancel only at the end of the gesture. Threshold-only one-shot intents
  are acceptable as a fallback, not the final interaction model.

Required checks:

```text
swift build
Scripts/build-app.sh
manual visual check
```

### P4 - Later

- Internal folder reorder.
- Drag-out folder removal.
- Full geometry-driven drag engine for Launchpad-style reorder if SwiftUI
  `onDrag`/`onDrop` remains too limited.
- Localization.
- Logging cleanup.
- Signing/notarization.
- Import/export or file-based persistence.

Do not build P4 before P0-P2 are stable.

## Swift Review Rules

Use these when reviewing code:

- Clarity at use site beats clever brevity.
- Use role names, not type names, when parameters are weakly typed.
- Keep side-effecting methods as verb phrases.
- Keep pure layout/folder/gesture rules in `LaunchCore`.
- Keep AppKit references out of `LaunchCore`.
- Keep UI mutation on the main actor.
- Avoid protocol layers until there are two real implementations.
- Avoid force casts and `try!`.
- Guard private API usage with public fallback.
- Add one `LaunchpadCheck` assertion or `LaunchpadCoreTests` case for new pure behavior.
- Keep production Swift files under 300 lines. When a file grows beyond that,
  split by domain before adding more behavior.
- Use Swift-style domain entry files, not barrel/export files. `main.swift`
  belongs only to executable entry points.
- Keep each domain near five Swift files by default; split a subdomain or
  document the exception when a UI-heavy domain needs more.

Official references:

- Swift API Design Guidelines: https://www.swift.org/documentation/api-design-guidelines/
- Swift memory safety: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/memorysafety/
- Swift 6 data-race safety: https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/dataracesafety/
- SwiftUI model data: https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
- Apple Human Interface Guidelines for macOS: https://developer.apple.com/design/human-interface-guidelines/macos

## Current Cleanup Queue

### Now

- Keep lifecycle phase/token behavior stable.
- Keep grid hit testing aligned with `LaunchpadLayoutMetrics`.
- Split large UI/AppKit files by domain before adding behavior.
- Reduce high-volume `LaunchLog.line` calls after input UX settles.
- Keep folder UX focused: close by dim click, create, add, remove, dissolve.
- Fix stale drag opacity before adding larger drag features.
- Keep grid drag geometry centralized in `LaunchpadLayoutMetrics`-based helpers.

### Next

- Add folder internal reorder.
- Add drag-out removal.
- Replace one-shot gesture intents with continuous progress for native-feeling
  page and launch gestures.
- Add `Localizable.strings`.
- Verify app bundle resources after icon/menu icon changes.

### Skip For Now

- New SwiftPM targets.
- Repositories/services/protocols for one implementation.
- Custom logging framework.
- Theme system.
- File-based persistence.
- Background catalog watcher.
