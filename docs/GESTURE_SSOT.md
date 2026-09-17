# Gesture Interaction SSOT

Status: normative
Last updated: 2026-09-17

This document is the single source of truth for launcher trackpad behavior.
Dated plans and research notes explain history but do not override this file.
When behavior changes, update this document, implementation, and verification
in the same change.

## Product Contract

- Keep the familiar macOS gesture grammar: pinch inward opens the launcher;
  spread outward closes it while the launcher owns the interaction.
- A physical gesture has one owner from recognition until every contact lifts.
  Direction changes update progress; they do not transfer ownership.
- Gesture progress is continuous and reversible. Threshold-only AppKit
  magnification remains a fallback when private contact input is unavailable.
- Trackpad, keyboard, mouse, menu, hot corner, and accessibility paths must
  converge on the same `LauncherLifecycle` states.
- Do not redefine Mission Control or Show Desktop direction to differentiate
  the product. Differentiate the launcher UI and workflow instead.

## State And Ownership

`LauncherLifecycle` is authoritative for presentation:

```text
hidden -> showing -> shown -> hiding -> hidden
```

| Phase | Window | Launcher gesture owner | Mission Control gesture |
| --- | --- | --- | --- |
| `hidden` | ordered out | no | restored to the saved user value |
| `showing` | visible or becoming visible | yes | suppressed |
| `shown` | visible | yes | suppressed |
| `hiding` | visible until completion | yes | suppressed |

The launcher becomes the gesture owner immediately before its window is
ordered front. It remains the owner through the entire closing animation.
Ownership and Mission Control are restored only after `window.orderOut` in
`completeHide()`.

Mission Control suppression is a project integration rule, not a public AppKit
capability. The implementation snapshots the user's three- and four-finger
vertical-swipe values independently from native Launchpad-pinch reservation,
uses guarded system preference/private integration, and restores the snapshot
after the window is ordered out. Presentation-time changes use direct Darwin
notifications instead of launching and waiting for system helper processes, so
the first tracking sample can present immediately. Normal termination restores
synchronously; abnormal termination is recovered on the next launch.

## Routing Rules

At the first stable contact frame, capture context and keep it for the complete
contact sequence:

| Starting context | Pinch inward | Spread outward |
| --- | --- | --- |
| launcher hidden, windows visible | open launcher | Show Desktop when the system path is supported |
| launcher visible or closing | reverse/open progress | close launcher |
| system desktop visible | restore system desktop | remain system-owned |
| drag or folder mutation active | ignore launcher gesture | ignore launcher gesture |
| system state unknown | wait; do not guess | wait; do not guess |

Re-arm only after a clean full lift. A late terminal event from an older input
generation must never finish or reverse a newer gesture.

## Recognition And Progress

- `LaunchCore` owns pure contact quality, intent, progress, projection, and
  commit/cancel rules.
- `LaunchApp` owns MultitouchSupport/AppKit input, system preferences, window
  presentation, and display-link animation.
- Pinch scale smaller than the baseline means open; larger means close.
- Center translation, contact loss, and unstable finger count must not be
  mistaken for radial intent.
- Once radial ownership is claimed, changing direction rewinds the same
  transition instead of creating the opposite system action.
- Calibration values remain explicit because built-in and external trackpads
  produce different physical ranges. Change them only with a recorded manual
  comparison.

## Presentation And Motion

While contacts are down:

- Keep physical progress authoritative for commit/cancel decisions. Derive a
  monotonic fast-start visual progress from it so the first recognized movement
  is visible without weakening ownership recognition.
- Present the final tracking sample before processing its terminal update.
- Keep alpha and scale driven by the same visual progress.
- Do not add time-delayed easing or a visual dead zone while contacts are down.

After release or cancellation:

- Choose the target from progress plus bounded release velocity.
- Continue from the final input position and velocity with a short,
  interruptible settle animation.
- Commit settles to the projected target; cancel returns to the gesture's
  starting state.
