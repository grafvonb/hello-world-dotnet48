# Quickstart: Compare All Three User Services

The third service and selectors are implemented. Automated results and outstanding interactive
acceptance are recorded below. See the [plan](plan.md), [user-service contract](contracts/user-service.md),
[procedure contract](contracts/stored-procedures.md) and [selection contract](contracts/implementation-selection.md).

## Prerequisites

- Windows, Visual Studio MSBuild, net48 reference assemblies/runtime and Windows PowerShell 5.1.
- The existing pinned EF6 6.5.2 package/cache or restore access; no package upgrade.
- A test SQL Server instance and an identity allowed to create/drop owned databases and apply
  schema/type/procedure definitions. The setup batches retain the existing effective SQL2012+
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

The third configuration choice is:

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

The second command uses the existing Interactive option in the copied real host, keeping its owned fixture available until the window closes. Check keyboard navigation,
1,000-row scroll, wrapped/complete text, readability after resizing, Retry focus and moving/
closing a pending window; inspect the actual third-configured window as well.

Earlier manual acceptance is still unexecuted. Previous Computer Use initialization rejected
the WSL workspace with `sandboxCwd is not a local file URI`, including after a kernel reset.
Reattempt during implementation; retain exact failure and outstanding status if still unavailable.
Automated state/Dispatcher assertions cannot substitute for visual/keyboard acceptance.

## Recorded Validation — 2026-11-03

Validation used Visual Studio 18 Community MSBuild Debug/Any CPU, .NET Framework 4.8
targets, C# 7.3, EF6 6.5.2 and SQL Server localhost.

| Check | Actual result |
|---|---|
| Restore/build/deployment | PASS: final Windows solution restore/build; both EF DLLs present in service and app outputs; copied hosts resolve their local DLLs. |
| Full service suite | PASS: All mode, **314 assertions**. Original scenarios pass for Sql, EntityFramework and EntityFrameworkStoredProcedures. |
| Read parity | PASS: all three retrieval methods compared for 0/1/1,000 records across all three services in one shared fixture. |
| Procedure/parameter proof | PASS: all six exact async EF invocations observed; scalar types/sizes, actual matched Unicode/punctuation values and 1/2,000-row structured payloads; 2,001 rejected before opening a connection, including while procedures are unavailable. |
| Write and identity parity | PASS: unchanged update=true, missing writes=false, immutable stored login spelling, case/accent, caller objects, duplicate races, validation and cancellation categories. |
| Cross-service state | PASS: all six directed writer→primed-retained-reader create/update/delete pairings; concurrent all-three setup repairs missing check/procedure and preserves rows. |
| Setup/error boundaries | PASS: each missing procedure produces SQL2812 without implicit repair; explicit setup restores it. Stale procedures, invalid result row counts/values, missing table, incompatible type, real SQL229, EXECUTE-only runtime access and retained procedure grants pass. |
| Executing cancellation | PASS: cancellation while waiting on an externally held creation lock is observed as cancellation; the master session is disposed and subsequent explicit setup succeeds. Nonzero SQL error cases remain provider failures. |
| Independent executables | PASS: Both mode, **22 assertions** for EfUserService and **26** for EfStoredProcedureUserService. Third executable contains no older service/context/configuration/factory or baseline service DLL; all seven operations work with normal provider discovery. Three consecutive Both runs also passed after creation serialization. |
| Controlled window suite | PASS: **1,182 assertions**. Loading 1/100/1,000 rows: 168/91/90 ms; supplied-result layout: 47/21/22 ms. Empty/error/Retry and late success/fault/cancel closure pass. |
| Real-source windows | PASS: All mode, **22/22/25 assertions** for Sql/EntityFramework/EntityFrameworkStoredProcedures, respectively. All three selections, configuration failures, populated/empty/errors, Retry and unchanged fixture users pass. |
| Cold UI/order | PASS: separate preparation process, fresh EF cold-close hosts, both normal EF discovery orders, immediate close and no late mutation. All-mode first UI dispatch: 226/245/200 ms; final targeted third-service rerun: 196 ms, with 25 assertions and cold/order checks passing again. All UI thresholds are under one second; query throughput was not benchmarked. |
| Preservation/cleanup | PASS: eight protected baseline files plus App.config byte-identical to the start of implementation. All fixture databases, disposable principal/scopes/interceptors and copied executables are cleaned up. No normal database or normal-account permission was changed. |
| Repository checks | PASS: git diff --check; required .NET build/package exclusions already present. |
| Interactive acceptance | **UNEXECUTED: T007 remains open**, as detailed below. |

Initial validation caught a test metadata cast and a fixture-specific login assumption; those
were corrected. An early cold concurrent-creation run returned SQL0. Catalog creation now uses
a session-owned master lock with an unpooled connection, retaining the existing target-schema
transaction lock. The added executing-cancellation check exposed Framework SqlClient's
attention-only SQL0 behavior; only the documented zero/state-0/class-11 pattern with a canceled
operation token is normalized to cancellation. Other SQL failures are not suppressed and no
automatic retry policy was added. The final checks above passed after these refinements.

### Remaining Manual Acceptance

Computer Use was retried on 2026-11-03 and failed before desktop access, then failed identically
after resetting the JavaScript kernel:

```text
Mcp error: -32602: js: codex/sandbox-state-meta: sandboxCwd is not a local file URI: file:///mnt/c/users/adamb/development/workspace/boczek/learning/wpf/helloworldwpf48
```

The interactive views were not launched after this failure. Keyboard traversal, visual
readability/resize/scroll, Retry focus, moving/closing pending work and actual third-configured
visual inspection remain unexecuted. Earlier features' manual acceptance also remains unexecuted.
Automated state/Dispatcher checks do not replace those checks. T001–T006 are complete; T007
stays unchecked.
