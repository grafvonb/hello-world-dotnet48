using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Entity;
using System.Data.Entity.Core;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Threading.Tasks;

namespace UserDatabaseService
{
    public sealed class EfStoredProcedureUserService : IUserService
    {
        private readonly string connectionString;
        private readonly string masterConnectionString;
        private readonly string databaseName;

        public EfStoredProcedureUserService(string connectionString)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
                throw new ArgumentException("A SQL Server connection string is required.", nameof(connectionString));

            var builder = new SqlConnectionStringBuilder(connectionString);
            databaseName = builder.InitialCatalog;
            if (string.IsNullOrWhiteSpace(databaseName) || databaseName.Length > 128)
                throw new ArgumentException("Specify a database name of 1-128 characters in Initial Catalog.", nameof(connectionString));
            if (new[] { "master", "model", "msdb", "tempdb" }.Contains(databaseName, StringComparer.OrdinalIgnoreCase))
                throw new ArgumentException("Use an application database, not a SQL Server system database.", nameof(connectionString));
            if (!string.IsNullOrEmpty(builder.AttachDBFilename))
                throw new ArgumentException("Use a named database without AttachDBFilename.", nameof(connectionString));

            this.connectionString = builder.ConnectionString;
            builder.InitialCatalog = "master";
            // A canceled DDL batch must end its session, releasing any session-owned creation lock.
            builder.Pooling = false;
            masterConnectionString = builder.ConnectionString;
        }

