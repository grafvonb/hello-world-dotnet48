# User Source Integration Contract

**Owner**: Existing UserDatabaseService library.
**Consumer**: MainWindow in HelloWorldWpf48.
**Change policy**: Reuse existing public types and service behavior; no interface or schema changes.

## Permitted operation

`Task<IReadOnlyList<User>> IUserService.GetAllAsync(CancellationToken cancellationToken)`

- Invoked once per accepted attempt, after resolving the source inside the loading error boundary.
- Returns all existing users with Name, Login, and Age, initially ordered by Login.
- A non-null collection containing zero records is a successful empty result.
- Pass the window-lifetime token. Provider exceptions/cancellation propagate to the awaited caller.
- No setup, insert, update, or delete is performed by this operation.
- The 2,000-login restriction on GetByLoginsAsync does not apply to this operation.

Do not invoke CreateOrUpdateDatabaseAsync, CreateAsync, UpdateAsync, DeleteAsync, GetByLoginAsync,
or GetByLoginsAsync from the user-list flow.

## Configuration and factory seam

Production uses `ConfigurationManager.ConnectionStrings["UserDatabase"]` and SqlUserService.
Check for a missing/blank entry before constructing the service. Preserve the public
parameterless MainWindow constructor for StartupUri.

A public `MainWindow(Func<IUserService> serviceFactory)` overload stores a lazy factory.
The normal constructor supplies a production factory; test code supplies a fake or throwing
factory. Invoke it within each accepted load, not during window construction. A factory must
return a non-null service; failure to do so produces safe failure feedback.

The default connection remains in App.config. Changes to settings that require application
restart do not need hot-reload support. Entirely malformed executable configuration XML may
prevent runtime startup before MainWindow; configuration acceptance checks use structurally
valid XML with missing or invalid connection settings.

## Error mapping

ConfigurationErrorsException, absent settings, and invalid connection/service construction
produce a configuration category. Catch SqlException via a System.Data framework reference
in the desktop project without placing SQL/connection operations there.

| SQL error | Presentation category |
|---|---|
| 18456, 229, 230 | Access denied |
| 208 | User storage unavailable or unprepared |
| 4060 | Database cannot open; availability/access uncertain |
| Other SQL errors, including timeout | Safe data-load failure |

Provider messages and connection values are never copied into presentation text. These codes
describe categories and do not establish a unique root cause. Unexpected recoverable failures
produce a generic loading failure and allow Retry. Close-related OperationCanceledException is
suppressed; cancellation while still open ends loading in a recoverable failure.

## Thread and lifetime guarantees

The caller awaits directly from the UI context; the service may continue using ConfigureAwait(false)
internally. The consumer does not use synchronous waits or Task.Run for async SQL I/O. One
attempt is active at a time. Closing requests cancellation and independently guards against
late completion; cancellation alone is not proof that the task has finished.

## Validation doubles

A fake implements the unchanged IUserService. Only GetAllAsync is expected; other members
record and reject calls. A TaskCompletionSource-controlled result tests pending, successful,
empty, failed, retried, and post-close outcomes. Test factory exceptions separately.

Do not reflect into SqlException internals to fabricate provider failures. Validate actual SQL
categories against a dedicated fixture. No production database is modified by a validation
double. See [quickstart.md](../quickstart.md).
