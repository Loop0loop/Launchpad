# Agent Instructions

## Product Goal

Build a native-feeling macOS Launchpad replacement. The bar is Apple's
Launchpad-level interaction quality: smooth gestures, reliable drag and drop,
clean folder behavior, no stale visual state, and predictable keyboard/mouse
escape paths.

Current priority bugs:

- Gestures do not feel native-grade.
- Folder drag/folder construction is unreliable.
- Dragged or clicked app icons can remain faded, leaving a visual ghost state.
- Folder overlay should close by clicking empty/dimmed space, not only by ESC.

## Architecture Rules

- Keep `LaunchCore` pure. It should import `Foundation` only.
- Put pure layout/search/folder/gesture rules in `LaunchCore` and cover
  meaningful branches with `LaunchpadCheck` assertions or focused
  `LaunchpadCoreTests`.
- Keep AppKit, SwiftUI, persistence, permissions, and system APIs in
  `LaunchApp`.
- `AppState` is the single observable UI model. Prefer domain extensions over
  growing one large file.
- `AppDelegate` owns process-level AppKit wiring. SwiftUI views should call
  `AppState`; AppKit side effects should go through `LauncherActions`.

## Interaction Rules

- Treat app drag, folder drag, folder creation, folder add/remove, page drag,
  and click launch as separate interaction states. Do not let one gesture path
  leave stale state for another.
- Clear transient drag state on cancel, failed drop, successful drop, launcher
  hide, and any new non-drag mouse down.
- Do not re-render or page-offset the grid during icon drag if it can cancel
  SwiftUI drop delivery.
- Folder overlay dismissal must work from the dimmed empty space and must not
  be stolen by underlying folder icons or title field commits.
- Prefer private in-process drag types for internal app movement so external
  apps cannot hijack drag payloads.

## Verification

Run these before claiming a fix:

```sh
swift build
swift run LaunchpadCheck
swift test
```

Use `LaunchpadCheck` for executable rule checks and `swift test` for the
`LaunchpadCoreTests` XCTest target.

For UI/gesture changes, also run the app bundle when practical:

```sh
Scripts/build-app.sh
open .build/Launchpad.app
```

Manual checks for this project:

- Click empty/dimmed space closes an open folder.
- ESC still closes folder/search/launcher in order.
- Drag app onto app creates a folder.
- Drag app onto folder adds it to the folder.
- Failed or canceled drag restores icon opacity.
- Page swipe/trackpad navigation does not fight icon drag.

## Existing Context

There is also a `CLAUDE.md` with code-review-graph guidance. If the graph MCP
tools are available, use them before broad file scans. If they are not
available, fall back to `rg` and focused file reads.

<!-- code-review-graph MCP tools -->
## MCP Tools: code-review-graph

**IMPORTANT: This project has a knowledge graph. ALWAYS use the
code-review-graph MCP tools BEFORE using Grep/Glob/Read to explore
the codebase.** The graph is faster, cheaper (fewer tokens), and gives
you structural context (callers, dependents, test coverage) that file
scanning cannot.

### When to use graph tools FIRST

- **Exploring code**: `semantic_search_nodes` or `query_graph` instead of Grep
- **Understanding impact**: `get_impact_radius` instead of manually tracing imports
- **Code review**: `detect_changes` + `get_review_context` instead of reading entire files
- **Finding relationships**: `query_graph` with callers_of/callees_of/imports_of/tests_for
- **Architecture questions**: `get_architecture_overview` + `list_communities`

Fall back to Grep/Glob/Read **only** when the graph doesn't cover what you need.

### Key Tools

| Tool | Use when |
| ------ | ---------- |
| `detect_changes` | Reviewing code changes — gives risk-scored analysis |
| `get_review_context` | Need source snippets for review — token-efficient |
| `get_impact_radius` | Understanding blast radius of a change |
| `get_affected_flows` | Finding which execution paths are impacted |
| `query_graph` | Tracing callers, callees, imports, tests, dependencies |
| `semantic_search_nodes` | Finding functions/classes by name or keyword |
| `get_architecture_overview` | Understanding high-level codebase structure |
| `refactor_tool` | Planning renames, finding dead code |

### Workflow

1. The graph auto-updates on file changes (via hooks).
2. Use `detect_changes` for code review.
3. Use `get_affected_flows` to understand impact.
4. Use `query_graph` pattern="tests_for" to check coverage.
