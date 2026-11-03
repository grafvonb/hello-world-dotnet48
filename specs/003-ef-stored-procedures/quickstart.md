# Quickstart: Compare All Three User Services

This is the implementation-phase validation guide. Planning has not implemented the third
service, installed procedures, built the change or run these scenarios. New selectors below
become available during implementation. See the [plan](plan.md), [user-service contract](contracts/user-service.md),
[procedure contract](contracts/stored-procedures.md) and [selection contract](contracts/implementation-selection.md).

## Prerequisites

- Windows, Visual Studio MSBuild, net48 reference assemblies/runtime and Windows PowerShell 5.1.
- The existing pinned EF6 6.5.2 package/cache or restore access; no package upgrade.
- A test SQL Server instance and an identity allowed to create/drop owned databases and apply
  schema/type/procedure definitions. The planned batches retain the existing effective SQL2012+
  syntax baseline rather than requiring CREATE OR ALTER.
- Runtime accounts need procedure EXECUTE and EXECUTE/REFERENCES on dbo.UserLoginList.
  Setup privilege requirements are separate. Normal account/server-login permissions are untouched.
- Run from the repository root. Use STA for window checks.

## Restore and Deployment

```powershell
msbuild .\HelloWorldWpf48.sln -restore /t:Build /p:Configuration=Debug /p:Platform="Any CPU"
Get-Item .\HelloWorldWpf48\bin\Debug\EntityFramework*.dll
Get-Item .\UserDatabaseService\bin\Debug\EntityFramework*.dll
```

Both outputs must contain EntityFramework.dll and EntityFramework.SqlServer.dll.
Copied hosts must resolve those local DLLs without package-cache paths or manual provider setup.

## Explicit Setup and Selection

Only EfStoredProcedureUserService.CreateOrUpdateDatabaseAsync installs the third service's
required type/procedures. It independently prepares the same user schema and preserves records.
An existing source prepared by either earlier service needs this explicit third-service setup
before the new choice can read/write; ordinary launch never installs it.

For isolated, runnable setup/repair and cleanup, use the independent check:

```powershell
powershell.exe -NoProfile -File .\scripts\Test-EfIndependence.ps1 -Server localhost -Configuration Debug -Implementation EntityFrameworkStoredProcedures
```

That executable must build without either earlier service, their context/configuration,
the factory or the normal service DLL, then exercise all seven operations including explicit
concurrent setup and constraint/procedure repair. It removes only its generated fixture.

For application deployment, an explicit setup caller constructs the third service with the
chosen UserDatabase connection and awaits CreateOrUpdateDatabaseAsync outside the window load path.
Procedure/type definitions and permission prerequisites are detailed in the procedure contract;
do not add setup to constructors, service selection, normal data calls or Retry.

The new documented configuration choice will be:

```xml
<add key="UserServiceImplementation" value="EntityFrameworkStoredProcedures" />
```

The current local EntityFramework setting is preserved. Existing Sql/EntityFramework values
and missing/blank Sql fallback remain valid. Rebuild/restart when intentionally changing source
configuration. Validation uses copied configurations rather than editing the normal one.

## Full Service Comparison

```powershell
powershell.exe -NoProfile -File .\scripts\Test-UserDatabaseService.ps1 -Server localhost -Configuration Debug -Implementation All
# Diagnose only the third choice:
powershell.exe -NoProfile -File .\scripts\Test-UserDatabaseService.ps1 -Server localhost -Implementation EntityFrameworkStoredProcedures
# Retain both EF independence checks, each in its own isolated executable:
powershell.exe -NoProfile -File .\scripts\Test-EfIndependence.ps1 -Server localhost -Implementation Both
```

Service/window Both retains Sql + EntityFramework. All means all three. In the independence
script, Both means its two EF variants; its default remains the earlier EntityFramework check.
Do not reinterpret existing commands or add test-phase switches.

