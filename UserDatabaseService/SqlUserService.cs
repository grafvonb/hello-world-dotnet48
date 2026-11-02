using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace UserDatabaseService
{
    public sealed class DuplicateLoginException : InvalidOperationException
    {
        public DuplicateLoginException(string login, Exception innerException)
            : base("A user with login '" + login + "' already exists.", innerException)
        {
        }
    }

    public sealed class SqlUserService : IUserService
    {
        private const int MaxTextLength = 100;
        private const int MaxLoginCount = 2000;
        private readonly string connectionString;
        private readonly string masterConnectionString;
        private readonly string databaseName;

        public SqlUserService(string connectionString)
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
            masterConnectionString = builder.ConnectionString;
        }

        public async Task CreateOrUpdateDatabaseAsync(CancellationToken cancellationToken = default(CancellationToken))
        {
            // CREATE DATABASE must run outside a transaction, against master.
            using (var connection = new SqlConnection(masterConnectionString))
            {
                await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
                using (var command = connection.CreateCommand())
                {
                    command.CommandTimeout = 60;
                    command.CommandText = "IF DB_ID(@databaseName) IS NULL CREATE DATABASE [" + databaseName.Replace("]", "]]") + "];";
                    command.Parameters.Add("@databaseName", SqlDbType.NVarChar, 128).Value = databaseName;
                    try
                    {
                        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
                    }
                    catch (SqlException exception) when (exception.Number == 1801)
                    {
                        // Another initializer created the same database between the check and CREATE.
                    }
                }
            }

            using (var connection = new SqlConnection(connectionString))
            {
                await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
                using (var transaction = connection.BeginTransaction())
                using (var command = connection.CreateCommand())
                {
                    command.Transaction = transaction;
                    command.CommandTimeout = 60;
                    command.CommandText = @"
DECLARE @result int;
EXEC @result = sys.sp_getapplock @Resource = N'UserDatabaseService.Schema',
    @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 30000;
IF @result < 0 THROW 50001, 'Could not acquire the user schema update lock.', 1;";
                    await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);

                    using (var stream = typeof(SqlUserService).Assembly.GetManifestResourceStream("UserDatabaseService.Database.Schema.sql"))
                    {
                        if (stream == null)
                            throw new InvalidOperationException("The embedded database schema is missing.");
                        using (var reader = new StreamReader(stream))
                            command.CommandText = reader.ReadToEnd();
                    }

                    await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
                    cancellationToken.ThrowIfCancellationRequested();
                    transaction.Commit();
                }
            }
        }

        public Task<IReadOnlyList<User>> GetAllAsync(CancellationToken cancellationToken = default(CancellationToken))
        {
            return QueryAsync("SELECT [Name], [Login], [Age] FROM dbo.[User] ORDER BY [Login];",
                new SqlParameter[0], cancellationToken);
        }

        public async Task<User> GetByLoginAsync(string login, CancellationToken cancellationToken = default(CancellationToken))
        {
            var users = await QueryAsync("SELECT [Name], [Login], [Age] FROM dbo.[User] WHERE [Login] = @login;",
                new[] { TextParameter("@login", ValidateText(login, nameof(login))) }, cancellationToken).ConfigureAwait(false);
            return users.SingleOrDefault();
        }

        public Task<IReadOnlyList<User>> GetByLoginsAsync(IEnumerable<string> logins, CancellationToken cancellationToken = default(CancellationToken))
        {
            if (logins == null)
                throw new ArgumentNullException(nameof(logins));
            cancellationToken.ThrowIfCancellationRequested();

            // Bound the query below SQL Server's 2100-parameter limit.
            var values = logins.Select(login => ValidateText(login, nameof(logins)))
                .Distinct(StringComparer.Ordinal).Take(MaxLoginCount + 1).ToArray();
            if (values.Length > MaxLoginCount)
                throw new ArgumentException("Supply at most 2000 distinct logins per query.", nameof(logins));
            if (values.Length == 0)
                return Task.FromResult<IReadOnlyList<User>>(new List<User>().AsReadOnly());

            var parameters = values.Select((login, index) => TextParameter("@login" + index, login)).ToArray();
            var sql = "SELECT [Name], [Login], [Age] FROM dbo.[User] WHERE [Login] IN (" +
                string.Join(", ", parameters.Select(parameter => parameter.ParameterName)) + ") ORDER BY [Login];";
            return QueryAsync(sql, parameters, cancellationToken);
        }

        public async Task CreateAsync(User user, CancellationToken cancellationToken = default(CancellationToken))
        {
            var parameters = UserParameters(user);
            try
            {
                await ExecuteAsync("INSERT INTO dbo.[User] ([Name], [Login], [Age]) VALUES (@name, @login, @age);",
                    parameters, cancellationToken).ConfigureAwait(false);
            }
            catch (SqlException exception) when (exception.Number == 2601 || exception.Number == 2627)
            {
                throw new DuplicateLoginException((string)parameters[1].Value, exception);
            }
        }

        public async Task<bool> UpdateAsync(User user, CancellationToken cancellationToken = default(CancellationToken))
        {
            return await ExecuteAsync("UPDATE dbo.[User] SET [Name] = @name, [Age] = @age WHERE [Login] = @login;",
                UserParameters(user), cancellationToken).ConfigureAwait(false) > 0;
        }

        public async Task<bool> DeleteAsync(string login, CancellationToken cancellationToken = default(CancellationToken))
        {
            return await ExecuteAsync("DELETE FROM dbo.[User] WHERE [Login] = @login;",
                new[] { TextParameter("@login", ValidateText(login, nameof(login))) }, cancellationToken).ConfigureAwait(false) > 0;
        }

        private async Task<IReadOnlyList<User>> QueryAsync(string sql, SqlParameter[] parameters, CancellationToken cancellationToken)
        {
            var users = new List<User>();
            using (var connection = new SqlConnection(connectionString))
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.AddRange(parameters);
                await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
                using (var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false))
                {
                    while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
                        users.Add(new User { Name = reader.GetString(0), Login = reader.GetString(1), Age = reader.GetInt32(2) });
                }
            }
            return users.AsReadOnly();
        }

        private async Task<int> ExecuteAsync(string sql, SqlParameter[] parameters, CancellationToken cancellationToken)
        {
            using (var connection = new SqlConnection(connectionString))
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.AddRange(parameters);
                await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
                return await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
            }
        }

        private static SqlParameter[] UserParameters(User user)
        {
            if (user == null)
                throw new ArgumentNullException(nameof(user));
            if (user.Age < 0)
                throw new ArgumentOutOfRangeException(nameof(user), "Age cannot be negative.");
            return new[]
            {
                TextParameter("@name", ValidateText(user.Name, nameof(user.Name))),
                TextParameter("@login", ValidateText(user.Login, nameof(user.Login))),
                new SqlParameter("@age", SqlDbType.Int) { Value = user.Age }
            };
        }

        private static string ValidateText(string value, string parameterName)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException("A non-empty value is required.", parameterName);
            value = value.Trim();
            if (value.Length > MaxTextLength)
                throw new ArgumentException("The value cannot exceed 100 characters.", parameterName);
            return value;
        }

        private static SqlParameter TextParameter(string name, string value)
        {
            return new SqlParameter(name, SqlDbType.NVarChar, MaxTextLength) { Value = value };
        }
    }
}
