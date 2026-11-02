# Contract: Implementation Selection and Application Behavior

## Service factory

Add UserServiceFactory in the existing library:

`IUserService Create(string implementation, string connectionString)`

| implementation input | Result |
|---|---|
| null, empty, whitespace | SqlUserService |
| Sql after trimming, case-insensitive | SqlUserService |
| EntityFramework after trimming, case-insensitive | EfUserService |
| Other nonblank value | ArgumentException identifying the invalid choice; no silent fallback |

The factory does not read files, open connections, initialize EF/model/storage, or cache a service.
Validate the implementation choice before constructing its selected service. Direct construction
of the original SqlUserService and new EfUserService stays supported.

## Application settings

Keep the current UserDatabase connection string and providerName=System.Data.SqlClient.
Add this application-level selection:

```xml
<appSettings>
  <add key="UserServiceImplementation" value="Sql" />
</appSettings>
```

EntityFramework is the alternative value. MainWindow's existing lazy production factory reads
this setting and UserDatabase, then calls UserServiceFactory. Connection/provider configuration
must not be resolved eagerly in its constructor. Missing/invalid connection and unknown choice
continue through the current safe configuration-failure UI.

Settings are selected on launch; configuration hot reload and an in-window picker are outside
scope. Both choices target the same configured catalog and permissions. Default remains Sql.

## Window contract

Retain the existing UsersGrid, LoadStatusText and RetryButton identifiers and all previous
read-only list behaviors: explicit fields, source order, wrapped long text, keyboard access,
loading/empty/failure states, one in-flight request, Retry and terminal closure.

The selected service must preserve the direct SQL exception categories expected by the current
window. Keep retrying in the window's shared load path; do not add automatic provider retries.

On the first cold EF request, model preparation must not freeze the window before the first
await yields. Closing must remain immediate even if initialization/cancellation completes later.
No setup or write is permitted simply because the implementation was selected.

## Package/runtime contract

Use exact EntityFramework 6.5.2 references in both classic projects; retain net48/C# 7.3 and
System.Data.SqlClient. Copy-local output includes EntityFramework.dll and EntityFramework.SqlServer.dll
beside application/service assemblies. Do not use the Microsoft.Data.SqlClient-based EF provider.

One code-based UserDbConfiguration associated with UserDbContext establishes the EF SQL provider
and disables automatic initialization before use. Do not depend on NuGet configuration transforms
or the PowerShell executable's configuration. Do not introduce another conflicting DbConfiguration.

Disposable SQL window hosts copy the full built DLL/config set. A provider choice must work from
the copied output directory without a package-cache path or manually preloaded EF assemblies.

## Validation entry points

Extend existing script interfaces, retaining default behavior:

| Script | Selection | Behavior |
|---|---|---|
| scripts/Test-UserDatabaseService.ps1 | -Implementation Sql, EntityFramework or Both; default Sql | Same service scenarios per provider; Both adds parity/mixed-provider and EF parameter checks. |
| scripts/Test-MainWindow.ps1 | -SqlServer plus -Implementation Sql, EntityFramework or Both; default Sql | Real-source host exercises each selected configuration, first cold EF use and safe failure/retry. |
| scripts/Test-MainWindow.ps1 | Default fake-source mode | Provider-independent suite remains available; do not mislabel it as real EF validation. |

-Configuration Debug/Release, existing -Phase, and -Interactive remain supported where already
present. Real-provider results identify which provider was tested. Test commands do not point
at normal user data for destructive setup, invalid-schema or permission scenarios.
