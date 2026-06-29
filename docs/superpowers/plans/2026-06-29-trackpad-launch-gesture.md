# LaunchOS-Parity Activation And Gesture Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Launchpad reliably accessible like LaunchOS: full-screen app browsing, folders, remembered manual layout, trackpad gesture setting, F4/custom shortcut, hot corner, and a macOS-native visual feel.

**Architecture:** Do not treat trackpad pinch as the only product path. macOS owns 4/5-finger system gestures aggressively, so our reliable product surface must be a set of activation paths: F4/custom shortcut, hot corner, and trackpad where available. Keep pure gesture choices in `LaunchpadCore`; keep AppKit, defaults writes, hotkeys, hot corners, and private multitouch code in `LaunchpadApp`.

**Research baseline:**
- LaunchOS advertises `Launch with Trackpad Gesture`, `Launch from Hot Corners`, `Import Native Launchpad Layout`, customizable grid layout, native Launchpad experience, quick right-click menu, and uninstall actions: https://launchosapp.com/
- LaunchNow issue `#36` says trackpad gesture support depends on disabling Apple's `TrackpadFourFingerPinchGesture` / `TrackpadFiveFingerPinchGesture` keys and applying settings with `activateSettings -u`: https://github.com/ggkevinnnn/LaunchNow/issues/36
- LaunchNext issue `#163` points users to third-party gesture mappers when native trackpad hijacking is unreliable: https://github.com/RoversX/LaunchNext/issues/163
- Touch issue `#3` shows replaying Launchpad/Show Desktop four-finger gestures is unreliable reverse-engineering territory: https://github.com/calftrail/Touch/issues/3
- KidoX and Docky-style Launchpad replacements use F4/global hotkey capture instead of depending only on pinch.

---

## Current Capability Map

| LaunchOS-style capability | Current project surface | Plan status |
| --- | --- | --- |
| Full-screen app browsing | `LauncherLifecycle`, `LauncherView`, `LauncherDisplayMode`, `windowBrowsingMode` | Present; verify after activation changes |
| App folders | `LaunchFolder`, `FolderLayout`, `FolderOverlay`, folder drag state in `AppState` | Present but priority reliability bugs remain |
| Remember app positions | `LayoutStore`, `layoutOrder`, folder/order persistence | Present; verify after drag/folder fixes |
| Trackpad gesture setting | `TrackpadGestureResolver`, `TrackpadGestureMonitor`, settings picker | Present but unreliable against macOS native gestures |
| F4/custom shortcut | `GlobalHotKeyAdapter`, input settings | Present; make this first-class fallback |
| Hot corner | `HotCornerMonitor` | Present; make this first-class fallback |
| macOS visual feel | launcher glass/background/icon/folder surfaces | Present; polish after interaction reliability |

---

## Phase 0: Freeze The Product Contract

**Purpose:** Decide what "works like LaunchOS" means before changing more gesture code.

**Files:**
- Modify: `docs/superpowers/plans/2026-06-29-trackpad-launch-gesture.md`
- Inspect only: `Sources/LaunchApp/App/AppState.swift`, `Sources/LaunchApp/Input/SystemInputMonitors.swift`, `Sources/LaunchApp/Input/TrackpadGestureMonitor.swift`, `Sources/LaunchApp/AppDelegate/AppDelegate+Input.swift`

- [ ] **Step 1: Document activation priorities**

Use this product contract:

1. F4/custom shortcut must always be the reliable default.
2. Hot corner must be a reliable no-keyboard fallback.
3. Trackpad gesture is enabled when available, but 4/5-finger native pinch is allowed only if Apple's Launchpad/Show Desktop gesture has been reserved or disabled.
4. 3-finger pinch is the supported fallback when macOS refuses to release 4/5-finger pinch.

- [ ] **Step 2: Keep scope narrow**

Do not redesign folders, grid layout, or visuals in the same change as trackpad activation. Those are separate quality phases below.

---

## Phase 1: Make Activation Surfaces Explicit

**Purpose:** LaunchOS sells multiple ways to open the launcher. Our app should report and handle those paths clearly instead of making trackpad the single point of failure.

