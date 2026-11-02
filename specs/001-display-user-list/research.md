# Research: Display Users in the Main Window

**Date**: 2026-11-02
**Inputs**: [spec.md](spec.md), project constitution v1.0.0, existing application/service source.
**Status**: Complete; no unresolved technical questions.

## 1. Keep the existing application structure

**Decision**: Extend MainWindow XAML/code-behind and reuse IUserService. Add no production
projects, packages, view-model framework, or repository layer.

**Rationale**: The feature has one read-only view and a completed result list. The existing
service already separates persistence from presentation. The desktop project already references
UserDatabaseService and System.Configuration.

**Alternatives considered**: An MVVM framework or new presentation project adds dependencies and
indirection without a second view, editing flow, or shared presentation state.

**Evidence**: `HelloWorldWpf48/MainWindow.xaml.cs`,
`HelloWorldWpf48/HelloWorldWpf48.csproj`, `UserDatabaseService/IUserService.cs`.

## 2. Reuse the existing retrieve-all contract

**Decision**: Call GetAllAsync with a window-lifetime cancellation token; bind the returned
IReadOnlyList<User> as one result, preserving its ordering and values.

**Rationale**: SqlUserService already performs a SELECT of Name/Login/Age ordered by Login,
uses asynchronous connection/reader operations, and disposes resources per operation.
Retrieve-all has no 2,000-record restriction; that limit belongs to GetByLoginsAsync.
No service or schema change is needed.

**Alternatives considered**: Direct SQL in the window violates the service boundary.
Client-side sorting risks changing collation order; name-based deduplication loses valid users.
Startup schema initialization violates the read-only view contract.

