# Quickstart: Compare the Two User Services

This is an implementation-phase validation guide. Planning has not installed packages, built
the new implementation or run these checks. Contracts are in
[user-service.md](contracts/user-service.md) and
[implementation-selection.md](contracts/implementation-selection.md).

## Prerequisites

- Windows, Visual Studio MSBuild, .NET Framework 4.8 reference assemblies and compatible runtime.
- Developer PowerShell at the repository root; Windows PowerShell 5.1 STA for window checks.
- NuGet access for the pinned EntityFramework 6.5.2 package.
- A test SQL Server instance. Owned-fixture setup requires create/drop database and schema rights.
- Do not point destructive comparison checks at a normal application database.

## Restore and build

After implementing the planned package references and classes:

```powershell
msbuild .\HelloWorldWpf48.sln -restore /t:Build /p:Configuration=Debug /p:Platform="Any CPU"
Get-Item .\HelloWorldWpf48\bin\Debug\EntityFramework*.dll
Get-Item .\UserDatabaseService\bin\Debug\EntityFramework*.dll
```

Expect EntityFramework.dll and EntityFramework.SqlServer.dll in both output directories.
No SDK-style migration, EF Core, migrations, or Microsoft.Data.SqlClient provider is required.

## Select the implementation

The planned App.config default is:

```xml
<appSettings>
  <add key="UserServiceImplementation" value="Sql" />
</appSettings>
```

Use EntityFramework to select the alternative. Missing/blank remains Sql; an unknown nonblank
choice must display the existing configuration-failure UI. Both use UserDatabase and prepared
dbo.User data. Configuration changes may require restart; opening the window never runs setup.

## Service comparison

These parameters will be implemented in the existing script:

```powershell
.\scripts\Test-UserDatabaseService.ps1 -Server localhost -Configuration Debug -Implementation Both
```

Both must run the existing service scenarios per implementation on owned fixtures and report
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

Do not satisfy the new implementation by forwarding user queries/CRUD to the original. The
explicit setup operation is deliberately shared; the existing schema script remains authoritative.

## Window and deployment validation

Run the existing provider-independent fake suite, then the extended real-source mode:

```powershell
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug -SqlServer localhost -Implementation Both
```

The real-source runner must copy all built runtime DLLs and configuration into owned temporary
hosts and select each implementation through configuration. Assert populated/empty/error states,
safe categories, Retry, cancellation/closure and unchanged fixture data. For EF's first query,
prepare data using SqlUserService so setup/baseline reads do not warm the EF model beforehand.
Confirm a cold load lets the window process input/close while model preparation is pending.

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

Record restore/build result, per-provider comparison results, intercepted parameter checks,
copied-host dependency/cold-load outcomes, timings under the inherited window criteria, data/schema
preservation, and cleanup. Distinguish passed, failed and unexecuted checks.

All FR-001–FR-012 and SC-001–SC-005 require matching evidence before claiming feature completion.
The original implementation's regression suite must still pass. No package/runtime comparison,
new feature validation or outstanding manual check has been executed by this planning command.