**Files:**
- Modify: `Sources/LaunchCore/TrackpadGestureResolver.swift`
- Modify: `Sources/LaunchApp/AppDelegate/AppDelegate+Input.swift`
- Modify: `Sources/LaunchApp/Settings/SettingsView.swift`
- Modify: `Sources/LaunchCheck/main.swift`

- [x] **Step 1: Keep resolver conservative**

Automatic trackpad mode should support `[3, 4]`, reserve native pinch when system 4/5-finger gestures are enabled, and never reserve native pinch for explicit 3-finger mode.

- [x] **Step 2: Show activation choices in settings**

Settings should expose:

- Trackpad: Automatic, 3-finger pinch, 4-finger pinch, 5-finger pinch, Disabled
- F4/custom shortcut state
- Hot corner state

- [x] **Step 3: Log the active activation contract**

On input startup, log the resolved trackpad fingers, whether macOS native pinch conflicts, whether reservation was attempted, and whether F4/hot corner monitors started.

- [x] **Step 4: Verify pure rules**

Run:

```sh
swift run LaunchpadCheck
```

Expected: resolver assertions pass for automatic, 3-finger, 4-finger, 5-finger, disabled, and conflict cases.

---

## Phase 2: Reserve Apple's Native Pinch Where Possible

**Purpose:** Test the LaunchNow-style route before giving up on 4/5-finger pinch.

**Files:**
- Modify: `Sources/LaunchApp/Input/SystemTrackpadSettings.swift`
- Modify: `Sources/LaunchApp/AppDelegate/AppDelegate+Input.swift`

- [ ] **Step 1: Write every known Launchpad/Show Desktop pinch key**

For both domains:

```text
com.apple.AppleMultitouchTrackpad
com.apple.driver.AppleBluetoothMultitouch.trackpad
```

Write `0` for:

```text
TrackpadFourFingerPinchGesture
TrackpadFiveFingerPinchGesture
com.apple.trackpad.fourFingerPinchSwipeGesture
com.apple.trackpad.fiveFingerPinchSwipeGesture
```

- [ ] **Step 2: Apply settings immediately**

After writing defaults, run Apple's settings activation helper from app code when it exists:

```text
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
```

- [ ] **Step 3: Verify defaults**

Run:

```sh
swift build
defaults read com.apple.AppleMultitouchTrackpad TrackpadFourFingerPinchGesture
defaults read com.apple.AppleMultitouchTrackpad TrackpadFiveFingerPinchGesture
defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerPinchGesture
defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFiveFingerPinchGesture
```

Expected: build succeeds and each defaults read returns `0` or the key is absent after the modern key path has been written.

---

## Phase 3: Trackpad Monitor Reliability

**Purpose:** Make our private multitouch monitor accept the intended gesture without fighting icon drag or page navigation.

**Files:**
- Modify: `Sources/LaunchApp/Input/TrackpadGestureMonitor.swift`
- Modify: `Sources/LaunchCore/TrackpadIntent.swift`
- Modify: `Sources/LaunchCheck/main.swift`

- [ ] **Step 1: Support multiple finger counts**

The monitor should accept the resolved finger list, prefer higher counts first, and fall back to 3-finger when automatic mode includes both `[3, 4]`.

- [ ] **Step 2: Do not trigger while drag state is active**

Trackpad open/close/page intent must not fire while root icon drag, folder drag, folder creation, folder pull-out, or page drag is active.

- [ ] **Step 3: Verify intent rules**

Run:

```sh
swift run LaunchpadCheck
```

Expected: pinch, scroll, page swipe, and contact-quality assertions pass.

---

## Phase 4: Ship F4 And Hot Corner As First-Class Fallbacks

**Purpose:** If macOS still opens its own launcher, do not keep chasing private gesture hijacking. Make the dependable paths feel intentional.

**Files:**
- Modify: `Sources/LaunchApp/Input/SystemInputMonitors.swift`
- Modify: `Sources/LaunchApp/AppDelegate/AppDelegate+Input.swift`
- Modify: `Sources/LaunchApp/Settings/SettingsView.swift`

