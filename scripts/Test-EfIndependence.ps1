param(
    [string]$Server = 'localhost',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [ValidateSet('EntityFramework', 'EntityFrameworkStoredProcedures', 'Both')][string]$Implementation = 'EntityFramework'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$serviceDirectory = Join-Path $root 'UserDatabaseService'
$build = Join-Path $serviceDirectory "bin\$Configuration"
$programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$compilerPaths = @($env:ProgramFiles, $programFilesX86) | ForEach-Object {
    Join-Path $_ 'Microsoft Visual Studio\*\*\MSBuild\Current\Bin\Roslyn\csc.exe'
}
$compiler = Get-ChildItem -Path $compilerPaths -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
if (!$compiler) { throw 'Visual Studio MSBuild C# compiler is required.' }
$framework = Join-Path $programFilesX86 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'
$implementations = if ($Implementation -eq 'Both') { @('EntityFramework', 'EntityFrameworkStoredProcedures') } else { @($Implementation) }
foreach ($mode in $implementations) {
$serviceClass = if ($mode -eq 'EntityFramework') { 'EfUserService' } else { 'EfStoredProcedureUserService' }
$contextClass = if ($mode -eq 'EntityFramework') { 'UserDbContext' } else { 'StoredProcedureUserDbContext' }
$temporary = Join-Path $env:TEMP ('EfIndependence_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    foreach ($name in 'EntityFramework.dll', 'EntityFramework.SqlServer.dll') {
        Copy-Item (Join-Path $build $name) $temporary
    }
    $hostSource = Join-Path $temporary 'Program.cs'
    $hostCode = @'
using System;
using System.Data;
using System.Data.Entity;
using System.Data.SqlClient;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using UserDatabaseService;

public static class EfIndependenceCheck
{
    private static int assertions;
    private static void Assert(bool condition, string message)
    {
        assertions++;
        if (!condition) throw new Exception("FAIL: " + message);
    }
    public static int Main(string[] args)
    {
        try { RunAsync(args[0]).GetAwaiter().GetResult(); return 0; }
        catch (Exception error)
        {
            var sql = error as SqlException;
            Console.Error.WriteLine(sql == null ? error.Message : "SQL validation failed with provider error " + sql.Number + ": " + sql.Message + "\n" + string.Join("\n", sql.Errors.Cast<SqlError>().Select(e => e.Number + "/" + e.State + "/" + e.Class + ": " + e.Message)) + "\n" + sql.StackTrace);
            return 1;
        }
    }
    private static async Task RunAsync(string server)
    {
        string[] omitted = typeof(__SERVICE__).Name == "EfStoredProcedureUserService"
            ? new[] { "SqlUserService", "EfUserService", "UserDbContext", "UserDbConfiguration", "UserServiceFactory" }
            : new[] { "SqlUserService", "EfStoredProcedureUserService", "StoredProcedureUserDbContext", "UserServiceFactory" };
        foreach (string type in omitted)
            Assert(typeof(__SERVICE__).Assembly.GetType("UserDatabaseService." + type) == null, "Assembly omits " + type);
        var name = "EfIndependenceTest_" + Guid.NewGuid().ToString("N");
        var builder = new SqlConnectionStringBuilder {
            DataSource = server, InitialCatalog = name, IntegratedSecurity = true, ConnectTimeout = 30
        };
        var connection = builder.ConnectionString;
        builder.InitialCatalog = "master";
        var master = builder.ConnectionString;
        IUserService service = new __SERVICE__(connection);
        try
        {
            Assert(Scalar(master, "SELECT DB_ID(N'" + name + "');") == DBNull.Value,
                "Construction did not create storage");
            foreach (string invalid in new[] { null, " ", "invalid", "Data Source=localhost",
                "Data Source=localhost;Initial Catalog=master",
                "Data Source=localhost;Initial Catalog=Valid;AttachDBFilename=C:\\unused.mdf" })
            {
                try { new __SERVICE__(invalid); throw new Exception("Accepted invalid connection"); }
                catch (ArgumentException) { assertions++; }
            }
            // Both first-use setup calls start without the SQL implementation or a prewarmed EF context.
            await Task.WhenAll(service.CreateOrUpdateDatabaseAsync(), service.CreateOrUpdateDatabaseAsync());
            Assert((await service.GetAllAsync()).Count == 0, "Independent setup creates empty storage");
            await service.CreateAsync(new User { Name = " \u0141ukasz ", Login = " ALICE ", Age = 0 });
            var row = await service.GetByLoginAsync(" Alice ");
            Assert(row != null && row.Name == "\u0141ukasz" && row.Login == "ALICE" && row.Age == 0,
                "Independent create and single lookup");
            Assert((await service.GetByLoginsAsync(new[] { "alice", "ALICE", "missing" })).Count == 1,
                "Independent multiple-login lookup");
            try
            {
                await service.CreateAsync(new User { Name = "Duplicate", Login = "alice", Age = 1 });
                throw new Exception("Accepted duplicate login");
            }
            catch (DuplicateLoginException) { assertions++; }
            Assert(await service.UpdateAsync(new User { Name = "Updated", Login = "alice", Age = 42 }),
                "Independent update");
            Assert((await service.GetAllAsync()).Single().Name == "Updated", "Independent ordered read");

            using (var database = new __CONTEXT__(connection))
                await database.Database.ExecuteSqlCommandAsync(
                    "ALTER TABLE dbo.[User] DROP CONSTRAINT [CK_User_Age];");
            await service.CreateOrUpdateDatabaseAsync();
            Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.check_constraints WHERE name=N'CK_User_Age';") == 1
                && (await service.GetAllAsync()).Count == 1, "Independent setup repairs constraints and preserves rows");
            if (typeof(__SERVICE__).Name == "EfStoredProcedureUserService")
            {
                using (var database = new __CONTEXT__(connection))
                    await database.Database.ExecuteSqlCommandAsync("DROP PROCEDURE dbo.User_GetAll;");
                try { await service.GetAllAsync(); throw new Exception("Missing procedure was hidden"); }
                catch (SqlException error) { Assert(error.Number == 2812, "Independent missing procedure remains SQL2812"); }
                Assert(Scalar(connection, "SELECT OBJECT_ID(N'dbo.User_GetAll', N'P');") == DBNull.Value, "No automatic procedure repair");
                await service.CreateOrUpdateDatabaseAsync();
                Assert((await service.GetAllAsync()).Count == 1, "Independent procedure repair preserves user");
            }
            Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0;") == 1,
                "Independent setup creates no history tables");
            Assert(await service.DeleteAsync("alice") && !await service.DeleteAsync("alice"),
                "Independent delete and missing result");
            Assert(!await service.UpdateAsync(new User { Name = "Missing", Login = "alice", Age = 0 }),
                "Independent missing update");
            try
            {
                await service.CreateOrUpdateDatabaseAsync(new CancellationToken(true));
                throw new Exception("Ignored setup cancellation");
            }
            catch (OperationCanceledException) { assertions++; }
            Console.WriteLine("PASS: " + typeof(__SERVICE__).Name + " - " + assertions +
                " independent assertions; all seven operations without other implementation/helper types");
        }
        finally
        {
            SqlConnection.ClearAllPools();
            using (var database = new SqlConnection(master))
            using (var command = database.CreateCommand())
            {
                database.Open();
                command.CommandText = "IF DB_ID(@name) IS NOT NULL BEGIN ALTER DATABASE [" + name +
                    "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [" + name + "]; END;";
                command.Parameters.Add("@name", SqlDbType.NVarChar, 128).Value = name;
                command.ExecuteNonQuery();
            }
            Console.WriteLine("Removed owned independent fixture: " + name);
        }
    }
    private static object Scalar(string connectionString, string text)
    {
        using (var connection = new SqlConnection(connectionString))
        using (var command = connection.CreateCommand())
        {
            connection.Open(); command.CommandText = text; return command.ExecuteScalar();
        }
    }
}
'@
    $hostCode.Replace('__SERVICE__', $serviceClass).Replace('__CONTEXT__', $contextClass) | Set-Content -LiteralPath $hostSource -Encoding UTF8
    $hostExe = Join-Path $temporary 'EfIndependence.exe'
    $arguments = @('/nologo', '/langversion:7.3', '/target:exe', '/nostdlib+', "/out:$hostExe")
    foreach ($name in 'mscorlib', 'System', 'System.Core', 'System.Data', 'System.Xml', 'System.ComponentModel.DataAnnotations') {
        $arguments += '/reference:' + (Join-Path $framework ($name + '.dll'))
    }
    foreach ($name in 'EntityFramework.dll', 'EntityFramework.SqlServer.dll') {
        $arguments += '/reference:' + (Join-Path $temporary $name)
    }
    # Deliberately compile only EF implementation and shared contracts. No baseline DLL is copied.
    $sources = @('IUserService.cs', 'User.cs', 'DuplicateLoginException.cs', ($serviceClass + '.cs'), ($contextClass + '.cs'))
    if ($mode -eq 'EntityFramework') { $sources += 'UserDbConfiguration.cs' }
    foreach ($name in $sources) { $arguments += Join-Path $serviceDirectory $name }
    if ($mode -eq 'EntityFrameworkStoredProcedures') {
        Get-ChildItem (Join-Path $serviceDirectory 'Database\StoredProcedures\*.sql') | ForEach-Object {
            $arguments += '/resource:' + $_.FullName + ',UserDatabaseService.Database.StoredProcedures.' + $_.Name
        }
    }
    $arguments += '/resource:' + (Join-Path $serviceDirectory 'Database\Schema.sql') + ',UserDatabaseService.Database.Schema.sql'
    $arguments += $hostSource
    $process = Start-Process -FilePath $compiler -ArgumentList ($arguments | ForEach-Object { '"' + $_ + '"' }) -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) { throw 'Independent EF compilation failed.' }
    $process = Start-Process -FilePath $hostExe -ArgumentList ('"{0}"' -f $Server) -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) { throw 'Independent EF execution failed.' }
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
}
