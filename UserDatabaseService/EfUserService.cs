using System;
using System.Collections.Generic;
using System.Data;
using System.Data.Entity;
using System.Data.Entity.Core;
using System.Data.Entity.Infrastructure;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Linq.Expressions;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Threading.Tasks;

namespace UserDatabaseService
{
    public sealed class EfUserService : IUserService
    {
        private readonly string connectionString;
        private readonly string masterConnectionString;
        private readonly string databaseName;

        public EfUserService(string connectionString)
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
            // CREATE DATABASE cannot run in a transaction. EF owns this master context too.
            try
            {
                await ExecuteAsync(masterConnectionString, context =>
                {
                    context.Database.CommandTimeout = 60;
                    return context.Database.ExecuteSqlCommandAsync(TransactionalBehavior.DoNotEnsureTransaction,
                        "IF DB_ID(@databaseName) IS NULL CREATE DATABASE [" + databaseName.Replace("]", "]]") + "];",
                        cancellationToken, new SqlParameter("@databaseName", SqlDbType.NVarChar, 128) { Value = databaseName });
                }, cancellationToken).ConfigureAwait(false);
            }
            catch (SqlException exception) when (exception.Number == 1801)
            {
                // A concurrent initializer created the catalog first.
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

                    string schema;
                    using (var stream = typeof(EfUserService).Assembly.GetManifestResourceStream("UserDatabaseService.Database.Schema.sql"))
                    {
                        if (stream == null)
                            throw new InvalidOperationException("The embedded database schema is missing.");
                        using (var reader = new StreamReader(stream))
                            schema = reader.ReadToEnd();
                    }
                    await context.Database.ExecuteSqlCommandAsync(TransactionalBehavior.DoNotEnsureTransaction,
                        schema, cancellationToken).ConfigureAwait(false);
                    cancellationToken.ThrowIfCancellationRequested();
                    transaction.Commit();
                    return 0;
                }
            }, cancellationToken).ConfigureAwait(false);
        }

        public Task<IReadOnlyList<User>> GetAllAsync(CancellationToken cancellationToken = default(CancellationToken))
        {
            return ExecuteAsync<IReadOnlyList<User>>(async context =>
                (await context.Users.AsNoTracking().OrderBy(user => user.Login)
                    .ToListAsync(cancellationToken).ConfigureAwait(false)).AsReadOnly(), cancellationToken);
        }

        public Task<User> GetByLoginAsync(string login, CancellationToken cancellationToken = default(CancellationToken))
        {
            var key = ValidateText(login, nameof(login));
            return ExecuteAsync(context => context.Users.AsNoTracking()
                .SingleOrDefaultAsync(user => user.Login == key, cancellationToken), cancellationToken);
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

            var predicate = LoginPredicate(values);
            return ExecuteAsync<IReadOnlyList<User>>(async context =>
                (await context.Users.AsNoTracking().Where(predicate).OrderBy(user => user.Login)
                    .ToListAsync(cancellationToken).ConfigureAwait(false)).AsReadOnly(), cancellationToken);
        }

        public async Task CreateAsync(User user, CancellationToken cancellationToken = default(CancellationToken))
        {
            var snapshot = Snapshot(user);
            try
            {
                await ExecuteAsync(async context =>
                {
                    context.Users.Add(snapshot);
                    return await context.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
                }, cancellationToken).ConfigureAwait(false);
            }
            catch (SqlException exception) when (exception.Number == 2601 || exception.Number == 2627)
            {
                throw new DuplicateLoginException(snapshot.Login, exception);
            }
        }

        public Task<bool> UpdateAsync(User user, CancellationToken cancellationToken = default(CancellationToken))
        {
            var snapshot = Snapshot(user);
            return ExecuteAsync(async context =>
            {
                context.Users.Attach(snapshot);
                context.Entry(snapshot).Property(value => value.Name).IsModified = true;
                context.Entry(snapshot).Property(value => value.Age).IsModified = true;
                return await SaveExistingAsync(context, cancellationToken).ConfigureAwait(false);
            }, cancellationToken);
        }

        public Task<bool> DeleteAsync(string login, CancellationToken cancellationToken = default(CancellationToken))
        {
            var snapshot = new User { Login = ValidateText(login, nameof(login)) };
            return ExecuteAsync(async context =>
            {
                context.Users.Attach(snapshot);
                context.Users.Remove(snapshot);
                return await SaveExistingAsync(context, cancellationToken).ConfigureAwait(false);
            }, cancellationToken);
        }

        private static async Task<bool> SaveExistingAsync(UserDbContext context, CancellationToken cancellationToken)
        {
            try
            {
                await context.SaveChangesAsync(cancellationToken).ConfigureAwait(false);
                return true;
            }
            catch (DbUpdateConcurrencyException)
            {
                // Only one entry, no concurrency tokens: zero affected rows means absent.
                return false;
            }
        }

        private Task<T> ExecuteAsync<T>(Func<UserDbContext, Task<T>> operation, CancellationToken cancellationToken)
        {
            return ExecuteAsync(connectionString, operation, cancellationToken);
        }

        private static Task<T> ExecuteAsync<T>(string operationConnectionString,
            Func<UserDbContext, Task<T>> operation, CancellationToken cancellationToken)
        {
            // EF6 cold model/provider preparation is synchronous. Keep it off the UI thread;
            // the context stays on this worker flow and database I/O still uses native async APIs.
            return Task.Run(async () =>
            {
                try
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    using (var context = new UserDbContext(operationConnectionString))
                    {
                        context.Database.Initialize(false);
                        cancellationToken.ThrowIfCancellationRequested();
                        return await operation(context).ConfigureAwait(false);
                    }
                }
                catch (Exception exception)
                {
                    if (exception is EntityException || exception is DbUpdateException ||
                        exception is SqlException || exception is OperationCanceledException)
                    {
                        for (var cause = exception; cause != null; cause = cause.InnerException)
                            if (cause is SqlException || cause is OperationCanceledException)
                                ExceptionDispatchInfo.Capture(cause).Throw();
                    }
                    throw;
                }
            }, cancellationToken);
        }

        private static User Snapshot(User user)
        {
            if (user == null)
                throw new ArgumentNullException(nameof(user));
            if (user.Age < 0)
                throw new ArgumentOutOfRangeException(nameof(user), "Age cannot be negative.");
            return new User
            {
                Name = ValidateText(user.Name, nameof(user.Name)),
                Login = ValidateText(user.Login, nameof(user.Login)),
                Age = user.Age
            };
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

        private static Expression<Func<User, bool>> LoginPredicate(string[] values)
        {
            var parameter = Expression.Parameter(typeof(User), "user");
            var terms = new Expression[values.Length];
            for (int i = 0; i < values.Length; i++)
            {
                var captured = values[i];
                Expression<Func<User, bool>> leaf = user => user.Login == captured;
                terms[i] = new ReplaceParameter(leaf.Parameters[0], parameter).Visit(leaf.Body);
            }
            return Expression.Lambda<Func<User, bool>>(Combine(terms, 0, terms.Length), parameter);
        }

        private static Expression Combine(Expression[] terms, int start, int length)
        {
            if (length == 1)
                return terms[start];
            int left = length / 2;
            return Expression.OrElse(Combine(terms, start, left), Combine(terms, start + left, length - left));
        }

        private sealed class ReplaceParameter : ExpressionVisitor
        {
            private readonly ParameterExpression source;
            private readonly ParameterExpression target;

            public ReplaceParameter(ParameterExpression source, ParameterExpression target)
            {
                this.source = source;
                this.target = target;
            }

            protected override Expression VisitParameter(ParameterExpression node)
            {
                return node == source ? target : base.VisitParameter(node);
            }
        }
    }
}
