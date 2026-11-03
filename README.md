# WPF User Directory

A read-only Windows desktop user directory targeting **.NET Framework 4.8** with
**C# 7.3**, using WPF (XAML and C#). Compare the original ADO.NET service with
a parallel Entity Framework 6.5.2 implementation against the same SQL Server data.

## Open and run in Visual Studio

1. Open `HelloWorldWpf48.sln` in Visual Studio.
2. Select **Debug** and **Any CPU** in the toolbar.
3. Press **F5** to build and run with the debugger, or **Ctrl+F5** to run without it.
4. The main window automatically loads users from the configured **UserDatabase** source.
   It shows **Name**, **Login**, and **Age** in login order. Use the keyboard or scrollbars
   to reach all rows and complete field values.
5. An empty source shows **No users found**. A loading failure shows a safe explanation and
   **Retry**; Retry is unavailable while a request is pending. You can move or close the
   window during loading.

The installed Visual Studio Community is version 18 (Visual Studio 2026).
Its MSBuild tools and the installed .NET Framework 4.8 reference assemblies
are used to build this example. The installed .NET Framework 4.8.1 runtime
can run the resulting application.

## Build from Developer PowerShell for Visual Studio

From the directory containing the solution:

```powershell
msbuild .\HelloWorldWpf48.sln -restore /t:Build /p:Configuration=Debug /p:Platform="Any CPU"
.\HelloWorldWpf48\bin\Debug\HelloWorldWpf48.exe
```

Use Visual Studio's MSBuild for this classic .NET Framework WPF project.

## Files to explore

- `HelloWorldWpf48/MainWindow.xaml`: read-only user grid, loading status, and Retry.
- `HelloWorldWpf48/MainWindow.xaml.cs`: lazy source creation, async loading/retry, and shutdown.
- `HelloWorldWpf48/App.xaml`: starts the main window.
- `HelloWorldWpf48/HelloWorldWpf48.csproj`: project settings, including
  `<TargetFrameworkVersion>v4.8</TargetFrameworkVersion>` and
  `<LangVersion>7.3</LangVersion>`.

The view does not create, edit, delete, seed, or initialize user storage. Prepare the
database explicitly using the service setup described below before normal use. Missing
settings or unavailable/unprepared storage produce an error rather than an empty result.

### Window validation

After restoring and building, run the window checks in Windows PowerShell:

```powershell
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1
# Validate the real SQL source using an owned disposable database:
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -SqlServer localhost -Implementation Both
# Open interactive views for keyboard, readability, and pending-operation checks:
powershell.exe -NoProfile -STA -File .\scripts\Test-MainWindow.ps1 -Interactive
```

Use -Configuration Release after building Release, or -Phase US1, -Phase US2, or
-Phase US3 to run one story's controlled checks. The default suite uses fake data and covers 1/100/1,000 rows,
duplicate names, Unicode, zero age, long values, loading, empty results, failures, Retry,
and closing while work is pending. The optional SQL mode runs each selected provider in a fresh copied executable host, including
EF cold initialization and cancellation. It creates a separate temporary
host/configuration and a randomly named test database, then removes both. It does not
change the normal connection or server authentication settings.

See specs/002-ef-user-service/quickstart.md for comparison evidence and outstanding manual checks.
The inherited scenarios are in specs/001-display-user-list/quickstart.md.

## SQL Server user service

The solution also contains **UserDatabaseService**, a .NET Framework 4.8 / C# 7.3
class library referenced by the WPF project. `SqlUserService` uses ADO.NET directly;
`EfUserService` independently implements the same reads and CRUD using EF6. Both use
`System.Data.SqlClient`, the same `IUserService` contract and the same `User` model.
Both projects restore the exact EntityFramework 6.5.2 NuGet package. Keep
`EntityFramework.dll` and `EntityFramework.SqlServer.dll` beside the deployed application.

`dbo.[User]` is the only application table:

| Column | SQL type | Rules |
| --- | --- | --- |
| Name | nvarchar(100) | Required, nonblank |
| Login | nvarchar(100) | Required, primary key, case-insensitive and accent-sensitive |
| Age | int | Required, zero or greater |

The service trims names and logins before saving or looking up users. Login is
the user's immutable key: `alice` and `ALICE` identify the same user, while
accented letters remain distinct. SQL Server enforces uniqueness even when
another application writes directly to the table. Names need not be unique.

### Connection and database setup

Edit the `UserDatabase` connection string in `HelloWorldWpf48/App.config`.
The default uses the local default SQL Server instance:

```text
Data Source=localhost;Initial Catalog=HelloWorldUsers;Integrated Security=True
```

