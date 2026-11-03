param(
    [string]$Server = 'localhost',
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',
    [ValidateSet('Sql', 'EntityFramework', 'EntityFrameworkStoredProcedures', 'Both', 'All')][string]$Implementation = 'Sql'
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
        all = implementation == "All";
        if (implementation != "Sql") DbConfiguration.LoadConfiguration(typeof(IUserService).Assembly);
        var selected = all ? Modes : implementation == "Both" ? Modes.Take(2).ToArray() : new[] { implementation };
        Assert(selected.Length == (all ? 3 : implementation == "Both" ? 2 : 1), "Selector meanings");
        foreach (string mode in selected) RunAsync(server, mode).GetAwaiter().GetResult();
        if (all) SharedAsync(server).GetAwaiter().GetResult();
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
        var type = typeof(IUserService).Assembly.GetType("UserDatabaseService." + (implementation == "EntityFramework" ? "EfUserService" : "EfStoredProcedureUserService"), true);
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

        if (!all && implementation == "EntityFramework")
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

        if (!all) foreach (int count in new[] { 0, 1, 1000 })
        {
            Seed(connection, count);
            await CompareAsync(service, baseline, count);
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
        if (implementation == "EntityFrameworkStoredProcedures") await ProcedureChecksAsync(service, connection);
        Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped=0;") == 1, "No EF history/application tables");
        Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.columns WHERE object_id=OBJECT_ID(N'dbo.[User]');") == 3, "Original three-column schema");
        Console.WriteLine("PASS: " + implementation + " - write/input/cancellation/race/schema/failure parity");
    }


    private static readonly string[] Modes = { "Sql", "EntityFramework", "EntityFrameworkStoredProcedures" };
    private static bool all;

    private static void Seed(string connection, int count)
    {
        Execute(connection, "DELETE FROM dbo.[User];");
        using (var table = new System.Data.DataTable())
        {
            table.Columns.Add("Name", typeof(string)); table.Columns.Add("Login", typeof(string)); table.Columns.Add("Age", typeof(int));
            for (int i = 0; i < count; i++) table.Rows.Add("Name " + i, "user" + i.ToString("D4"), i % 90);
            using (var bulk = new SqlBulkCopy(connection)) { bulk.DestinationTableName = "dbo.[User]"; bulk.WriteToServer(table); }
        }
    }

    private static async Task CompareAsync(IUserService service, IUserService baseline, int count)
    {
        Assert(Snapshot(await service.GetAllAsync()).SequenceEqual(Snapshot(await baseline.GetAllAsync())), count + " ordered records match");
        var keys = new[] { " USER0000 ", "user0999", "missing", "user0000" };
        Assert(Snapshot(await service.GetByLoginsAsync(keys)).SequenceEqual(Snapshot(await baseline.GetByLoginsAsync(keys))), "Multi lookup matches");
        var actual = await service.GetByLoginAsync("USER0000"); var expected = await baseline.GetByLoginAsync("USER0000");
        Assert((actual == null && expected == null) || (actual != null && expected != null &&
            Snapshot(new[] { actual }).SequenceEqual(Snapshot(new[] { expected }))), "Single lookup matches");
    }

    private static async Task SharedAsync(string server)
    {
        var name = "UserServiceTest_" + Guid.NewGuid().ToString("N");
        var builder = new SqlConnectionStringBuilder { DataSource = server, InitialCatalog = name, IntegratedSecurity = true, ConnectTimeout = 30 };
        var connection = builder.ConnectionString;
        builder.InitialCatalog = "master";
        try
        {
            var services = Modes.Select(mode => Service(connection, mode)).ToArray();
            await services[2].CreateOrUpdateDatabaseAsync();
            foreach (int count in new[] { 0, 1, 1000 })
            {
                Seed(connection, count);
                for (int i = 0; i < services.Length; i++)
                {
                    await CompareAsync(services[i], services[0], count);
                    Console.WriteLine("PASS: {0} - {1} shared records / three reads", Modes[i], count);
                }
            }
            for (int writer = 0; writer < 3; writer++)
            for (int reader = 0; reader < 3; reader++)
            {
                if (writer == reader) continue;
                string login = "cross" + writer + reader;
                Assert(await services[reader].GetByLoginAsync(login) == null, "Prime retained reader");
                await services[writer].CreateAsync(new User { Name = "Before", Login = login, Age = 1 });
                Assert((await services[reader].GetByLoginAsync(login)).Name == "Before", "Cross create");
                await services[writer].UpdateAsync(new User { Name = "After", Login = login, Age = 2 });
                Assert((await services[reader].GetByLoginAsync(login)).Age == 2, "Cross update");
                await services[writer].DeleteAsync(login);
                Assert(await services[reader].GetByLoginAsync(login) == null, "Cross delete");
                Console.WriteLine("PASS: fresh {0} -> {1} create/update/delete", Modes[writer], Modes[reader]);
            }
            var before = Snapshot(await services[0].GetAllAsync());
            Execute(connection, "ALTER TABLE dbo.[User] DROP CONSTRAINT CK_User_Age; DROP PROCEDURE dbo.User_GetAll;");
            await Task.WhenAll(services.Select(s => s.CreateOrUpdateDatabaseAsync()));
            Assert(before.SequenceEqual(Snapshot(await services[2].GetAllAsync())), "Mixed setup preserves rows and repairs procedure");
            Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.check_constraints WHERE name=N'CK_User_Age';") == 1, "Mixed constraint repair");
            Console.WriteLine("PASS: all-three concurrent setup preserves users and repairs check/procedure");
        }
        finally
        {
            SqlConnection.ClearAllPools();
            Execute(builder.ConnectionString, "IF DB_ID(N'" + name + "') IS NOT NULL BEGIN ALTER DATABASE [" + name +
                "] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [" + name + "]; END;");
            Console.WriteLine("Removed shared owned fixture: " + name);
        }
    }

    private static async Task ProcedureChecksAsync(IUserService service, string connection)
    {
        var baseline = new SqlUserService(connection);
        var login = "audit\u0141'brien;--";
        var guard = new ProcedureGuard();
        using (var watch = new ConnectionScope(connection, null, null))
        {
            DbInterception.Add(guard);
            try
            {
                await service.CreateAsync(new User { Name = "Audit", Login = login, Age = 0 });
                Assert((await service.GetAllAsync()).Any(u => u.Login == login), "Procedure all");
                Assert((await service.GetByLoginAsync(login)).Name == "Audit", "Procedure single");
                Assert((await service.GetByLoginsAsync(new[] { " " + login + " ", login })).Count == 1 && guard.TvpValues.Length == 1, "Trim and distinct TVP");
                var values = Enumerable.Range(0, 2000).Select(i => "bound" + i).ToArray();
                values[0] = login; values[1] = login.ToUpperInvariant();
                Assert((await service.GetByLoginsAsync(values)).Count == 1 && guard.TvpValues.Length == 2000 &&
                    guard.TvpValues.SequenceEqual(values), "2000 Unicode TVP rows, case variants return unique user");
                int calls = guard.Calls, openings = watch.Openings;
                await ExpectAsync<ArgumentException>(() => service.GetByLoginsAsync(values.Concat(new[] { "excess" })));
                await ExpectAsync<OperationCanceledException>(() => service.GetAllAsync(new CancellationToken(true)));
                Assert(guard.Calls == calls && watch.Openings == openings, "Rejected/canceled input performs no I/O");
                Assert(await service.UpdateAsync(new User { Name = "Audit", Login = login, Age = 0 }), "Procedure unchanged update");
                Assert(!await service.UpdateAsync(new User { Name = "Missing", Login = "auditMissing", Age = 0 }), "Procedure missing update");
                Assert(await service.DeleteAsync(login) && !await service.DeleteAsync(login), "Procedure delete outcomes");
                Assert(guard.Seen.Count == 6, "Every procedure observed through EF");
                Console.WriteLine("PASS: all six exact async EF procedure calls; Unicode TVP 1/2000; 2001 rejected before connection");
            }
            finally { DbInterception.Remove(guard); }
        }

        await CreationCancellationAsync(connection);
        var before = Snapshot(await baseline.GetAllAsync());
        var actions = new Func<Task>[] {
            () => service.GetAllAsync(), () => service.GetByLoginAsync("alice"),
            () => service.GetByLoginsAsync(new[] { "alice" }),
            () => service.CreateAsync(new User { Name = "Missing", Login = "missingProcedure", Age = 0 }),
            () => service.UpdateAsync(new User { Name = "Updated", Login = "alice", Age = 31 }),
            () => service.DeleteAsync("alice") };
        string[] names = { "GetAll", "GetByLogin", "GetByLogins", "Create", "Update", "Delete" };
        for (int i = 0; i < names.Length; i++)
        {
            Execute(connection, "DROP PROCEDURE dbo.User_" + names[i] + ";");
            await ExpectSqlFailureAsync(actions[i], 2812);
            Assert(Scalar(connection, "SELECT OBJECT_ID(N'dbo.User_" + names[i] + "',N'P');") == DBNull.Value, "No implicit procedure repair");
            using (var watch = new ConnectionScope(connection, null, null))
            {
                await ExpectAsync<ArgumentException>(() => service.GetByLoginsAsync(Enumerable.Range(0, 2001).Select(n => "offline" + n)));
                Assert(watch.Openings == 0, "Oversized input rejected with procedure unavailable");
            }
            await service.CreateOrUpdateDatabaseAsync();
        }
        Assert(before.SequenceEqual(Snapshot(await baseline.GetAllAsync())), "Missing-procedure failures preserve rows");

        foreach (string operation in new[] { "Update", "Delete" })
        {
            string parameters = operation == "Update" ? "@Name nvarchar(100), @Login nvarchar(100), @Age int" : "@Login nvarchar(100)";
            foreach (string result in new[] { "SELECT 2;", "SELECT 0 WHERE 1=0;", "SELECT 0 UNION ALL SELECT 1;" })
            {
                Execute(connection, "ALTER PROCEDURE dbo.User_" + operation + " " + parameters + " AS BEGIN SET NOCOUNT ON; " + result + " END;");
                await ExpectAsync<InvalidOperationException>(operation == "Update" ? actions[4] : actions[5]);
            }
            await service.CreateOrUpdateDatabaseAsync();
        }
        Execute(connection, "ALTER PROCEDURE dbo.User_GetAll AS SELECT [Name],[Login],[Age] FROM dbo.[User] WHERE 1=0;");
        await service.CreateOrUpdateDatabaseAsync();
        Assert(before.SequenceEqual(Snapshot(await service.GetAllAsync())), "Stale procedure restored");
        Assert((string)Scalar(connection, "SELECT c.collation_name FROM sys.table_types t JOIN sys.columns c ON c.object_id=t.type_table_object_id WHERE t.name=N'UserLoginList';") == "Latin1_General_100_CI_AS", "TVP column collation");
        Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.indexes i JOIN sys.table_types t ON i.object_id=t.type_table_object_id WHERE t.name=N'UserLoginList' AND i.is_unique=1;") == 0, "TVP accepts case variants");

        Execute(connection, "CREATE USER [ProcedureRuntime] WITHOUT LOGIN; GRANT EXECUTE ON SCHEMA::dbo TO [ProcedureRuntime]; GRANT EXECUTE, REFERENCES ON TYPE::dbo.UserLoginList TO [ProcedureRuntime];");
        try
        {
            var builder = new SqlConnectionStringBuilder(connection) { Pooling = false, ApplicationName = "ProcedureIdentity_" + Guid.NewGuid().ToString("N") };
            var runtime = Service(builder.ConnectionString, "EntityFrameworkStoredProcedures");
            using (var identity = new ConnectionScope(connection, "ProcedureRuntime", builder.ApplicationName))
            {
                Assert(before.SequenceEqual(Snapshot(await runtime.GetAllAsync())), "EXECUTE-only principal can use procedure without table grants");
                Assert((await runtime.GetByLoginsAsync(new[] { (await baseline.GetAllAsync()).First().Login })).Count == 1, "Runtime TVP permissions");
                Execute(connection, "DENY EXECUTE ON OBJECT::dbo.User_GetAll TO [ProcedureRuntime];");
                await ExpectSqlFailureAsync(() => runtime.GetAllAsync(), 229);
                await service.CreateOrUpdateDatabaseAsync();
                await ExpectSqlFailureAsync(() => runtime.GetAllAsync(), 229);
                Assert(identity.Openings > 0, "Runtime impersonation exercised");
            }
            Assert((int)Scalar(connection, "SELECT COUNT(*) FROM sys.database_permissions WHERE grantee_principal_id=USER_ID(N'ProcedureRuntime') AND major_id=OBJECT_ID(N'dbo.User_GetAll') AND state=N'D';") == 1, "ALTER preserves procedure permissions");
        }
        finally { Execute(connection, "DROP USER [ProcedureRuntime];"); }

        Execute(connection, "DROP PROCEDURE dbo.User_GetByLogins; DROP TYPE dbo.UserLoginList; CREATE TYPE dbo.UserLoginList AS TABLE(Login varchar(20));");
        await ExpectSqlFailureAsync(() => service.CreateOrUpdateDatabaseAsync(), 50002);
        Assert(Convert.ToInt32(Scalar(connection, "SELECT c.max_length FROM sys.table_types t JOIN sys.columns c ON c.object_id=t.type_table_object_id WHERE t.name=N'UserLoginList';")) == 20, "Incompatible type not replaced");
        Assert(before.SequenceEqual(Snapshot(await baseline.GetAllAsync())), "Incompatible setup preserves rows");
        Execute(connection, "DROP TYPE dbo.UserLoginList;");
        await service.CreateOrUpdateDatabaseAsync();
        Console.WriteLine("PASS: missing/stale procedures, malformed results, real SQL229, preserved grants, incompatible type and explicit repair");
    }


    public sealed class CreationCancellation : DbCommandInterceptor
    {
        public readonly CancellationTokenSource Cancellation = new CancellationTokenSource();
        public bool Started;
        public override void NonQueryExecuting(System.Data.Common.DbCommand command, DbCommandInterceptionContext<int> context)
        {
            if (command.CommandText.Contains("UserDatabaseService.CreateDatabase:"))
            {
                Started = true;
                Cancellation.CancelAfter(100);
            }
        }
    }

    private static async Task CreationCancellationAsync(string connection)
    {
        var builder = new SqlConnectionStringBuilder(connection) { InitialCatalog = "master", Pooling = false };
        var creation = new CreationCancellation();
        using (var blocker = new SqlConnection(builder.ConnectionString))
        {
            await blocker.OpenAsync();
            using (var command = blocker.CreateCommand())
            {
                command.CommandText = "DECLARE @r int; EXEC @r=sys.sp_getapplock @Resource=@resource,@LockMode='Exclusive',@LockOwner='Session',@LockTimeout=3000; SELECT @r;";
                command.Parameters.Add("@resource", System.Data.SqlDbType.NVarChar, 255).Value =
                    "UserDatabaseService.CreateDatabase:" + new SqlConnectionStringBuilder(connection).InitialCatalog.ToUpperInvariant();
                Assert(Convert.ToInt32(await command.ExecuteScalarAsync()) >= 0, "Hold owned catalog creation lock");
            }
            DbInterception.Add(creation);
            try
            {
                await ExpectAsync<OperationCanceledException>(() =>
                    Service(connection, "EntityFrameworkStoredProcedures").CreateOrUpdateDatabaseAsync(creation.Cancellation.Token));
                Assert(creation.Started, "Setup canceled during executing creation-lock wait");
            }
            finally { DbInterception.Remove(creation); creation.Cancellation.Dispose(); }
        }
        await Service(connection, "EntityFrameworkStoredProcedures").CreateOrUpdateDatabaseAsync();
        Console.WriteLine("PASS: executing creation-lock cancellation, session cleanup and explicit setup recovery");
    }

    public sealed class ProcedureGuard : DbCommandInterceptor
    {
        public int Calls;
        public string[] TvpValues = new string[0];
        public readonly System.Collections.Generic.HashSet<string> Seen = new System.Collections.Generic.HashSet<string>();
        private static readonly string[] Commands = {
            "EXEC dbo.User_GetAll;",
            "EXEC dbo.User_GetByLogin @Login = @Login;",
            "EXEC dbo.User_GetByLogins @Logins = @Logins;",
            "EXEC dbo.User_Create @Name = @Name, @Login = @Login, @Age = @Age;",
            "EXEC dbo.User_Update @Name = @Name, @Login = @Login, @Age = @Age;",
            "EXEC dbo.User_Delete @Login = @Login;" };
        private void Check(System.Data.Common.DbCommand command, bool async)
        {
            Calls++;
            Assert(async && command.CommandType == System.Data.CommandType.Text && Commands.Contains(command.CommandText), "Exact async EXEC allowlist, no inline user-table SQL");
            Seen.Add(command.CommandText);
            foreach (SqlParameter parameter in command.Parameters)
            {
                if (parameter.SqlDbType == System.Data.SqlDbType.Structured)
                {
                    Assert(parameter.TypeName == "dbo.UserLoginList", "Explicit TVP type");
                    var table = parameter.Value as System.Data.DataTable;
                    Assert(table != null && table.Columns.Count == 1 && table.Columns[0].ColumnName == "Login" &&
                        table.Columns[0].DataType == typeof(string) && table.Columns[0].MaxLength == 100 && !table.Columns[0].AllowDBNull, "Unicode TVP metadata");
                    TvpValues = table.Rows.Cast<System.Data.DataRow>().Select(r => (string)r[0]).ToArray();
                }
                else Assert((parameter.SqlDbType == System.Data.SqlDbType.NVarChar && parameter.Size == 100) ||
                    parameter.SqlDbType == System.Data.SqlDbType.Int, "Typed scalar parameters");
            }
        }
        public override void ReaderExecuting(System.Data.Common.DbCommand c, DbCommandInterceptionContext<System.Data.Common.DbDataReader> x) { Check(c, x.IsAsync); }
        public override void NonQueryExecuting(System.Data.Common.DbCommand c, DbCommandInterceptionContext<int> x) { Check(c, x.IsAsync); }
        public override void ScalarExecuting(System.Data.Common.DbCommand c, DbCommandInterceptionContext<object> x) { Check(c, x.IsAsync); }
    }

    public sealed class ConnectionScope : IDbConnectionInterceptor, IDisposable
    {
        private readonly string database, user, application;
        public int Openings;
        public ConnectionScope(string connection, string user, string application)
        {
            database = new SqlConnectionStringBuilder(connection).InitialCatalog;
            this.user = user; this.application = application;
            DbInterception.Add(this);
        }
        private bool Matches(System.Data.Common.DbConnection connection)
        {
            var value = new SqlConnectionStringBuilder(connection.ConnectionString);
            return value.InitialCatalog == database && (application == null || value.ApplicationName == application);
        }
        public void Opening(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext context)
        { if (Matches(connection)) Interlocked.Increment(ref Openings); }
        public void Opened(System.Data.Common.DbConnection connection, DbConnectionInterceptionContext context)
        {
            if (user != null && Matches(connection) && connection.State == System.Data.ConnectionState.Open)
                using (var command = connection.CreateCommand()) { command.CommandText = "EXECUTE AS USER = N'" + user + "';"; command.ExecuteNonQuery(); }
        }
        public void BeginningTransaction(System.Data.Common.DbConnection c, BeginTransactionInterceptionContext x) { }
        public void BeganTransaction(System.Data.Common.DbConnection c, BeginTransactionInterceptionContext x) { }
        public void Closing(System.Data.Common.DbConnection c, DbConnectionInterceptionContext x) { }
        public void Closed(System.Data.Common.DbConnection c, DbConnectionInterceptionContext x) { }
        public void ConnectionStringGetting(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.String> x) { }
        public void ConnectionStringGot(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.String> x) { }
        public void ConnectionStringSetting(System.Data.Common.DbConnection c, DbConnectionPropertyInterceptionContext<System.String> x) { }
        public void ConnectionStringSet(System.Data.Common.DbConnection c, DbConnectionPropertyInterceptionContext<System.String> x) { }
        public void ConnectionTimeoutGetting(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.Int32> x) { }
        public void ConnectionTimeoutGot(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.Int32> x) { }
        public void DatabaseGetting(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.String> x) { }
        public void DatabaseGot(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.String> x) { }
        public void DataSourceGetting(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.String> x) { }
        public void DataSourceGot(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.String> x) { }
        public void Disposing(System.Data.Common.DbConnection c, DbConnectionInterceptionContext x) { }
        public void Disposed(System.Data.Common.DbConnection c, DbConnectionInterceptionContext x) { }
        public void EnlistingTransaction(System.Data.Common.DbConnection c, EnlistTransactionInterceptionContext x) { }
        public void EnlistedTransaction(System.Data.Common.DbConnection c, EnlistTransactionInterceptionContext x) { }
        public void ServerVersionGetting(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.String> x) { }
        public void ServerVersionGot(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.String> x) { }
        public void StateGetting(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.Data.ConnectionState> x) { }
        public void StateGot(System.Data.Common.DbConnection c, DbConnectionInterceptionContext<System.Data.ConnectionState> x) { }
        public void Dispose() { DbInterception.Remove(this); }
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
