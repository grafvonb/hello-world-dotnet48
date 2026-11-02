param(
    [string]$Server = 'localhost',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug'
)

$ErrorActionPreference = 'Stop'
$assemblyPath = Join-Path $PSScriptRoot "..\UserDatabaseService\bin\$Configuration\UserDatabaseService.dll"
if (-not (Test-Path $assemblyPath)) {
    throw 'Build the solution before running this integration test.'
}
$assemblyPath = (Resolve-Path $assemblyPath).Path
Add-Type -Path $assemblyPath

# This test owns a fresh, randomly named database and removes it in finally.
Add-Type -ReferencedAssemblies $assemblyPath, 'System.Data.dll', 'System.Core.dll' -TypeDefinition @'
using System;
using System.Data.SqlClient;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using UserDatabaseService;

public static class UserServiceIntegrationTest
{
    public static void Run(string server)
    {
        RunAsync(server).GetAwaiter().GetResult();
    }

    private static async Task RunAsync(string server)
    {
        var database = "UserServiceTest_" + Guid.NewGuid().ToString("N");
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = server,
            InitialCatalog = database,
            IntegratedSecurity = true,
            ConnectTimeout = 30
        };
        var service = new SqlUserService(builder.ConnectionString);
        try
        {
            await service.CreateOrUpdateDatabaseAsync();
            Assert((await service.GetAllAsync()).Count == 0, "New table is empty");
            using (var connection = new SqlConnection(builder.ConnectionString))
            {
                await connection.OpenAsync();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0;";
                    Assert((int)await command.ExecuteScalarAsync() == 1, "Exactly one application table");
                    command.CommandText = "SELECT COUNT(*) FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.[User]');";
                    Assert((int)await command.ExecuteScalarAsync() == 3, "User has exactly three columns");
                }
            }

            await service.CreateAsync(new User { Name = "Alice", Login = "alice", Age = 30 });
            await service.CreateAsync(new User { Name = "Bob", Login = "bob", Age = 0 });
            Assert((await service.GetByLoginAsync(" ALICE ")).Age == 30, "Trimmed, case-insensitive lookup");
            Assert(await service.GetByLoginAsync("missing") == null, "Missing lookup returns null");
            await ExpectAsync<DuplicateLoginException>(() => service.CreateAsync(
                new User { Name = "Duplicate", Login = "ALICE", Age = 40 }));

            var selected = await service.GetByLoginsAsync(new[] { "bob", "missing", "alice", "alice", "ALICE" });
            Assert(selected.Count == 2 && selected[0].Login == "alice" && selected[1].Login == "bob", "IN lookup and ordering");
            Assert((await service.GetByLoginsAsync(new string[0])).Count == 0, "Empty IN lookup");
            Assert(await service.UpdateAsync(new User { Name = "Alice Updated", Login = "alice", Age = 31 }), "Update found user");
            Assert((await service.GetByLoginAsync("alice")).Name == "Alice Updated", "Updated values persisted");
            Assert(!await service.UpdateAsync(new User { Name = "Missing", Login = "missing", Age = 1 }), "Missing update returns false");

            // Simulate a missing constraint to exercise the repeatable schema update.
            using (var connection = new SqlConnection(builder.ConnectionString))
            {
                await connection.OpenAsync();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "ALTER TABLE dbo.[User] DROP CONSTRAINT [CK_User_Age];";
                    await command.ExecuteNonQueryAsync();
                }
            }
            await Task.WhenAll(service.CreateOrUpdateDatabaseAsync(), service.CreateOrUpdateDatabaseAsync());
            Assert((await service.GetAllAsync()).Count == 2, "Schema updates preserve data");

            using (var connection = new SqlConnection(builder.ConnectionString))
            {
                await connection.OpenAsync();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "INSERT INTO dbo.[User] ([Name], [Login], [Age]) VALUES (N'Duplicate', N'ALICE', 1);";
                    await ExpectSqlAsync(command, 2627);
                    command.CommandText = "UPDATE dbo.[User] SET [Age] = -1 WHERE [Login] = N'alice';";
                    await ExpectSqlAsync(command, 547);
                }
            }

            var unusualLogin = "o'brien;--";
            await service.CreateAsync(new User { Name = "O'Brien", Login = unusualLogin, Age = 20 });
            Assert((await service.GetByLoginAsync(unusualLogin)).Name == "O'Brien", "Parameterized login with SQL punctuation");
            Assert((await service.GetByLoginsAsync(new[] { unusualLogin, "' OR 1=1 --" })).Count == 1, "Parameterized IN query");
            await ExpectAsync<ArgumentException>(() => service.GetByLoginAsync(" "));
            await ExpectAsync<ArgumentException>(() => service.GetByLoginAsync(new string('x', 101)));
            await ExpectAsync<ArgumentNullException>(() => service.CreateAsync(null));
            await ExpectAsync<ArgumentOutOfRangeException>(() => service.CreateAsync(new User { Name = "Bad", Login = "bad", Age = -1 }));
            await ExpectAsync<ArgumentException>(() => service.GetByLoginsAsync(Enumerable.Range(0, 2001).Select(i => "login" + i)));
            await ExpectAsync<OperationCanceledException>(() => service.GetAllAsync(new CancellationToken(true)));

            Assert(await service.DeleteAsync("bob"), "Delete found user");
            Assert(!await service.DeleteAsync("bob"), "Missing delete returns false");
            Assert(await service.GetByLoginAsync("bob") == null, "Deleted user absent");
            Console.WriteLine("PASS: schema creation/update, concurrent initialization, CRUD, login queries, uniqueness, validation, and cancellation.");
        }
        finally
        {
            SqlConnection.ClearAllPools();
            builder.InitialCatalog = "master";
            using (var connection = new SqlConnection(builder.ConnectionString))
            {
                connection.Open();
                using (var command = connection.CreateCommand())
                {
                    command.CommandText = "IF DB_ID(@database) IS NOT NULL BEGIN ALTER DATABASE [" + database +
                        "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [" + database + "]; END;";
                    command.Parameters.AddWithValue("@database", database);
                    command.ExecuteNonQuery();
                }
            }
            Console.WriteLine("Removed temporary database: " + database);
        }
    }

    private static async Task ExpectAsync<TException>(Func<Task> action) where TException : Exception
    {
        try { await action(); }
        catch (TException) { return; }
        throw new Exception("Expected " + typeof(TException).Name);
    }

    private static async Task ExpectSqlAsync(SqlCommand command, int expectedNumber)
    {
        try { await command.ExecuteNonQueryAsync(); }
        catch (SqlException exception)
        {
            if (exception.Number == expectedNumber) return;
            throw;
        }
        throw new Exception("Expected SQL Server error " + expectedNumber);
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new Exception("FAIL: " + message);
    }
}
'@

[UserServiceIntegrationTest]::Run($Server)