- [ ] **Step 1: Confirm F4 opens and closes our launcher**

Use the existing global hotkey adapter. If F4 is not captured on this machine, add a small Carbon `RegisterEventHotKey` fallback in `LaunchApp`.

- [ ] **Step 2: Confirm hot corner opens our launcher**

Hot corner should be independently testable and should not depend on trackpad permissions.

- [ ] **Step 3: Make settings copy honest**

Use wording that makes trackpad optional:

```text
Trackpad gesture: Automatic / 3 fingers / 4 fingers / 5 fingers / Disabled
F4 shortcut: Enabled
Hot corner: Enabled
```

---

## Phase 5: Full-Screen Browsing And Page Gesture Quality

**Purpose:** Match the LaunchOS "full screen app browsing" promise inside the launcher after activation works.

**Files:**
- Modify: `Sources/LaunchApp/Launcher/LauncherView.swift`
- Modify: `Sources/LaunchApp/Launcher/LauncherContent.swift`
- Modify: `Sources/LaunchCore/TrackpadIntent.swift`
- Modify: `Sources/LaunchCheck/main.swift`

- [ ] **Step 1: Verify full-screen/windowed modes**

Manual checks:

- Full-screen grid opens on the active screen.
- Window browsing mode stays normal-level and movable.
- Page control matches the visible page.

- [ ] **Step 2: Keep page gestures out of icon drag**

Horizontal swipe/scroll should page only when no app/folder drag is active.

- [ ] **Step 3: Verify natural paging direction**

Manual check with trackpad: left/right movement should feel like Apple's Launchpad paging.

---

## Phase 6: Folder And Position Reliability

**Purpose:** Stabilize the LaunchOS-equivalent folder and manual positioning features after activation is no longer blocking.

**Files:**
- Modify: `Sources/LaunchCore/FolderLayout.swift`
- Modify: `Sources/LaunchApp/App/AppState.swift`
- Modify: `Sources/LaunchApp/Launcher/FolderOverlay.swift`
- Modify: `Sources/LaunchApp/Launcher/LauncherItemViews.swift`
- Modify: `Sources/LaunchCheck/main.swift`

- [ ] **Step 1: Separate drag states**

Keep app drag, folder drag, folder creation, folder add/remove, page drag, and click launch as separate transient states.

- [ ] **Step 2: Clear visual ghost state**

Clear faded/hidden icon state on cancel, failed drop, successful drop, launcher hide, and any new non-drag mouse down.

- [ ] **Step 3: Verify folder operations**

Manual checks:

- Drag app onto app creates a folder.
- Drag app onto folder adds it to the folder.
- Drag app out of folder restores it to the root grid.
- Failed or canceled drag restores icon opacity.
- Manual order persists after relaunch.

---

## Phase 7: macOS Visual Polish Pass

**Purpose:** Polish only after input and state reliability are stable.

**Files:**
- Modify only focused visual files under `Sources/LaunchApp/Launcher`
- Modify constants in `Sources/LaunchApp/Shared/LaunchConstants.swift` when needed

- [ ] **Step 1: Keep native-feeling surfaces**

Polish glass, dim layer, folder chrome, icon spacing, and animation timings without changing interaction state.

- [ ] **Step 2: Verify escape paths**

Manual checks:

- Empty/dimmed space closes an open folder.
- ESC closes folder, then search, then launcher.
- Underlying folder icons do not steal dimmed-space clicks.

---

## Final Verification

Run before claiming implementation complete:

```sh
swift build
swift run LaunchpadCheck
Scripts/build-app.sh
open .build/Launchpad.app
```

Manual checks:

- F4 opens/closes our launcher.
- Hot corner opens our launcher.
- 3-finger pinch opens our launcher when enabled.
- 4/5-finger pinch does not open Apple Launchpad after reservation; if it still does, use 3-finger + F4/hot corner as the supported path.
- Full-screen browsing works.
- Page swipe/trackpad navigation does not fight icon drag.
- Folder creation/add/remove works.
- Failed or canceled drag restores icon opacity.
