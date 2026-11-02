# Data Model: Main-Window User List

## Existing persisted User

Reuse `UserDatabaseService.User`; no new persisted entities or schema changes.

| Field | Existing type | Rules | Display behavior |
|---|---|---|---|
| Name | string / nvarchar(100) | Required, nonblank; duplicates allowed | Display returned value under Name. |
| Login | string / nvarchar(100) | Required, nonblank, immutable identity; unique, case-insensitive and accent-sensitive | Display returned value under Login. |
| Age | int | Required, zero or greater | Display integer under Age, including zero. |

Existing service writes trim text; this feature performs no writes and does not revalidate or
normalize returned values. Two users with the same Name remain distinct. Login identity and
initial ordering follow the existing SQL collation, not the client's current culture.

## User list result

- Type: existing `IReadOnlyList<User>`, non-null, supplied by GetAllAsync.
- Cardinality: zero or more records; acceptance validation uses 1, 100, and 1,000 records.
- One returned User maps to exactly one displayed row; no filtering, projection that loses fields,
  or deduplication.
- Bind the completed collection once. Existing mutable User properties remain unchanged; the
  grid disallows editing. No ObservableCollection or new DTO is needed for a static result.
- No parent/child relationships or new identifiers are introduced.

## Window-owned transient state

| State | Rows | Status | Retry |
|---|---|---|---|
| Initial | None | Initial loading feedback | Unavailable |
| Loading | None | Loading users | Unavailable |
| Populated | Complete returned collection | No loading/error message | Hidden |
| Empty | None | No users found | Hidden |
| Failed | None | Safe category message | Visible and enabled |
| Closed | No further UI access | No further UI access | No further UI access |

The implementation may use a private enum and a single presentation helper in MainWindow.
The state model is not a persisted entity or new production layer.

### State transitions

- First Loaded: Initial -> Loading. Subsequent Loaded notifications do not start another load.
- Source success with records: Loading -> Populated.
- Source success with zero records: Loading -> Empty.
- Configuration, access, storage, or other recoverable failure: Loading -> Failed.
- Retry: Failed -> Loading; the same success/failure rules apply.
- Closing: any state -> Closed; cancel pending work and ignore all later completions.
- Cancellation while still open: Loading -> Failed with a recoverable message.
- Repeated retry while Loading: no transition and no additional source invocation.
- Populated/Empty have no refresh transition in this feature.

### Lifecycle invariants

- Store the lazy source factory; invoke it only within an accepted loading attempt.
- Set the in-flight guard before any await or factory call; at most one attempt is active.
- One lifetime CancellationTokenSource belongs to the window. It is canceled only when closing;
  keep it available for retries while the window remains open.
- Check closure after every await, including a Dispatcher yield, and before every error/finally
  UI update. A provider that ignores cancellation cannot reopen or change the closed view.
- Dispose the source after closure once no load is active. No operation waits synchronously
  for pending I/O on the UI thread.
- Reset the in-flight guard on completion; only an open failed window enables Retry.
- Setup and CRUD invocation counts remain zero throughout the window lifecycle.

## Configuration dependency

The existing `UserDatabase` connection-string entry identifies SQL Server and its catalog.
It is not displayed or persisted by the view. A missing/blank entry or invalid connection value
is a Failed state, not an empty user collection. The explicit setup workflow remains external
to window loading.
