# Main-Window UI Contract

**Applies to**: [spec.md](../spec.md), FR-001–FR-011.
**State model**: [data-model.md](../data-model.md).
**Interface type**: Local Windows desktop UI; no network endpoints are added.

## Entry and layout

The existing application StartupUri opens MainWindow through its parameterless constructor.
The first Loaded event starts one load automatically. The greeting text and Say hello action
are replaced with a user directory. The window is resizable; its list occupies a constrained,
scrollable area.

| Control | AutomationId | Accessible purpose |
|---|---|---|
| User grid | UsersGrid | Users; Name, Login, Age column headers |
| State text | LoadStatusText | Current loading, empty, or failure message |
| Retry button | RetryButton | Retry loading users |

Identifiers are stable validation hooks. Messages and accessible names communicate behavior,
not implementation details.

## User grid

- Exactly three explicit columns, in order: Name, Login, Age.
- One row per returned User, retaining source values and source login order.
- Read-only: no editing, insertion row, deletion, or user column sorting.
- Native selection and keyboard navigation remain enabled.
- The list's height is constrained; vertical and horizontal scrolling remain available.
- Long text is fully reachable through keyboard navigation/scrolling or wrapping. Tooltips alone
  are not sufficient.
- Test Tab, arrows, Page Up/Down, Ctrl+Home, and Ctrl+End. All interactive controls have visible
  labels or accessible names; Retry can be activated from the keyboard.
- Row virtualization remains enabled. Bind the completed result once; avoid individually
  creating a visual element for every returned record.

## State presentation

| Outcome | Grid | State text | Retry |
|---|---|---|---|
| Pending | Hidden | Loading users... | Hidden or disabled |
| Populated | Visible, complete result | No loading/error feedback | Hidden |
| Empty | Hidden | No users found | Hidden |
| Failure | Hidden | Safe failure-category message | Visible, enabled |
| Closed | No updates permitted | No updates permitted | No actions permitted |

Only one result state is presented at a time. Starting Retry clears the previous error and
sets the busy guard immediately. A second attempt cannot start while loading is pending.

## Failure messages

Use fixed, non-sensitive text. Do not display raw exception text or any connection details.

| Category | Example message | Evidence boundary |
|---|---|---|
| Configuration | The user database connection is not configured correctly. Check the application settings. | Missing/blank setting or invalid connection construction. |
| Access | Access to user data was denied. Check your database permissions. | Authentication/permission rejection. |
| User storage unavailable | User storage is unavailable or has not been prepared. Check database setup and access. | Missing/inaccessible object; do not assert it definitely does not exist. |
| Database cannot open | The user database cannot be opened. Check availability and access. | Availability or permissions may be responsible. |
| Other load failure | Users could not be loaded. Check availability and access, then retry. | Safe fallback without claiming a root cause. |
| Cancellation while open | Loading was canceled. Try again. | A pending load was canceled without window closure. |

Cancellation caused by closing is silent. Never substitute the empty-state message for an error.

## Recovery and shutdown

Retry invokes the same loading path as startup and replaces the failed state with current data,
an empty result, or another failure. No manual refresh is provided after success.

The user can move or close the window while the source is pending. Closed is terminal:
request cancellation, ignore late success/failure, and emit no later message box. A provider
that ignores cancellation must not cause UI mutation after closure.

## Validation ownership

The planned `scripts/Test-MainWindow.ps1` asserts observable controls and outcomes through real
Loaded/Retry events, not private boolean values. Manual checks cover actual keyboard interaction,
window movement, and long-value readability. See [quickstart.md](../quickstart.md).
