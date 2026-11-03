# Contract: Three Choices and Existing Window Behavior

## Factory and Configuration

Extend the existing UserServiceFactory.Create(implementation, connectionString):

| Input after trimming, ignoring case | Result |
|---|---|
| Missing/null/empty/whitespace | SqlUserService. |
| Sql | SqlUserService. |
| EntityFramework | EfUserService. |
| EntityFrameworkStoredProcedures | EfStoredProcedureUserService. |
| Other nonblank text | Existing ArgumentException/configuration failure; no fallback. |

Keep UserDatabase as the only connection-string setting. The factory does no file I/O, setup,
EF initialization or connection opening. Direct construction remains supported for all three.

Do not change the source App.config to make the new choice the default. The user's current
EntityFramework selection is preserved; the existing missing/blank fallback remains Sql.
Document the third value and use disposable configuration copies for tests.
No picker, hot reload, alternate catalog or automatic migration is introduced.

## Window

MainWindow's existing lazy factory already reads the choice and invokes the shared factory.
Keep the same grid, status, Retry, asynchronous loading and lifetime guards.
Add SQL2812 alongside SQL208 in the existing storage/setup feedback branch.
SQL229 remains access denied; unknown selection remains configuration failure.
No raw provider text, procedure names or connection details are shown to users.

Missing procedures must leave the window open with safe setup feedback and enabled Retry,
without modifying definitions. Explicit external fixture repair followed by one Retry loads
current data. No overlapping request, new automatic retry or setup-on-error behavior.
All three choices retain responsive first-load/pending-close behavior.

## Validation Commands to Extend

| Entry point | Selection values | Compatibility |
|---|---|---|
| Test-UserDatabaseService.ps1 -Implementation | Sql, EntityFramework, EntityFrameworkStoredProcedures, Both, All | Default Sql; Both retains original two; All runs all three and shared comparisons once. |
| Test-MainWindow.ps1 -SqlServer ... -Implementation | Same five values | Default Sql; Both retains original pair; All runs real copied hosts for all three. |
| Test-MainWindow.ps1 without -SqlServer | Existing fake suite | Provider-independent; not mislabeled real procedure proof. |
| Test-EfIndependence.ps1 -Implementation | EntityFramework, EntityFrameworkStoredProcedures, Both | Default EntityFramework preserves the prior check; Both builds separate isolated executables for the two EF variants. |

Keep -Configuration and existing window -Phase/-Interactive options. Do not add public phase
switches; use internal host roles for fixture preparation, configuration-order and cold checks.
For third-service real interactive inspection, honor the existing -Interactive flag in the
copied real-source host while its owned fixture remains available; clean up after it closes.

Third-service window preparation must occur in a separate host process before fresh Full and
ColdClose hosts. Do not call third-service setup in those UI processes before their first query.
Copy all runtime DLLs/configuration. The fixture owner coordinates generated catalog names and
cleanup in finally; ordinary application configuration and data are never touched.

For interceptor registration, tooling may discover configuration with the selected context's
type/assembly before adding interceptors; it must not construct or substitute old configuration
to make third-only/provider-order checks pass. Fresh order tests use normal discovery.

Commands and selectors are implemented. Executed outcomes and unexecuted manual acceptance
are recorded in ../quickstart.md.
