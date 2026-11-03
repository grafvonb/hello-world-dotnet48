# Research: EF6 Stored-Procedure User Service

**Date**: 2026-11-02
**Status**: Design decisions resolved by repository inspection, delegated read-only research and
primary documentation. No implementation, build, package change or database execution was performed.

## 1. Preserve the two baselines and prove independence

**Decision**: Add `EfStoredProcedureUserService` and its own `StoredProcedureUserDbContext`.
Neither references `SqlUserService`, `EfUserService`, `UserDbContext` or `UserDbConfiguration`.
Retain those four source files unchanged. Shared contracts, `User`, `DuplicateLoginException`
and `Database/Schema.sql` remain shared and unchanged.

**Rationale**: Removing the other implementations and their specific helpers must leave the
third service buildable and runnable. The user's previous independence correction rules out
delegating constructor validation or explicit setup.

**Alternatives considered**: Reusing the original EF context or extracting its private helpers
would couple the new alternative to the comparison baseline. Another repository abstraction,
package or project adds no required behavior. Retain the existing exact EntityFramework 6.5.2
references and shipped System.Data.SqlClient provider assets.

## 2. One small context, no competing global configuration

**Decision**: Use a plain, operation-owned context with no DbSet, entity mapping, configuration
attribute or new DbConfiguration subclass. Its static constructor disables its own initializer
using `Database.SetInitializer<StoredProcedureUserDbContext>(null)`. Turn off proxies/lazy loading.
Create the context only inside the service's asynchronous worker boundary.

**Rationale**: EF configuration is global. Pinned EF6 source shows initializer registration
discovers the context's assembly configuration before accessing the locked resolver. In the full
library, existing configuration discovery remains valid; in an isolated third-only assembly,
the normal SQL-provider convention loads EntityFramework.SqlServer.dll. Neither older helper
is required by new source. Raw results need no mapped entity.

**Alternatives considered**: A second configuration subclass risks conflicting global discovery.
Registering configuration from every service operation or changing the existing helper is unnecessary.
A mapped DbSet would expose a direct-table path the third implementation does not need.

**Verification gate**: Fresh full-library processes must test third-first and original-EF-first
use, followed by the other EF service. A separate third-only executable must omit all older
implementation/helper sources and the normal service DLL, discover the provider without manual
configuration and exercise all seven operations. These are planned checks, not claimed results.