In SSMS, connect to `localhost` using Windows Authentication and refresh Databases.
The selected Windows identity must be able to connect to SQL Server. Creating a
new database requires database creation permission; schema setup requires DDL
permission in the selected database. Normal CRUD operations require SELECT,
INSERT, UPDATE, and DELETE permission on `dbo.[User]`.

`CreateOrUpdateDatabaseAsync()` creates the named database if missing, then
applies the embedded `UserDatabaseService/Database/Schema.sql` inside a
transaction. Repeated calls preserve rows and restore missing check constraints;
concurrent schema updates are serialized with a SQL Server application lock.
Future schema changes should be added to that script as repeatable, non-destructive
SQL updates. This initial scaffold expects the table layout above; it does not
automatically transform an unrelated existing table. No database is created
just by launching the WPF sample: call setup explicitly when you want it.

### Choose the implementation

In `HelloWorldWpf48/App.config`, select the service used by the main window:

```xml
<appSettings>
  <add key="UserServiceImplementation" value="EntityFramework" />
</appSettings>
```

The checked-in selection is `EntityFramework`. Missing or blank values select `Sql`; both
names accept surrounding whitespace and ignore case. Unknown values show the
configuration error with Retry. Both choices use the same `UserDatabase` connection
string. Rebuild and restart after changing source configuration.

You can also construct either service directly or use
`UserServiceFactory.Create("EntityFramework", connectionString)`. EF uses a fresh
context per operation and no tracking for reads, so reused service instances see
changes made through the other implementation. Automatic database initialization
and EF migrations are disabled. EF independently validates connections and implements all
seven operations, including setup through EF contexts, commands and transactions. It never
constructs or calls `SqlUserService`. Both use the shared schema definition. The original
`SqlUserService` class implementation is preserved; `DuplicateLoginException` is a separate
shared contract file so deleting the SQL implementation does not break the EF variant.
The main window only reads data and never invokes setup.

### Calling the API from C#

For example, inside an async WPF event handler:

```csharp
using System.Configuration;
using UserDatabaseService;

// In your async method:
// Replace EfUserService with SqlUserService to compare the original.
IUserService users = new EfUserService(
    ConfigurationManager.ConnectionStrings["UserDatabase"].ConnectionString);

await users.CreateOrUpdateDatabaseAsync();

try
{
    await users.CreateAsync(new User { Name = "Alice", Login = "alice", Age = 30 });
}
catch (DuplicateLoginException)
{
    // Display a message asking for a different login.
}

User alice = await users.GetByLoginAsync("alice"); // null if missing
var selected = await users.GetByLoginsAsync(new[] { "alice", "bob" });
var everyone = await users.GetAllAsync();

bool updated = await users.UpdateAsync(
    new User { Name = "Alice Updated", Login = "alice", Age = 31 });
bool deleted = await users.DeleteAsync("alice");
```

`UpdateAsync` changes name and age for the supplied login. Updates and deletes
return `false` when no matching user exists. Multiple-login queries return only
existing matches, once each, ordered by login. An empty input returns an empty
list. Supply at most 2000 distinct logins per call to stay below SQL Server's
parameter limit. All seven operations accept an optional `CancellationToken`. EF performs cold model
preparation on a worker flow and uses native asynchronous SQL I/O.
Invalid values produce argument exceptions; connection, permission, and other
SQL errors propagate as `SqlException`. Database queries use typed parameters.

### Integration check

Prove EF builds and runs without the SQL implementation (requires the built EF DLLs and
Visual Studio C# compiler):

```powershell
.\scripts\Test-EfIndependence.ps1 -Server localhost
```

This compiles EF and shared contracts into a temporary executable, excluding
`SqlUserService.cs`, the two-provider factory and the normal service DLL, then exercises
all seven operations using an owned disposable database.


Build the solution, then run this in Windows PowerShell:

```powershell
.\scripts\Test-UserDatabaseService.ps1 -Implementation Both
# Or explicitly select another SQL Server instance:
.\scripts\Test-UserDatabaseService.ps1 -Server 'localhost\SQLEXPRESS' -Implementation Both
```

Use `-Implementation Sql` or `-Implementation EntityFramework` for one provider; the
default remains `Sql`. `Both` also verifies cross-provider visibility and EF Unicode
parameter binding for 1 and 2,000 login inputs. This is a correctness comparison;
no performance ranking is claimed.

The check creates a randomly named `UserServiceTest_...` database and removes
it afterward. It verifies schema creation and updates, data preservation,
concurrent initialization, CRUD, single/multiple-login queries, database-level
uniqueness, input validation, parameterized queries, and cancellation. Use
`-Configuration Release` after building Release.
