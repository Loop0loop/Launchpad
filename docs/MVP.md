# MVP

LaunchOS 느낌의 macOS Launchpad 대체 앱. Pro/결제/라이선스 없음.

## Phase 0 - Project

- [x] SwiftPM macOS app scaffold
- [x] Minimal `.app` bundle builder
- [x] MVP phase tracker
- [x] Minimal `LaunchpadCheck` runnable check

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

## Phase 5 - Trackpad And Activation

- [x] Automatic plus 3/4/5-finger pinch open via MultitouchSupport-gated macOS pinch event
- [x] Spread close
- [x] Horizontal swipe page navigation
- [x] F4/global hotkey and hot corner fallbacks

Note: exact finger-count gating uses private MultitouchSupport contact counts,
with a public `NSEvent` pinch fallback when unavailable. 4/5-finger modes try
to reserve Apple's native Launchpad pinch; 3-finger mode remains the supported
fallback when macOS keeps those gestures.

## Phase 6 - Polish

- [x] Icon cache
- [x] Settings window
- [x] Login item
- [x] Performance pass

Run: `Scripts/build-app.sh`, then open `.build/Launchpad.app`.

## Phase 7 - Bugfix Pass

- [x] Request Accessibility permission for global gesture support
- [x] Horizontal scroll wheel paging
- [x] Toggle launcher and restore previous app

## Phase 8 - LaunchOS Parity

- [x] Global hotkey launch
- [x] F4 key launch
- [x] Quick right-click menu
- [x] Custom app sources
- [x] Customizable grid layout
- [x] Hot corners
- [x] Drag apps to Dock
- [x] Import native Launchpad layout
- [x] Vertical scroll view
- [x] Window browsing mode
- [x] Completely uninstall apps