Sources: pinned [initializer registration](https://raw.githubusercontent.com/dotnet/ef6/v6.5.2/src/EntityFramework/Database.cs),
[configuration manager](https://raw.githubusercontent.com/dotnet/ef6/v6.5.2/src/EntityFramework/Infrastructure/DependencyResolution/DbConfigurationManager.cs),
[configuration finder](https://raw.githubusercontent.com/dotnet/ef6/v6.5.2/src/EntityFramework/Infrastructure/DependencyResolution/DbConfigurationFinder.cs),
[provider discovery](https://raw.githubusercontent.com/dotnet/ef6/v6.5.2/src/EntityFramework/Infrastructure/DependencyResolution/AppConfigDependencyResolver.cs),
[unmapped result materialization](https://raw.githubusercontent.com/dotnet/ef6/v6.5.2/src/EntityFramework/Core/Objects/ObjectContext.cs).

## 3. EF calls procedures without direct-table fallback

**Decision**: Use six fixed, schema-qualified, parameterized EXEC templates. Reads materialize
`Database.SqlQuery<User>(...).ToListAsync(token)`. Create invokes
`Database.ExecuteSqlCommandAsync(..., token, parameters)` and ignores its row-count return.
Update/delete materialize one integer result through `Database.SqlQuery<int>`.
No SaveChanges, mapped entity writes, LINQ-to-Entities user query or direct provider execution.

**Rationale**: EF raw-query results are untracked; retained service objects see subsequent
committed changes. A command whose text is a fixed EXEC invocation is a procedure call even
when CommandType is Text. It need not use CommandType.StoredProcedure to meet the requirement.

**Alternatives considered**: EF insert/update/delete mapping alone does not cover retrieval.
Calling SqlCommand directly would bypass the requested EF execution path. Requiring the provider
command type to be StoredProcedure would reject EF's documented raw-query route.

Sources: [EF6 raw queries](https://learn.microsoft.com/en-us/ef/ef6/querying/raw-sql),
[async commands](https://learn.microsoft.com/en-us/dotnet/api/system.data.entity.database.executesqlcommandasync?view=entity-framework-6.2.0),
[async materialization](https://learn.microsoft.com/en-us/dotnet/api/system.data.entity.infrastructure.dbrawsqlquery-1.tolistasync?view=entity-framework-6.2.0),
[provider command construction](https://raw.githubusercontent.com/dotnet/ef6/v6.5.2/src/EntityFramework/Core/Objects/ObjectContext.cs).

## 4. One Unicode table-valued input for multi-login lookup

**Decision**: Transport normalized logins in one Structured SqlParameter named `@Logins`,
`TypeName = "dbo.UserLoginList"`, backed by a one-column DataTable. The SQL type has Login
nvarchar(100), NOT NULL, Latin1_General_100_CI_AS, and no primary/unique key. The procedure uses
EXISTS against the input and orders stored users by Login.

**Rationale**: C# preserves ordinal distinct counting and the 2,000 limit, while SQL preserves
case-insensitive/accent-sensitive identity. Case variants must not collide inside the TVP or
duplicate returned users. Matching the type's column collation avoids database-default conflicts.

**Alternatives considered**: One parameter per login complicates a fixed procedure signature.
Delimited strings require escaping/parsing; JSON raises compatibility considerations. A TVP
needs no extra package or persistent user-data table. A TVP uniqueness constraint would reject
valid ordinal-distinct case variants. Do not use AddWithValue.

Sources: [TVP transport](https://learn.microsoft.com/en-us/dotnet/framework/data/adonet/sql/table-valued-parameters),
[System.Data.SqlClient TypeName](https://learn.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlparameter.typename?view=netframework-4.8.1),
[TVP permissions and READONLY](https://learn.microsoft.com/en-us/sql/relational-databases/tables/use-table-valued-parameters-database-engine),
[collation precedence](https://learn.microsoft.com/en-us/sql/t-sql/statements/collation-precedence-transact-sql),
[table-type metadata](https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-table-types-transact-sql).

## 5. Explicit write results and preserved errors

**Decision**: Procedures set NOCOUNT ON. Update assigns Name/Age for the matching Login even
when unchanged; update/delete immediately return one int @@ROWCOUNT result. Only 0/1 are valid;
missing/extra/invalid result rows fail rather than become false. Keep inputs snapshotted and
validated before context creation. Preserve SQL 2601/2627 as DuplicateLoginException for insert;
unwrap known EF SQL/cancellation wrappers without changing error numbers.

**Rationale**: An ExecuteNonQuery row count can be -1 under NOCOUNT and is unsuitable for
the existing bool contract. An unchanged row still qualifies for an unconditional update.
A malformed procedure result is not evidence of an absent user.

**Alternatives considered**: Output parameters work but require completed reader consumption.
An existence pre-read adds a race. Rebuilding SQL errors from message text loses provider identity.

Sources: [NOCOUNT](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-nocount-transact-sql),
[@@ROWCOUNT](https://learn.microsoft.com/en-us/sql/t-sql/functions/rowcount-transact-sql),
[ExecuteNonQuery counts](https://learn.microsoft.com/en-us/dotnet/api/system.data.sqlclient.sqlcommand.executenonquery?view=netframework-4.8.1),
[THROW](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/throw-transact-sql).

## 6. Independent bootstrap without changing the baselines

**Decision**: The third service independently validates target/master connections. Its own EF
master context creates an absent catalog outside a transaction, binds the DB_ID value, escapes
the validated identifier and handles only the existing 1801 creation-race exception. Its target
context opens asynchronously, begins a transaction, obtains the same exclusive transaction-owned
`UserDatabaseService.Schema` lock, applies shared Schema.sql, then applies its own resources:
one Bootstrap.sql plus six separate ALTER PROCEDURE batches. Commit only after a cancellation check.

Bootstrap conditionally creates the TVP and fixed-name procedure stubs. All dynamic DDL is fixed
trusted setup text, never user-data interpolation. ALTER installs/updates the real definitions
without dropping objects or procedure grants. Verify an existing type matches the defined
column contract; incompatible types fail explicitly rather than being dropped/recreated.
Normal reads/writes never invoke setup.

Repository inspection confirms shared Schema.sql repairs missing named check constraints, not
a removed primary key or disabled constraints. The spec assumptions now make that existing
compatibility boundary explicit; this feature does not broaden schema-repair behavior.

**Rationale**: Procedure DDL has batch restrictions. Separate resources avoid a GO parser.
The create-stub/ALTER pattern avoids imposing the newer CREATE OR ALTER syntax requirement.
The chosen syntax stays within the existing schema's effective SQL Server 2012+ baseline.

**Alternatives considered**: A single unprocessed GO script cannot execute as an EF command.
Drop/recreate loses grants and dependencies. CREATE OR ALTER would require SQL Server 2016 SP1+.
Another setup service or a call into either old implementation violates independence.

Sources: [CREATE DATABASE transactions](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-transact-sql),
[application lock scope](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-getapplock-transact-sql),
[procedure batches and version limits](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-procedure-transact-sql),
[ALTER preservation](https://learn.microsoft.com/en-us/sql/t-sql/statements/alter-procedure-transact-sql),
[GO utility command](https://learn.microsoft.com/en-us/sql/t-sql/language-elements/sql-server-utilities-statements-go),
[type creation](https://learn.microsoft.com/en-us/sql/t-sql/statements/create-type-transact-sql).

## 7. Reuse the existing comparison entry points

**Decision**: Name the new choice `EntityFrameworkStoredProcedures`. Keep Sql, EntityFramework,
and Both meanings in service/window scripts; add the third choice and All. Both remains the
old pair; All exercises all three. Extend the existing EF-independence script with EF/third/Both
selection, defaulting to its original EF behavior. Add SQL 2812 alongside 208 in safe storage
feedback. Preserve the user's App.config EntityFramework selection.

**Rationale**: Configuration and testing already provide the required extension points.
The stored-procedure read-all call needs exact invocation observation; the current "[User]"
substring probe cannot identify it. A third-service setup would warm its own EF runtime, so
cold window checks must provision in a separate process before fresh UI hosts.

**Verification**: Keep original assertions, add procedure interception for all six calls and
typed TVP payloads, test six directed cross-service writer/reader pairings once, and use owned
fixtures for missing procedures, explicit repair and denied execution. Preserve inherited
manual acceptance as unexecuted unless actually performed.

Repository evidence: scripts/Test-UserDatabaseService.ps1, scripts/Test-MainWindow.ps1,
scripts/Test-EfIndependence.ps1 and HelloWorldWpf48/MainWindow.xaml.cs. No additional test framework,
public phase flag, provider retry policy, benchmark or user-facing implementation picker is needed.
