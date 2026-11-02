# WPF Hello World

A local Windows desktop example targeting **.NET Framework 4.8** with
**C# 7.3**, using WPF (XAML and C#). No NuGet packages are required.

## Open and run in Visual Studio

1. Open `HelloWorldWpf48.sln` in Visual Studio.
2. Select **Debug** and **Any CPU** in the toolbar.
3. Press **F5** to build and run with the debugger, or **Ctrl+F5** to run without it.
4. The window shows **Hello, World!**. Click **Say hello** to change the greeting
   to **Hello from C# 7.3!**.

The installed Visual Studio Community is version 18 (Visual Studio 2026).
Its MSBuild tools and the installed .NET Framework 4.8 reference assemblies
are used to build this example. The installed .NET Framework 4.8.1 runtime
can run the resulting application.

## Build from Developer PowerShell for Visual Studio

From the directory containing the solution:

```powershell
msbuild .\HelloWorldWpf48.sln /t:Build /p:Configuration=Debug /p:Platform="Any CPU"
.\HelloWorldWpf48\bin\Debug\HelloWorldWpf48.exe
```

Use Visual Studio's MSBuild for this classic .NET Framework WPF project.

## Files to explore

- `HelloWorldWpf48/MainWindow.xaml`: window layout and controls.
- `HelloWorldWpf48/MainWindow.xaml.cs`: constructor and button click handler.
- `HelloWorldWpf48/App.xaml`: starts the main window.
- `HelloWorldWpf48/HelloWorldWpf48.csproj`: project settings, including
  `<TargetFrameworkVersion>v4.8</TargetFrameworkVersion>` and
  `<LangVersion>7.3</LangVersion>`.

To try a small change, edit the initial greeting in `MainWindow.xaml`, then
build and run again.

## SQL Server user service

The solution also contains **UserDatabaseService**, a .NET Framework 4.8 / C# 7.3
class library referenced by the WPF project. It uses the built-in ADO.NET
`System.Data.SqlClient` provider; no NuGet packages are required. Its C# API is
intended to be called from the desktop app.

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

### Calling the API from C#

For example, inside an async WPF event handler:

```csharp
using System.Configuration;
using UserDatabaseService;

// In your async method:
IUserService users = new SqlUserService(
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
parameter limit. All database methods accept an optional `CancellationToken`.
Invalid values produce argument exceptions; connection, permission, and other
SQL errors propagate as `SqlException`. Database queries use typed parameters.

### Integration check

Build the solution, then run this in Windows PowerShell:

```powershell
.\scripts\Test-UserDatabaseService.ps1
# Or explicitly select another SQL Server instance:
.\scripts\Test-UserDatabaseService.ps1 -Server 'localhost\SQLEXPRESS'
```

The check creates a randomly named `UserServiceTest_...` database and removes
it afterward. It verifies schema creation and updates, data preservation,
concurrent initialization, CRUD, single/multiple-login queries, database-level
uniqueness, input validation, parameterized queries, and cancellation. Use
`-Configuration Release` after building Release.
