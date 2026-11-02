param(
    [string]$Server = 'localhost',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [ValidateSet('Sql', 'EntityFramework', 'Both')][string]$Implementation = 'Sql'
)

$ErrorActionPreference = 'Stop'
$assemblyPath = Join-Path $PSScriptRoot "..\UserDatabaseService\bin\$Configuration\UserDatabaseService.dll"
if (-not (Test-Path $assemblyPath)) {
    throw 'Build the solution before running this integration test.'
}
$assemblyPath = (Resolve-Path $assemblyPath).Path
$directory = Split-Path $assemblyPath
Add-Type -Path (Join-Path $directory 'EntityFramework.dll')
Add-Type -Path (Join-Path $directory 'EntityFramework.SqlServer.dll')
Add-Type -Path $assemblyPath

# This test owns a fresh, randomly named database and removes it in finally.
Add-Type -ReferencedAssemblies $assemblyPath, (Join-Path $directory 'EntityFramework.dll'), 'System.Data.dll', 'System.Core.dll', 'System.Xml.dll' -TypeDefinition @'
using System;
using System.Data.Entity;
using System.Data.Entity.Infrastructure.Interception;
using System.Data.SqlClient;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using UserDatabaseService;

public static class UserServiceIntegrationTest
{
    private static int assertions;
    public static void Run(string server, string implementation)
    {
        if (implementation != "Sql") DbConfiguration.SetConfiguration(new UserDbConfiguration());
        foreach (string mode in implementation == "Both" ? new[] { "Sql", "EntityFramework" } : new[] { implementation })
            RunAsync(server, mode).GetAwaiter().GetResult();
        Console.WriteLine("PASS: " + assertions + " service assertions");
    }

