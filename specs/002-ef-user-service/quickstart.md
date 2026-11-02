# Quickstart: Compare the Two User Services

The parallel EF service and configuration selection are implemented. Automated validation
and the remaining manual acceptance work are recorded below. Contracts are in
[user-service.md](contracts/user-service.md) and
[implementation-selection.md](contracts/implementation-selection.md).

## Prerequisites

- Windows, Visual Studio MSBuild, .NET Framework 4.8 reference assemblies and compatible runtime.
- Developer PowerShell at the repository root; Windows PowerShell 5.1 STA for window checks.
- NuGet access for the pinned EntityFramework 6.5.2 package.
- A test SQL Server instance. Owned-fixture setup requires create/drop database and schema rights.
- Do not point destructive comparison checks at a normal application database.

## Restore and build

```powershell
msbuild .\HelloWorldWpf48.sln -restore /t:Build /p:Configuration=Debug /p:Platform="Any CPU"
Get-Item .\HelloWorldWpf48\bin\Debug\EntityFramework*.dll
Get-Item .\UserDatabaseService\bin\Debug\EntityFramework*.dll
```

Expect EntityFramework.dll and EntityFramework.SqlServer.dll in both output directories.
No SDK-style migration, EF Core, migrations, or Microsoft.Data.SqlClient provider is required.

## Select the implementation

The checked-in App.config default is:

```xml
<appSettings>
  <add key="UserServiceImplementation" value="Sql" />
</appSettings>
```

Use EntityFramework to select the alternative. Missing/blank remains Sql; an unknown nonblank
choice must display the existing configuration-failure UI. Both use UserDatabase and prepared
dbo.User data. Configuration changes may require restart; opening the window never runs setup.

## Service comparison

Run the full seven-operation comparison through the existing script:

```powershell
.\scripts\Test-UserDatabaseService.ps1 -Server localhost -Configuration Debug -Implementation Both
```

Both runs the original service scenarios per implementation on owned fixtures and reports
separate outcomes plus mixed-provider parity. For diagnosis, use -Implementation Sql or
-Implementation EntityFramework; successful runs need not be repeated without a change/failure.

| Check group | Required evidence |
|---|---|
| Seven operations | Same setup, list/lookups, create, update and delete outcomes. |
| Datasets 0/1/1,000 | Identical fields/order and matched/missing results. |
| Validation and identity | Null/blank/100/101-character boundaries, Unicode, age zero/negative, duplicate names, case-insensitive/accent-sensitive logins, unchanged caller objects. |
| Multiple-login limits | Empty input, duplicates/case variants, 2,000 accepted, 2,001 rejected before query; matching ordinal distinct-count behavior. |
| Parameterization | Test-only EF command interception proves bound Unicode values for 1/2,000 inputs and SQL punctuation; no user input literals in SQL. |
| Writes and races | Unchanged existing update returns true; missing update/delete false; Login spelling unchanged; duplicate race preserves one identity and existing duplicate outcome. |
| Cross-provider visibility | Reuse service instances; create/update/delete in each direction, then read through the other. |
| Explicit setup | Repeated and concurrent mixed-provider setup preserves rows, restores missing constraints, leaves one application table/three columns, creates no history tables. |
| Cancellation/failures | Original argument/cancellation categories; direct SqlException type/number; failures are not empty/not-found. |
| Cleanup | Only owned fixtures removed; normal databases and permissions untouched. |

EfUserService is independent for all seven operations and connection validation. Explicit setup
uses its own EF contexts, database commands and transaction. The unchanged embedded schema
definition is shared; no SqlUserService source, instance or method is required.
DuplicateLoginException lives in its own shared contract file; the SqlUserService class body is unchanged.

Prove the removal scenario with an EF-only build/run:

```powershell
.\scripts\Test-EfIndependence.ps1 -Server localhost -Configuration Debug
```

The temporary executable compiles only EF implementation/support and shared contract sources,
with SqlUserService.cs, the two-provider factory and the normal service DLL absent. It exercises
all seven operations plus concurrent/repeated setup, constraint repair, duplicates and cancellation.

## Window and deployment validation

Run the existing provider-independent fake suite, then the extended real-source mode:

```powershell
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug -SqlServer localhost -Implementation Both
```

The real-source runner copies all built runtime DLLs and configuration into owned temporary
hosts and selects each implementation through configuration. It checks populated/empty/error
states, safe categories, Retry and unchanged data. Fixtures use SqlUserService so EF remains cold.
A separate fresh EF host holds its first intercepted connection opening while the Dispatcher
processes events and closes the window; after release, cancellation must complete without late UI changes.
The harness discovers the context-associated configuration before adding test interceptors;
it does not manually construct provider configuration or resolve DLLs from the package cache.

The fake suite verifies view state/lifetime logic, but does not prove EF SQL translation or
deployment. EF6 command interception and the copied-host run cover those separately.

## Interactive acceptance

```powershell
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug -Interactive
```

Complete the inherited 1,000-row keyboard/readability, Retry and pending move/close checks.
Also inspect the real EF-configured window. For manual fixture preparation use the
[previous feature guide](../001-display-user-list/quickstart.md); all setup is explicit and
separate from normal loading.