        public async Task CreateOrUpdateDatabaseAsync(CancellationToken cancellationToken = default(CancellationToken))
        {
            try
            {
                await ExecuteAsync(masterConnectionString, context =>
                {
                    context.Database.CommandTimeout = 60;
                    return context.Database.ExecuteSqlCommandAsync(TransactionalBehavior.DoNotEnsureTransaction,
                        @"
DECLARE @resource nvarchar(255) = N'UserDatabaseService.CreateDatabase:' + UPPER(@databaseName);
DECLARE @result int;
EXEC @result = sys.sp_getapplock @Resource = @resource,
    @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 30000;
IF @result < 0 THROW 50001, 'Could not acquire the user database creation lock.', 1;
BEGIN TRY
    IF DB_ID(@databaseName) IS NULL CREATE DATABASE [" + databaseName.Replace("]", "]]") + @"];
    EXEC sys.sp_releaseapplock @Resource = @resource, @LockOwner = 'Session';
END TRY
BEGIN CATCH
    EXEC sys.sp_releaseapplock @Resource = @resource, @LockOwner = 'Session';
    THROW;
END CATCH;",
                        cancellationToken, new SqlParameter("@databaseName", SqlDbType.NVarChar, 128) { Value = databaseName });
                }, cancellationToken).ConfigureAwait(false);
            }
            catch (SqlException exception) when (exception.Number == 1801)
            {
                // Another explicit initializer created the catalog first.
            }

            await ExecuteAsync(async context =>
            {
                context.Database.CommandTimeout = 60;
                await context.Database.Connection.OpenAsync(cancellationToken).ConfigureAwait(false);
                using (var transaction = context.Database.BeginTransaction())
                {
                    await context.Database.ExecuteSqlCommandAsync(TransactionalBehavior.DoNotEnsureTransaction, @"
DECLARE @result int;
EXEC @result = sys.sp_getapplock @Resource = N'UserDatabaseService.Schema',
    @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;
IF @result < 0 THROW 50001, 'Could not acquire the user schema update lock.', 1;",
                        cancellationToken).ConfigureAwait(false);

                    foreach (var resource in new[] { "Schema", "StoredProcedures.Bootstrap", "StoredProcedures.GetAll",
                        "StoredProcedures.GetByLogin", "StoredProcedures.GetByLogins", "StoredProcedures.Create",
                        "StoredProcedures.Update", "StoredProcedures.Delete" })
                    {
                        string sql;
                        using (var stream = typeof(EfStoredProcedureUserService).Assembly
                            .GetManifestResourceStream("UserDatabaseService.Database." + resource + ".sql"))
                        {
                            if (stream == null)
                                throw new InvalidOperationException("An embedded database setup resource is missing.");
                            using (var reader = new StreamReader(stream))
                                sql = reader.ReadToEnd();
                        }
                        await context.Database.ExecuteSqlCommandAsync(TransactionalBehavior.DoNotEnsureTransaction,
                            sql, cancellationToken).ConfigureAwait(false);
                    }
                    cancellationToken.ThrowIfCancellationRequested();
                    transaction.Commit();
                    return 0;
                }
            }, cancellationToken).ConfigureAwait(false);
        }

        public Task<IReadOnlyList<User>> GetAllAsync(CancellationToken cancellationToken = default(CancellationToken))
        {
            return QueryAsync("EXEC dbo.User_GetAll;", new object[0], cancellationToken);
        }

        public async Task<User> GetByLoginAsync(string login, CancellationToken cancellationToken = default(CancellationToken))
        {
            var parameter = TextParameter("@Login", ValidateText(login, nameof(login)));
            var users = await QueryAsync("EXEC dbo.User_GetByLogin @Login = @Login;",
                new object[] { parameter }, cancellationToken).ConfigureAwait(false);
            return users.SingleOrDefault();
        }

        public Task<IReadOnlyList<User>> GetByLoginsAsync(IEnumerable<string> logins, CancellationToken cancellationToken = default(CancellationToken))
        {
            if (logins == null)
                throw new ArgumentNullException(nameof(logins));
            cancellationToken.ThrowIfCancellationRequested();
            var values = logins.Select(login => ValidateText(login, nameof(logins)))
                .Distinct(StringComparer.Ordinal).Take(2001).ToArray();
            if (values.Length > 2000)
                throw new ArgumentException("Supply at most 2000 distinct logins per query.", nameof(logins));
            if (values.Length == 0)
                return Task.FromResult<IReadOnlyList<User>>(new List<User>().AsReadOnly());

            return ExecuteAsync<IReadOnlyList<User>>(async context =>
            {
                using (var table = new DataTable())
                {
                    var column = table.Columns.Add("Login", typeof(string));
                    column.MaxLength = 100;
                    column.AllowDBNull = false;
                    foreach (var value in values)
                        table.Rows.Add(value);
                    var parameter = new SqlParameter("@Logins", SqlDbType.Structured)
                    {
                        TypeName = "dbo.UserLoginList",
                        Value = table
                    };
                    return (await context.Database.SqlQuery<User>("EXEC dbo.User_GetByLogins @Logins = @Logins;",
                        parameter).ToListAsync(cancellationToken).ConfigureAwait(false)).AsReadOnly();
                }
            }, cancellationToken);
        }

        public async Task CreateAsync(User user, CancellationToken cancellationToken = default(CancellationToken))
        {
            var snapshot = Snapshot(user);
            try
            {
                await ExecuteAsync(context => context.Database.ExecuteSqlCommandAsync(
                    "EXEC dbo.User_Create @Name = @Name, @Login = @Login, @Age = @Age;",
                    cancellationToken, UserParameters(snapshot)), cancellationToken).ConfigureAwait(false);
            }
            catch (SqlException exception) when (exception.Number == 2601 || exception.Number == 2627)
            {
                throw new DuplicateLoginException(snapshot.Login, exception);
            }
        }

        public Task<bool> UpdateAsync(User user, CancellationToken cancellationToken = default(CancellationToken))
        {
            var parameters = UserParameters(Snapshot(user));
            return WriteResultAsync("EXEC dbo.User_Update @Name = @Name, @Login = @Login, @Age = @Age;",
                parameters, cancellationToken);
        }

        public Task<bool> DeleteAsync(string login, CancellationToken cancellationToken = default(CancellationToken))
        {
            var parameter = TextParameter("@Login", ValidateText(login, nameof(login)));
            return WriteResultAsync("EXEC dbo.User_Delete @Login = @Login;", new object[] { parameter }, cancellationToken);
        }

        private Task<IReadOnlyList<User>> QueryAsync(string invocation, object[] parameters, CancellationToken token)
        {
            return ExecuteAsync<IReadOnlyList<User>>(async context =>
                (await context.Database.SqlQuery<User>(invocation, parameters)
                    .ToListAsync(token).ConfigureAwait(false)).AsReadOnly(), token);
        }

        private Task<bool> WriteResultAsync(string invocation, object[] parameters, CancellationToken token)
        {
            return ExecuteAsync(async context =>
            {
                var rows = await context.Database.SqlQuery<int>(invocation, parameters)
                    .ToListAsync(token).ConfigureAwait(false);
                if (rows.Count != 1 || (rows[0] != 0 && rows[0] != 1))
                    throw new InvalidOperationException("The user procedure returned an invalid write result.");
                return rows[0] == 1;
            }, token);
        }

        private Task<T> ExecuteAsync<T>(Func<StoredProcedureUserDbContext, Task<T>> operation, CancellationToken token)
        {
            return ExecuteAsync(connectionString, operation, token);
        }

        private static Task<T> ExecuteAsync<T>(string connection, Func<StoredProcedureUserDbContext, Task<T>> operation, CancellationToken token)
        {
            // EF6 may prepare its model/provider synchronously before the first asynchronous I/O.
            return Task.Run(async () =>
            {
                try
                {
                    token.ThrowIfCancellationRequested();
                    using (var context = new StoredProcedureUserDbContext(connection))
                    {
                        context.Database.Initialize(false);
                        token.ThrowIfCancellationRequested();
                        return await operation(context).ConfigureAwait(false);
                    }
                }
                catch (Exception exception)
                {
                    if (exception is EntityException || exception is SqlException || exception is OperationCanceledException)
                        for (var cause = exception; cause != null; cause = cause.InnerException)
                            if (cause is SqlException || cause is OperationCanceledException)
                            {
                                var sql = cause as SqlException;
                                // Framework SqlClient can surface an attention as SQL0 instead of cancellation.
                                // Do not reclassify real server errors or a SQL0 without our canceled token.
                                if (sql != null && token.IsCancellationRequested &&
                                    sql.Errors.Cast<SqlError>().All(error => error.Number == 0 && error.State == 0 && error.Class == 11))
                                    throw new OperationCanceledException("The database operation was canceled.", sql, token);
                                ExceptionDispatchInfo.Capture(cause).Throw();
                            }
                    throw;
                }
            }, token);
        }

        private static User Snapshot(User user)
        {
            if (user == null)
                throw new ArgumentNullException(nameof(user));
            if (user.Age < 0)
                throw new ArgumentOutOfRangeException(nameof(user), "Age cannot be negative.");
            return new User { Name = ValidateText(user.Name, nameof(user.Name)),
                Login = ValidateText(user.Login, nameof(user.Login)), Age = user.Age };
        }

        private static string ValidateText(string value, string parameterName)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException("A non-empty value is required.", parameterName);
            value = value.Trim();
            if (value.Length > 100)
                throw new ArgumentException("The value cannot exceed 100 characters.", parameterName);
            return value;
        }

        private static SqlParameter TextParameter(string name, string value)
        {
            return new SqlParameter(name, SqlDbType.NVarChar, 100) { Value = value };
        }

        private static object[] UserParameters(User user)
        {
            return new object[] { TextParameter("@Name", user.Name), TextParameter("@Login", user.Login),
                new SqlParameter("@Age", SqlDbType.Int) { Value = user.Age } };
        }
    }
}
