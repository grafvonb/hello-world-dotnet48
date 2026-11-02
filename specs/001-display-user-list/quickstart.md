# Quickstart Validation: Main-Window User List

This guide is executed after implementation. Planning has not built or run the new UI.
See [main-window contract](contracts/main-window.md),
[user-source contract](contracts/user-source.md), and [data model](data-model.md).

## Prerequisites

- Windows, Visual Studio MSBuild, and .NET Framework 4.8 reference assemblies.
- A runtime capable of running the existing net48 desktop executable.
- Developer PowerShell for Visual Studio, opened at the repository root.
- Windows PowerShell 5.1 in STA mode for the window harness.
- For real-source checks only: an accessible SQL Server test instance and permission to create
  an owned validation database. The application normally needs only read access to prepared data.

## Build and normal launch

```powershell
msbuild .\HelloWorldWpf48.sln /t:Build /p:Configuration=Debug /p:Platform="Any CPU"
.\HelloWorldWpf48\bin\Debug\HelloWorldWpf48.exe
```

Expect the user list instead of the greeting. Normal startup reads the existing UserDatabase
setting and does not create a database or seed users. An unprepared configured source must
produce failure feedback; it is not a successful empty result.

## Controlled window checks

The following script is planned by this design and will be created during implementation:

```powershell
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug
```

The script loads the built application and service assemblies, supplies controlled factories,
shows real windows, drives Loaded/Retry, and uses a bounded Dispatcher pump with a timeout.
It must fail with a nonzero exit code on an unmet assertion and report tested outcomes.

| Scenario | Expected outcome |
|---|---|
| 1, 100, 1,000 source records | Same count and fields, each record exactly once, unchanged source order. |
| Duplicate names, Unicode, age zero, 100-character text | Values preserved; duplicate names remain separate. |
| Source task remains pending | Loading feedback visible; Retry unavailable; one source call. |
| Empty collection | No users found; no rows or error. |
| Factory throws configuration/argument exception | Configuration failure inside the open window. |
| Generic load failure | Safe failure message and Retry. |
| Failure then successful retry | Current list or empty state replaces the error. |
| Failure then another failure | Retry becomes available again. |
| Repeated Retry input during pending work | No second request and no duplicate rows. |
| Close while pending, cancellation honored | Window closes without a later error/popup. |
| Close while pending, provider ignores cancellation and later succeeds or faults | No post-close UI updates or unhandled errors. |
| All startup/retry/close cases | Zero setup or CRUD calls on the fake. |

Measure loading feedback and completed-result presentation against SC-002. The script must
observe rendered/layout-ready controls after a supplied result, not just private state flags.
Do not manufacture SqlException with reflection; use the real-source cases below.

For keyboard/readability checks, the planned harness also supports a final interactive
1,000-record view:

```powershell
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Configuration Debug -Interactive
```

Use Tab and arrow keys, Page Up/Down, Ctrl+Home/Ctrl+End, and horizontal navigation to read
the complete first/last records, including 100-character values. Try F2 and Delete: records must
remain unchanged. Resize the window and check scrolling. In a failed-source window, reach Retry
with Tab and activate it with Enter or Space. During a pending-source check, move and close the
window; it must respond without waiting for I/O.

## Real SQL smoke check with an owned fixture

Use a fresh Windows PowerShell session so fixture variables remain available. These are explicit
test setup commands, not application behavior. They copy the build and change only the copied
configuration; the source App.config and normal database are untouched.