**Evidence**: `UserDatabaseService/SqlUserService.cs` and
[SqlConnection.OpenAsync](https://learn.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlconnection.openasync?view=netframework-4.8.1).

## 3. Start loading after window initialization

**Decision**: Keep constructors free of configuration access and database work. Store a lazy
Func<IUserService>; a parameterless constructor supplies the production factory and an injection
constructor supports controlled validation. Invoke the factory inside the guarded load try block.
Start automatically from Loaded once, and reuse the same Task-returning method for Retry.

**Rationale**: Missing settings and invalid connection/catalog values can fail before an async
database task exists. Resolving them during loading permits an error UI to remain visible.
Set the loading state before the first await; allow the Dispatcher to render it before proceeding.
Async-void is confined to event adapters that await a method containing operational error handling.

**Alternatives considered**: Constructing SqlUserService in the window constructor can fail before
the error view exists. Eager initialization in App would require additional startup wiring.
Changing StartupUri is unnecessary.

**Sources**:
[WPF lifetime events](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/events/object-lifetime-events),
[async return types](https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/async-return-types),
[ConfigurationManager.ConnectionStrings](https://learn.microsoft.com/en-us/dotnet/api/system.configuration.configurationmanager.connectionstrings?view=netframework-4.8.1).

## 4. Await I/O without blocking the UI thread

**Decision**: Await GetAllAsync directly from the window's UI context. Set the busy guard before
awaiting or invoking the factory. All UI changes occur on the UI thread; no .Wait(), .Result,
Thread.Sleep, or unnecessary Task.Run in the window.

**Rationale**: The service already provides asynchronous I/O and uses ConfigureAwait(false)
internally. The caller can still resume on its captured UI context. One guarded path prevents
duplicate requests and inconsistent status visibility.

**Alternatives considered**: Explicit background threads or Task.Run around async SQL introduce
extra coordination without converting any blocking operation.

**Source**: [WPF threading model](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/threading-model).

## 5. Make window closure terminal

**Decision**: Closed marks the window closed and requests cancellation. Check the closed flag
after awaits and before any success, failure, or finally-path UI change. Suppress close-related
cancellation; if cancellation occurs while still open, show a recoverable failure. Dispose the
lifetime token source once the window is closed and the outstanding attempt has settled.

**Rationale**: Cancellation is cooperative; a provider can complete or fault after cancellation.
The closed flag prevents late UI updates independently of provider behavior. Closure never waits
for I/O, and disposal must not race the active operation.

**Alternatives considered**: Cancellation alone cannot prevent late completions. Blocking closure
until the task completes would violate responsiveness.

**Sources**:
[Window.Closed](https://learn.microsoft.com/en-us/dotnet/api/system.windows.window.closed),
[managed cancellation](https://learn.microsoft.com/en-us/dotnet/standard/threading/cancellation-in-managed-threads).

## 6. Use a constrained native DataGrid

**Decision**: A resizable window contains a Grid with a star-sized DataGrid row, explicit
Name/Login/Age columns, read-only cells, no new/delete rows, no user sorting, native scrolling,
and enabled row virtualization. Bind the full result once. Complete long values must be reachable
through keyboard horizontal navigation/scrolling or wrapping, not mouse-only tooltips.

**Rationale**: A vertical StackPanel provides unconstrained height and can let the grid grow
past the viewport. A bounded grid preserves scrolling and virtualization. Disabling editing
must not disable the whole control, which would prevent navigation.

**Alternatives considered**: A StackPanel of individual rows increases rendering work and
requires custom keyboard behavior. A custom list control offers no benefit for three fields.

**Sources**:
[DataGrid sizing](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/controls/sizing-options-in-the-datagrid-control),
[DataGrid](https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.datagrid?view=netframework-4.8),
[row virtualization](https://learn.microsoft.com/en-us/dotnet/api/system.windows.controls.datagrid.enablerowvirtualization),
[keyboard behavior](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/controls/default-keyboard-and-mouse-behavior-in-the-datagrid-control).

## 7. Categorize failures without exposing provider details

**Decision**: Missing/blank UserDatabase settings, ConfigurationErrorsException, and invalid
connection/service-construction values produce a configuration message. Add a System.Data
framework reference to classify SqlException. Access errors such as 18456/229/230 produce access
feedback; 208 indicates unavailable or unprepared user storage; 4060 indicates a database that
cannot be opened. Other SQL or recoverable errors receive a safe load-failure message.

**Rationale**: Provider error numbers support useful categories, not certainty about root cause.
Error 208 may reflect object visibility; 4060 may reflect availability or permissions. Messages
must not claim that a database is missing based solely on either code. Never show exception
messages, credentials, or connection strings.

**Alternatives considered**: Displaying exception.Message leaks technical details. Modifying the
service to introduce a new exception hierarchy is unnecessary for this presentation-only feature.

**Sources**:
[SQL error catalog](https://learn.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors-0-to-999),
[SQL login failures](https://learn.microsoft.com/en-us/sql/relational-databases/errors-events/mssqlserver-18456-database-engine-error).

## 8. Verify window behavior with a small STA harness

**Decision**: Add one dependency-free Windows PowerShell script, Test-MainWindow.ps1, using a C#
fake and the real window through the factory seam. Bounded Dispatcher pumping observes the actual
controls and task completions. Fake setup/write methods count and reject unexpected calls.
Include delayed, failed, retried, canceled, and post-close outcomes; record 1/100/1,000-row results.
Keep keyboard readability and move/close interaction as explicit manual checks.

**Rationale**: The important risks are asynchronous ordering, error recovery, and preventing writes.
They need controlled outcomes, not a large new test framework. SqlException has no public
constructor; do not use reflection to manufacture it. Verify provider-specific categories with
an owned real SQL fixture. The existing service integration script removes its database and
does not validate the window.

**Alternatives considered**: Real SQL alone cannot reliably reproduce pending/late completion
races. A fake-only check cannot prove the production configuration path or actual SQL categories.

**Sources**:
[PowerShell STA](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1),
[DispatcherFrame](https://learn.microsoft.com/en-us/dotnet/api/system.windows.threading.dispatcherframe),
[TaskCompletionSource](https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.taskcompletionsource-1?view=netframework-4.8.1).

The selected architecture and testing approach are project-specific inferences from these sources
and repository evidence. Research did not execute application code or modify a database.
