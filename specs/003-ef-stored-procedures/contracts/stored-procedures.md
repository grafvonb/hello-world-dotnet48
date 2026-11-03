# Contract: Stored Procedures and Explicit Installation

## Fixed Runtime Invocations

New service: `EfStoredProcedureUserService`. Own context: `StoredProcedureUserDbContext`.

| Operation | Exact invocation text | Inputs | Result |
|---|---|---|---|
| GetAll | `EXEC dbo.User_GetAll;` | None | Name, Login, Age rows, ordered by Login. |
| GetByLogin | `EXEC dbo.User_GetByLogin @Login = @Login;` | Login | Zero/one User row. |
| GetByLogins | `EXEC dbo.User_GetByLogins @Logins = @Logins;` | Logins | Unique matched User rows, ordered by Login. |
| Create | `EXEC dbo.User_Create @Name = @Name, @Login = @Login, @Age = @Age;` | Name, Login, Age | No result required; successful completion means created. |
| Update | `EXEC dbo.User_Update @Name = @Name, @Login = @Login, @Age = @Age;` | Name, Login, Age | Exactly one int row: 0 or 1. |
| Delete | `EXEC dbo.User_Delete @Login = @Login;` | Login | Exactly one int row: 0 or 1. |

Scalar inputs use System.Data.SqlClient.SqlParameter: text NVarChar(100), age Int.
Logins uses SqlDbType.Structured, TypeName dbo.UserLoginList and a one-column string DataTable.
Bind values; never interpolate/concatenate them into invocation text.

EF reads use Database.SqlQuery<User> and ToListAsync(token), never DbSet.SqlQuery.
Create uses ExecuteSqlCommandAsync with the cancellation overload and ignores the returned count.
Update/delete use Database.SqlQuery<int> and asynchronous full materialization, then validate
cardinality and value. SqlQuery on Database does not track results.

All procedure bodies use SET NOCOUNT ON and explicit columns. Scalar lookup matches Login by
the existing column collation. Multi-login matches with EXISTS over the READONLY TVP, ensuring
case variants do not duplicate returned users. Do not build dynamic user-data SQL.
Update changes only Name/Age, with no value-difference predicate; update/delete immediately
return int @@ROWCOUNT as AffectedRows. A routine-level catch must not replace provider errors.

## Type Contract

`dbo.UserLoginList`: exactly one Login column, nvarchar(100), NOT NULL,
COLLATE Latin1_General_100_CI_AS, without a primary key or unique constraint.
Retain the client-side 2,000 ordinal-distinct bound. Type declaration order is stable.
Only the schema definition persists; this is not another user table.

## Installation Contract

Explicit CreateOrUpdateDatabaseAsync owns the entire workflow without either earlier service:

1. Independently validate and normalize the target/master connection settings; preserve the
   existing system-catalog and AttachDBFilename rejection rules without opening a connection.
2. On its own EF master context, create an absent database using DoNotEnsureTransaction.
   DB_ID receives a bound Unicode catalog parameter; the validated catalog identifier is
   bracket-escaped. Only SQL1801 from a creation race is specially tolerated.
3. On its own target context, open asynchronously and begin an EF transaction. Acquire the
   exclusive, transaction-owned `UserDatabaseService.Schema` application lock with the same
   30-second lock timeout as the old services; use a 60-second setup command timeout.
4. Execute the unchanged shared Schema.sql; then the new embedded resources in this exact order:

   | Resource under Database/StoredProcedures | Purpose |
   |---|---|
   | Bootstrap.sql | Conditionally create/validate UserLoginList and create absent fixed-name procedure stubs. |
   | GetAll.sql | ALTER dbo.User_GetAll. |
   | GetByLogin.sql | ALTER dbo.User_GetByLogin. |
   | GetByLogins.sql | ALTER dbo.User_GetByLogins. |
   | Create.sql | ALTER dbo.User_Create. |
   | Update.sql | ALTER dbo.User_Update. |
   | Delete.sql | ALTER dbo.User_Delete. |

5. Check cancellation before committing. Roll back the target transaction on failure; never
   compensate by deleting a catalog. Catalog creation is a separate autocommit operation.

Each ALTER resource is one complete batch, without GO. Bootstrap uses only fixed trusted DDL
strings for conditional type/stub creation. No generic SQL parser or CREATE OR ALTER requirement.
Use explicit embedded resource names under UserDatabaseService.Database.StoredProcedures.
An incompatible existing type fails explicitly, with no drop/recreate or silent coercion.
Missing/stale procedure definitions are repaired on explicit setup; ALTER preserves grants.
Original setup can still run before/after/concurrently and leaves added type/procedures intact.
Schema compatibility and check-repair scope follow the specification assumptions: supported
table layout/key, plus missing named check constraints handled by shared Schema.sql. Do not add
a general schema-repair/migration system or claim a removed primary key/disabled check is repaired.

Constructors, configuration selection, reads, writes and window loading never install assets.
Normal missing-procedure failures propagate directly; they do not become automatic setup or
inline-query fallback. Setup DDL/provider metadata are outside the six user-data invocations.

## EF Configuration and Deployment

The new context has no sets, mappings or configuration attribute/subclass. Its static constructor
disables its own initializer. No reference to the old context/configuration is compiled.
The full library retains its existing global discovery; an isolated build uses standard EF6
SQL-provider discovery. Both EF runtime DLLs must be beside every production/test executable.

Verify third-first and original-EF-first order in fresh full-library hosts, and all seven
operations in a separate executable omitting both older implementations/helpers and the factory.
Do not make these checks pass by manually registering the old configuration in the new path.

## Permissions and Observation

Explicit setup needs existing catalog-create/schema rights plus type/procedure create/alter
rights. Runtime uses EXECUTE on the six procedures and EXECUTE/REFERENCES on dbo.UserLoginList.
Document grants for the selected identity; production setup does not create principals or
grant/revoke permissions automatically.

A scoped EF interceptor captures readers, nonqueries and scalars. For the six operations,
require the exact invocation table and expected parameters/async calls. CommandType.Text with
the defined EXEC text is valid; a loose "contains EXEC" check is not. Require observations for
each exercised operation so bypassing EF interception cannot pass.
Inventory any cold provider metadata separately using exact known templates; no blanket SELECT,
sys.* or "no [User] substring" exemption. Setup/fixture maintenance is outside the runtime guard.

Inspect installed definitions and type metadata as well as the client calls. Exercise 1/2,000
TVP rows containing matched Unicode/punctuation inputs, ordinal-distinct case variants and
trimmed duplicates. Reject 2,001 before any connection/command, including on unprepared storage.
Drop each procedure only in owned fixtures: assert SQL2812/no repair, then explicit setup/recovery.
Verify real SQL229 using only a fixture-owned disposable principal/impersonation scope; restore
that scope and clean it up without changing normal account/server-login permissions.