    private static async Task RunAsync(string server, string implementation)
    {
        var database = "UserServiceTest_" + Guid.NewGuid().ToString("N");
        var builder = new SqlConnectionStringBuilder
        {
            DataSource = server,
            InitialCatalog = database,
            IntegratedSecurity = true,
            ConnectTimeout = 30
        };
        var service = Service(builder.ConnectionString, implementation);
        try
        {
            await ExpectSqlFailureAsync(() => service.GetAllAsync(), 4060);
            var master = new SqlConnectionStringBuilder(builder.ConnectionString) { InitialCatalog = "master" };
            Assert(Scalar(master.ConnectionString, "SELECT DB_ID(N'" + database + "')") == DBNull.Value, "Reads did not create database");
            Assert((await service.GetByLoginsAsync(new string[0])).Count == 0, "Empty input needs no database");
            // Do not carry the intentional login failure into explicit setup's target connection.
            SqlConnection.ClearAllPools();
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
            Console.WriteLine("PASS: " + implementation + " - original integration scenarios");
            await ExtendedAsync(service, builder.ConnectionString, implementation);
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


    private static IUserService Service(string connection, string implementation)
    {
        if (implementation == "Sql") return new SqlUserService(connection);
        var type = typeof(IUserService).Assembly.GetType("UserDatabaseService.EfUserService", true);
        return (IUserService)Activator.CreateInstance(type, connection);
    }

    private static object Scalar(string connectionString, string sql)
    {
        using (var connection = new SqlConnection(connectionString))
        using (var command = connection.CreateCommand())
        {
            connection.Open(); command.CommandText = sql; return command.ExecuteScalar();
        }
    }

    private static void Execute(string connectionString, string sql)
    {
        using (var connection = new SqlConnection(connectionString))
        using (var command = connection.CreateCommand())
        {
            connection.Open(); command.CommandText = sql; command.ExecuteNonQuery();
        }
    }

    private static string[] Snapshot(System.Collections.Generic.IReadOnlyList<User> users)
    {
        return users.Select(u => u.Login + "|" + u.Name + "|" + u.Age).ToArray();
    }

    private static async Task<bool> RaceInsert(IUserService service)
    {
        try { await service.CreateAsync(new User { Name = "Race", Login = "race", Age = 1 }); return true; }
        catch (DuplicateLoginException) { return false; }
    }

    private static async Task ExtendedAsync(IUserService service, string connection, string implementation)
    {
        var input = new User { Name = " Updated ", Login = " ALICE ", Age = 31 };
        Assert(await service.UpdateAsync(input), "Snapshot update");
        Assert(await service.UpdateAsync(input), "Unchanged update still returns true");
        Assert(input.Name == " Updated " && input.Login == " ALICE ", "Caller input remains unchanged");
        var persisted = await service.GetByLoginAsync("ALICE");
        Assert(persisted.Login == "alice" && persisted.Name == "Updated", "Stored login spelling immutable");
        var created = new User { Name = " New ", Login = " new ", Age = 0 };
        await service.CreateAsync(created);
        Assert(created.Name == " New " && created.Login == " new ", "Create does not normalize caller object");
        await service.CreateAsync(new User { Name = new string('\u0141', 100), Login = new string('x', 100), Age = 0 });
        await service.CreateAsync(new User { Name = "Same", Login = "cafe", Age = 1 });
        await service.CreateAsync(new User { Name = "Same", Login = "caf\u00e9", Age = 2 });
        Assert((await service.GetByLoginAsync("CAF\u00c9")).Age == 2 &&
            (await service.GetByLoginAsync("CAFE")).Age == 1, "Accent-sensitive, case-insensitive identity");
        var raced = await Task.WhenAll(RaceInsert(service), RaceInsert(service));
        Assert(raced.Count(result => result) == 1 && (await service.GetByLoginsAsync(new[] { "race" })).Count == 1,
            "Exactly one insert wins a duplicate race");

        await ExpectAsync<ArgumentException>(() => service.CreateAsync(new User { Name = " ", Login = "invalid", Age = 0 }));
        await ExpectAsync<ArgumentException>(() => service.CreateAsync(new User { Name = new string('x', 101), Login = "invalid", Age = 0 }));
        await ExpectAsync<ArgumentException>(() => service.UpdateAsync(new User { Name = "Ok", Login = new string('x', 101), Age = 0 }));
        await ExpectAsync<ArgumentNullException>(() => service.GetByLoginsAsync(null));
        var canceled = new CancellationToken(true);
        await ExpectAsync<ArgumentNullException>(() => service.GetByLoginsAsync(null, canceled));
        await ExpectAsync<OperationCanceledException>(() => service.GetByLoginsAsync(new[] { " " }, canceled));
        await ExpectAsync<ArgumentException>(() => service.GetByLoginAsync(" ", canceled));
        await ExpectAsync<ArgumentException>(() => service.DeleteAsync(" ", canceled));
        await ExpectAsync<OperationCanceledException>(() => service.CreateOrUpdateDatabaseAsync(canceled));
        await ExpectAsync<OperationCanceledException>(() => service.GetByLoginAsync("alice", canceled));
        await ExpectAsync<OperationCanceledException>(() => service.GetByLoginsAsync(new[] { "alice" }, canceled));
        await ExpectAsync<OperationCanceledException>(() => service.CreateAsync(new User { Name = "Canceled", Login = "canceled", Age = 1 }, canceled));
        await ExpectAsync<OperationCanceledException>(() => service.UpdateAsync(input, canceled));
        await ExpectAsync<OperationCanceledException>(() => service.DeleteAsync("alice", canceled));
        Assert(await service.GetByLoginAsync("canceled") == null, "Canceled create did not persist");

        // Owned fixture only: check provider failures without allowing schema initialization.
        Execute(connection, "EXEC sys.sp_rename N'dbo.User', N'User_ValidationHidden';");
        await ExpectSqlFailureAsync(() => service.GetAllAsync(), 208);
        await ExpectSqlFailureAsync(() => service.CreateAsync(new User { Name = "No table", Login = "none", Age = 0 }), 208);
        await ExpectSqlFailureAsync(() => service.UpdateAsync(input), 208);
        await ExpectSqlFailureAsync(() => service.DeleteAsync("alice"), 208);
        Assert(Scalar(connection, "SELECT OBJECT_ID(N'dbo.[User]', N'U');") == DBNull.Value, "No implicit table creation");
        Execute(connection, "EXEC sys.sp_rename N'dbo.User_ValidationHidden', N'User';");
        var baseline = new SqlUserService(connection);
        Execute(connection, "ALTER TABLE dbo.[User] DROP CONSTRAINT [CK_User_Age];");
        await Task.WhenAll(baseline.CreateOrUpdateDatabaseAsync(), service.CreateOrUpdateDatabaseAsync());
        Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.check_constraints WHERE name=N'CK_User_Age';") == 1,
            "Concurrent mixed setup repairs missing constraint");

        if (implementation == "EntityFramework")
        {
            foreach (var pair in new[] {
                new[] { (IUserService)baseline, service }, new[] { service, (IUserService)baseline } })
            {
                await pair[0].CreateAsync(new User { Name = "Before", Login = "cross", Age = 1 });
                Assert((await pair[1].GetByLoginAsync("cross")).Name == "Before", "Cross-provider create visible");
                await pair[0].UpdateAsync(new User { Name = "After", Login = "cross", Age = 2 });
                Assert((await pair[1].GetByLoginAsync("cross")).Name == "After", "Cross-provider update fresh");
                await pair[0].DeleteAsync("cross");
                Assert(await pair[1].GetByLoginAsync("cross") == null, "Cross-provider delete fresh");
            }
        }

        foreach (int count in new[] { 0, 1, 1000 })
        {
            Execute(connection, "DELETE FROM dbo.[User];");
            var table = new System.Data.DataTable();
            table.Columns.Add("Name", typeof(string)); table.Columns.Add("Login", typeof(string)); table.Columns.Add("Age", typeof(int));
            for (int i = 0; i < count; i++) table.Rows.Add("Name " + i, "user" + i.ToString("D4"), i % 90);
            using (var bulk = new SqlBulkCopy(connection))
            {
                bulk.DestinationTableName = "dbo.[User]";
                bulk.WriteToServer(table);
            }
            Assert(Snapshot(await service.GetAllAsync()).SequenceEqual(Snapshot(await baseline.GetAllAsync())),
                count + " rows equal to original source, values and order");
            var keys = new[] { " USER0000 ", "user0999", "missing", "user0000" };
            Assert(Snapshot(await service.GetByLoginsAsync(keys)).SequenceEqual(Snapshot(await baseline.GetByLoginsAsync(keys))),
                count + " rows: matched/missing multi-lookup matches original");
            var actual = await service.GetByLoginAsync("USER0000");
            var expected = await baseline.GetByLoginAsync("USER0000");
            Assert((actual == null && expected == null) || (actual != null && expected != null &&
                Snapshot(new[] { actual }).SequenceEqual(Snapshot(new[] { expected }))), count + " rows: single lookup matches original");
            Console.WriteLine("PASS: {0} - {1} record comparison", implementation, count);
        }
        var probes = Enumerable.Range(0, 2000).Select(i => "probe" + i.ToString("D4")).ToArray();
        probes[0] = "probe\u0141'brien;--";
        if (implementation == "EntityFramework")
        {
            var capture = new ParameterCapture();
            DbInterception.Add(capture);
            try
            {
                foreach (var values in new[] { probes.Take(1).ToArray(), probes })
                {
                    capture.Reset();
                    await service.GetByLoginsAsync(values);
                    Assert(capture.Calls == 1 && capture.Values.Length == values.Length, "All inputs are SQL parameters");
                    Assert(capture.Types.All(t => t == System.Data.DbType.String), "Unicode parameters");
                    Assert(values.All(value => capture.Values.Contains(value) &&
                        !capture.Text.Contains(value) && !capture.Text.Contains(value.Replace("'", "''"))),
                        "No user values in command literals");
                    Console.WriteLine("PASS: EntityFramework - {0} Unicode-bound lookup parameters", values.Length);
                }
                capture.Reset();
                await ExpectAsync<ArgumentException>(() => service.GetByLoginsAsync(probes.Concat(new[] { "excess" })));
                Assert(capture.Calls == 0, "Oversized lookup rejected before SQL");
            }
            finally { DbInterception.Remove(capture); }
        }
        else { Assert((await service.GetByLoginsAsync(probes)).Count == 0, "2000 inputs accepted"); }
        Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0;") == 1, "No EF history/application tables");
        Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.[User]');") == 3, "Original three-column schema");
        Console.WriteLine("PASS: " + implementation + " - write/input/cancellation/race/schema/failure parity");
    }

    public sealed class ParameterCapture : DbCommandInterceptor
    {
        public int Calls;
        public string Text;
        public string[] Values;
        public System.Data.DbType[] Types;
        public void Reset() { Calls = 0; Text = ""; Values = new string[0]; Types = new System.Data.DbType[0]; }
        public override void ReaderExecuting(System.Data.Common.DbCommand command, DbCommandInterceptionContext<System.Data.Common.DbDataReader> context)
        {
            Calls++;
            Text = command.CommandText;
            Values = command.Parameters.Cast<System.Data.Common.DbParameter>().Select(p => Convert.ToString(p.Value)).ToArray();
            Types = command.Parameters.Cast<System.Data.Common.DbParameter>().Select(p => p.DbType).ToArray();
        }
    }

    private static async Task ExpectAsync<TException>(Func<Task> action) where TException : Exception
    {
        try { await action(); }
        catch (TException) { assertions++; return; }
        throw new Exception("Expected " + typeof(TException).Name);
    }

    private static async Task ExpectSqlFailureAsync(Func<Task> action, int expectedNumber)
    {
        try { await action(); }
        catch (SqlException exception)
        {
            Assert(exception.Number == expectedNumber, "Direct SQL failure preserves provider error number");
            return;
        }
        throw new Exception("Expected direct SQL error " + expectedNumber);
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
        assertions++;
        if (!condition) throw new Exception("FAIL: " + message);
    }
}
'@

[UserServiceIntegrationTest]::Run($Server, $Implementation)