| Group | Required evidence |
|---|---|
| Original contract | Existing complete assertions still run for both earlier services; third passes all seven methods and existing validation/cancellation categories. |
| 0/1/1,000 users | Same fields, login order and single/multiple matched/missing results for all three. |
| Boundary rules | Unicode, case/accent, trim, 100/101 characters, zero/negative age, caller objects unchanged, duplicate names/races and unchanged update=true. |
| Procedure execution | Observe all six fixed EF invocations, native async execution and actual bound parameters. No direct-table or fallback commands; inspect installed definitions. |
| Login-list transport | One correctly typed Unicode TVP with 1/2,000 inputs, actual matched punctuation/Unicode rows, case variants and trimmed duplicates; reject 2,001 before connection/query. |
| Result contract | Missing update/delete=false, unchanged update=true; malformed count/result rows fail rather than appear missing. |
| Cross-service freshness | Prime and reuse readers; test create/update/delete for each of six directed writer→reader pairings in one shared fixture. |
| Setup | Third-only cold setup, repeated/concurrent all-three setup, preserved rows/grants, repaired constraints and each missing/stale procedure; one application table/three columns. |
| Failure boundary | Missing procedures yield SQL2812 without automatic repair; explicit setup restores operation. Missing table/storage and real denied execution remain failures. |
| Type compatibility | An owned incompatible type causes explicit setup failure without drop/recreate or data loss. |
| Configuration order | Fresh full-library hosts: third then original EF; original EF then third. No forced old configuration; isolated third provider discovery also succeeds. |
| Isolation/cleanup | Assert older implementation/helper types absent in third-only assembly; copy only required DLLs, remove generated fixture/principal/temp assets in finally, preserve normal data/permissions. |

Expected EF calls may use CommandType.Text with the exact parameterized EXEC templates; that
is procedure execution. Do not accept arbitrary SQL merely because it contains EXEC, or accept
zero intercepted commands as proof. Separate bootstrap and exact provider metadata observation
from the normal-operation guard. Keep the old EF scalar-parameter assertions distinct from TVP checks.

## Window Checks

```powershell
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug -SqlServer localhost -Implementation All
```

The fake suite runs once for shared view behavior. Real copied hosts test all three configured
choices: populated/empty/error, default/blank/case/trim/unknown selection, Retry, data preservation
and actual selected-provider observation.

Third-service fixtures are prepared in a separate child process. Fresh Full and ColdClose UI
hosts must not call third-service setup before their first request. While cold preparation is
held pending, verify first feedback/Dispatcher work and close within one second, cancellation
and no late mutation. Supplied-result layout for up to 1,000 users also stays within one second.
Record UI responsiveness separately from total database query duration; claim no speed ranking.

For a real missing-procedure window, remove only the owned read-all procedure, assert safe
storage feedback and enabled Retry, prove it remains absent, repair through explicit setup,
then Retry once and observe unchanged fixture rows. Missing execution permission must use
safe access feedback. Never include raw provider text or connection details in the window.

## Interactive Acceptance

```powershell
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Interactive
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -SqlServer localhost -Implementation EntityFrameworkStoredProcedures -Interactive
```

The second command is the planned use of the existing Interactive option in the copied real
host, keeping its owned fixture available until the window closes. Check keyboard navigation,
1,000-row scroll, wrapped/complete text, readability after resizing, Retry focus and moving/
closing a pending window; inspect the actual third-configured window as well.

Earlier manual acceptance is still unexecuted. Previous Computer Use initialization rejected
the WSL workspace with `sandboxCwd is not a local file URI`, including after a kernel reset.
Reattempt during implementation; retain exact failure and outstanding status if still unavailable.
Automated state/Dispatcher assertions cannot substitute for visual/keyboard acceptance.

## Completion Evidence to Record During Implementation

No results below are claimed by planning. Record build/runtime-DLL results, each selected
contract outcome, all-six procedure observations, TVP boundaries, six-way freshness, independent
compile/run and configuration-order checks, setup/grant/schema preservation, real failure/Retry,
cold/supplied-result timings and owned cleanup. Distinguish passed, failed and unexecuted checks.

Verify no implementation diff against the feature's base for SqlUserService.cs, EfUserService.cs,
UserDbContext.cs, UserDbConfiguration.cs, IUserService.cs, User.cs, DuplicateLoginException.cs and
Database/Schema.sql. Preserve the user's pre-existing App.config edit rather than comparing its
local selection to the missing/blank Sql fallback.

Map evidence to FR-001–FR-013 and SC-001–SC-007 before claiming complete verification.
New service, procedure/type installation and runtime/interactive checks remain unimplemented
or unexecuted until the implementation phase.