```powershell
$fixtureName = 'WpfUserList_' + [Guid]::NewGuid().ToString('N')
$fixtureDirectory = Join-Path $env:TEMP $fixtureName
New-Item -ItemType Directory -Path $fixtureDirectory | Out-Null
Copy-Item .\HelloWorldWpf48\bin\Debug\* $fixtureDirectory -Recurse
Add-Type -Path (Join-Path $fixtureDirectory 'UserDatabaseService.dll')
$testServer = 'localhost'
$fixtureConnection = "Data Source=$testServer;Initial Catalog=$fixtureName;Integrated Security=True"
$fixtureService = New-Object UserDatabaseService.SqlUserService -ArgumentList $fixtureConnection
$fixtureService.CreateOrUpdateDatabaseAsync().GetAwaiter().GetResult()
$fixtureConfigPath = Join-Path $fixtureDirectory 'HelloWorldWpf48.exe.config'
[xml]$fixtureConfig = Get-Content -LiteralPath $fixtureConfigPath
$fixtureConfig.configuration.connectionStrings.add |
    Where-Object { $_.name -eq 'UserDatabase' } |
    ForEach-Object { $_.connectionString = $fixtureConnection }
$fixtureConfig.Save($fixtureConfigPath)
$fixtureExe = Join-Path $fixtureDirectory 'HelloWorldWpf48.exe'
Start-Process -FilePath $fixtureExe -Wait
```

Expect the successful empty state. Close the window, then populate only this fixture:

```powershell
$fixtureUsers = @(
    [UserDatabaseService.User]@{ Name = 'Same Name'; Login = 'alice'; Age = 0 }
    [UserDatabaseService.User]@{ Name = 'Same Name'; Login = 'bob'; Age = 30 }
    [UserDatabaseService.User]@{ Name = 'Łukasz'; Login = 'unicode-user'; Age = 42 }
)
foreach ($fixtureUser in $fixtureUsers) {
    $fixtureService.CreateAsync($fixtureUser).GetAwaiter().GetResult()
}
$beforeViewing = $fixtureService.GetAllAsync().GetAwaiter().GetResult() | ConvertTo-Json -Compress
Start-Process -FilePath $fixtureExe -Wait
$afterViewing = $fixtureService.GetAllAsync().GetAwaiter().GetResult() | ConvertTo-Json -Compress
if ($beforeViewing -cne $afterViewing) { throw 'Viewing changed fixture user data.' }
```

Expect three rows in source order, duplicate names retained, zero displayed as zero, and Unicode
unchanged. Synchronous GetAwaiter calls here belong to an external setup shell, never the UI thread.

For negative checks, use only the copied configuration and fixture:

1. Remove the UserDatabase entry from otherwise valid copied configuration XML, then launch.
   Expect a configuration message, an open window, and Retry. Restore the entry afterwards.
2. Use a structurally valid entry with an invalid connection value. Expect configuration feedback.
   Entirely malformed runtime configuration XML is outside the window's error boundary.
3. Point the copied configuration at a unique database name that has not been created, or at an
   owned database without user storage. Expect safe availability/storage feedback, never "No users
   found"; confirm that launching did not create the missing database/table.
4. In SSMS, use a dedicated fixture identity and deny its SELECT permission on the fixture table.
   Expect access feedback. Restore that identity's permission, then use keyboard Retry; expect rows.
   Do not change the normal application's identity permissions.
5. A failed SQL load may wait for the existing connection/command timeout. Move and close the
   window while pending. Do not stop a shared SQL Server instance to simulate a failure.

Record the observed category and result; SQL codes may reflect visibility or access rather than
a uniquely identifiable missing object. Close every test process. In SSMS, remove only the
database named in $fixtureName after checking it matches this session's owned fixture, then remove
the copied build directory when its assemblies are no longer loaded. Keep setup credentials and
connection details out of recorded UI evidence.

## Existing service regression check

This command already exists. It is required if implementation unexpectedly changes service or
schema behavior; it is not a replacement for the window acceptance checks.

```powershell
.\scripts\Test-UserDatabaseService.ps1 -Server 'localhost' -Configuration Debug
```

It owns and removes its own randomly named database. That database cannot be reused for the
separate UI smoke check after the script returns.

## Completion evidence

Record build result, automated window outcomes, manual keyboard/long-value checks, timings,
real-source results, and any checks not run with the reason. Confirm FR-001–FR-011 and
SC-001–SC-005, and update README with the final startup/setup and validation instructions.
No application check in this guide is claimed to have passed merely because planning completed.