The earlier desktop-control runtime failure is not evidence that these checks passed.
If the tool remains unavailable, retain an outstanding manual task with the exact reason.
Do not change checklists merely to mark implementation complete.

## Completion evidence

Validation on 2026-11-02 uses Visual Studio 18 Community MSBuild, Debug/Any CPU,
.NET Framework 4.8 targets and SQL Server `localhost`. The compatibility/runtime
checks exercise correctness and responsiveness; they do not establish a performance winner.

| Check | Actual result |
|---|---|
| Restore/build | PASS: Visual Studio MSBuild `-restore /t:Build /p:Configuration=Debug /p:Platform="Any CPU"`. Both projects remain classic net48/C# 7.3. |
| Deployment | PASS: EntityFramework.dll and EntityFramework.SqlServer.dll exist in both service and app Debug outputs. Fresh copied hosts load them beside the executable and discover the context-associated configuration. |
| Service comparison | PASS: `-Implementation Both`, 145 assertions. Both providers pass the original integration scenarios, full seven-operation contract, 0/1/1,000-row field/order and lookup comparisons, duplicate insert races, input/cancellation rules and direct SQL errors (4060 missing catalog; 208 missing table). |
| Mixed-provider behavior | PASS: reused instances observe create/update/delete from either implementation; concurrent setup repairs a removed constraint and preserves rows. Only the original three-column application table remains. |
| EF parameters | PASS: intercepted queries bind 1 and 2,000 Unicode parameters, including SQL punctuation, without input literals; 2,001 inputs rejected before SQL. |
| Controlled window suite | PASS: 1,182 assertions. Loading for 1/100/1,000 rows: 154/106/91 ms; supplied-result layout: 48/24/24 ms. Pending close handles cancellation, late success and late fault; empty/failure/Retry states pass. |
| Real-source windows | PASS: 21 assertions per provider. Actual EF interception confirms EF selection. Missing/default/blank/case/trim and invalid selection, populated/empty/errors, safe access feedback, Retry and unchanged rows pass. |
| First UI dispatch | PASS: Sql 222 ms, EntityFramework 238 ms, both below the inherited one-second threshold. These are Dispatcher responsiveness measurements, not database-query benchmarks. |
| Cold EF close | PASS: separate fresh process, SQL-prepared fixture, first EF connection opening held by an interceptor; Dispatcher responsiveness and close both under one second, followed by canceled service task and no late UI mutation. |
| Cleanup/preservation | PASS: both service fixtures and all three copied-host fixtures removed in finally blocks; copied hosts removed. No normal database or permissions changed. The `SqlUserService` class body, `IUserService.cs`, `User.cs`, and `Database/Schema.sql` are unchanged. Only the shared exception moved out of the original source file. |
| Repository checks | PASS: `git diff --check`; required .NET build/package/editor exclusions already present in .gitignore. |

Independence correction validation (same date):

- PASS: final Windows solution restore/build.
- PASS: service comparison rerun, 145 assertions, including independent EF setup and mixed-provider
  constraint repair; both owned service databases removed.
- PASS: copied-host window checks rerun, 21 assertions per provider plus separate cold EF close
  check. First UI dispatch: Sql 222 ms, EF 238 ms. All three owned window fixtures removed.
- PASS: `Test-EfIndependence.ps1` compiles C# 7.3 against net48 references with only EF sources,
  IUserService, User and the extracted shared exception. SqlUserService.cs, UserServiceFactory.cs
  and UserDatabaseService.dll are absent. Nineteen assertions exercise all seven operations,
  concurrent first setup, constraint repair, preservation, duplicates, validation and cancellation.
  EF configuration is discovered normally. The owned fixture and temporary executable/DLLs are removed.
- PASS: source comparison confirms the entire SqlUserService class body is byte-for-byte unchanged;
  its only file diff is relocating the unchanged shared exception. EF implementation/support
  sources contain no reference to SqlUserService.
- The controlled 1,182-assertion window suite above passed before this correction; it was not
  rerun because no view logic changed. Real-provider window behavior was rerun.
- An early standalone run reported SQL provider error 0 and cleaned its owned fixture. A subsequent
  run passed. The final standalone script uses a 30-second connection timeout, matching the service
  integration suite, and passed again; no production retry or error suppression was added.

Manual acceptance remains **unexecuted** (T008). Computer Use initialization and window
listing failed before desktop access, and failed again after resetting the JavaScript kernel:

```text
Mcp error: -32602: js: codex/sandbox-state-meta: sandboxCwd is not a local file URI: file:///mnt/c/Users/adamb/Development/Workspace/Boczek/Learning/wpf/HelloWorldWpf48
```

Consequently keyboard traversal, visual readability, manual resizing/scrolling, moving and
closing a pending window, and interactive EF-configured inspection are outstanding.
The earlier feature's manual check remains unexecuted. Automated layout/state checks and
Dispatcher/close assertions do not replace this acceptance work. All FR-001–FR-012 and
SC-001–SC-005 need their full evidence before claiming the feature completely verified.