- A new valid input invalidates stale animation completions.
- Respect Reduce Motion by removing scale motion and completing without the
  spring while preserving state and dismissal behavior.

## Accessibility And Alternatives

Every gesture action must remain available through non-gesture input:

- open/toggle: F4, configured shortcut, menu bar, or hot corner;
- close: Escape, toggle action, or empty background click;
- folder dismissal: Escape or dimmed empty-space click;
- page navigation: keyboard and page controls.

## Diagnostics

Run the app with `LAUNCH_TRACKPAD_DIAGNOSTICS=1` when investigating physical
input. Record macOS version, device type, configured finger count, starting
context, recognized owner, progress, release velocity, target, and final state.
Do not tune thresholds from a single unexplained trace.

## Implementation Status

| Contract | Status | Evidence / next action |
| --- | --- | --- |
| Visible lifecycle owns the gesture through `hiding` | implemented | Ownership clears only in `completeHide()` |
| Mission Control suppressed only for the visible lifecycle | implemented; physical verification required | Independent 3/4-finger snapshot; direct suppression before ordering front; restore after ordering out |
| Final input sample and velocity feed settlement | implemented | `finishPinch` synchronizes progress and uses `interactionVelocity` |
| Claimed radial gesture cannot flip owner | covered by core tests | `testClaimedCloseCannotFlipToOpen` |
| Re-arm requires clean contact release | covered by core tests; hardware repetition required | Contact-gate and desktop ownership tests |
| New qualified gesture invalidates a queued prior terminal | implemented; covered by core tests | Delivery generation advances when a new pinch baseline is captured |
| Physical ranges and spring constants | calibration pending | Tune only after the 20-cycle diagnostics run |

## Verification Matrix

Automated checks required before claiming a gesture change:

```sh
swift build
swift run LaunchpadCheck
swift test
```

Build and run the bundle when practical:

```sh
Scripts/build-app.sh
open .build/Launchpad-Dev.app
```

Manual checks on a physical trackpad:

- Open slowly, reverse before release, then cancel back to hidden.
- Open quickly and verify release velocity continues without a hitch.
- Close slowly, reverse before release, then return to shown.
- Repeat open/close at least 20 times without direction inversion.
- Start a new gesture during both opening and closing animation.
- Verify Mission Control cannot activate in `showing`, `shown`, or `hiding`.
- Verify Mission Control returns only after the launcher is fully hidden.
- Repeat Mission Control checks after opening by F4, shortcut, menu, and hot corner.
- Repeat after disabling trackpad gestures and after disconnecting an external trackpad.
- Verify Show Desktop/restore from normal and desktop-visible contexts.
- Verify partial contact loss does not re-arm before all fingers lift.
- Verify icon/folder/page drag blocks launcher gesture ownership.
- Repeat with Reduce Motion enabled.

## Change Record

| Date | Decision |
| --- | --- |
| 2026-09-17 | Keep the macOS gesture grammar; fix ownership and presentation continuity instead of inventing new directions. |
| 2026-09-17 | Treat `showing`, `shown`, and `hiding` as launcher-owned; suppress Mission Control only for that visible lifecycle. |
| 2026-09-17 | Use final interaction progress and velocity as the settle animation's initial state. |
| 2026-09-17 | Invalidate queued delivery when a new pinch baseline is captured so delayed terminals cannot cross gestures. |
| 2026-09-17 | Avoid presentation-time helper processes; notify Mission Control preference changes directly and snapshot 3/4-finger vertical swipes independently from native pinch ownership. |

## Apple References And Boundary

- [Human Interface Guidelines: Pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices)
- [Human Interface Guidelines: Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [AppKit `NSEvent.Phase`](https://developer.apple.com/documentation/appkit/nsevent/phase-swift.struct)

Apple's public documentation defines user-facing conventions and AppKit event
semantics, but does not publish the internal recognizer, thresholds, Dock
protocol, or Launchpad animation constants. Treat private integration as
version-specific implementation, never as an Apple-documented contract.
