# MVP

LaunchOS 느낌의 macOS Launchpad 대체 앱. Pro/결제/라이선스 없음.

## Phase 0 - Project

- [x] SwiftPM macOS app scaffold
- [x] MVP phase tracker
- [x] Minimal `LaunchCheck` runnable check

## Phase 1 - Launcher Shell

- [x] Borderless fullscreen window
- [x] Liquid Glass-style blurred background
- [x] Menu bar trigger
- [x] ESC close

## Phase 2 - Apps

- [x] Scan `/Applications`, `/System/Applications`, `~/Applications`
- [x] Deduplicate apps
- [x] 7x5 icon grid
- [x] Search
- [x] Launch selected app

## Phase 3 - Layout

- [x] Page dots and horizontal paging
- [x] Drag reorder
- [x] Persist layout

## Phase 4 - Folders

- [x] Drop app on app to create folder
- [x] Glass folder overlay
- [x] Launch apps inside folder

## Phase 5 - Trackpad

- [x] 4-finger pinch open via macOS pinch event
- [x] Spread close
- [x] Horizontal swipe page navigation

Note: public `NSEvent` does not expose finger count. Private MultitouchSupport is required if exact 4-finger-only detection is mandatory.

## Phase 6 - Polish

- [x] Icon cache
- [x] Settings window
- [x] Login item
- [x] Performance pass

Note: login item uses `SMAppService.mainApp`; final validation needs a bundled app build, not only `swift run`.
