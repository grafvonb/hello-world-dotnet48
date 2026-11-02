# Data Model: Parallel User Service

## Existing User and table

Reuse the existing public User type unchanged. No new persisted entity or relationship is added.

| Field | EF/store mapping | Existing constraint |
|---|---|---|
| Name | Required Unicode string, maximum 100; dbo.User.Name | Nonblank after trimming; duplicates allowed. |
| Login | Required Unicode string, maximum 100; dbo.User.Login; non-generated primary key | Trimmed, nonblank, immutable; case-insensitive/accent-sensitive identity. |
| Age | Required int; dbo.User.Age | Zero or greater. |

Explicitly map dbo.User; do not infer a Users table, identity column, rowversion, or EF history
table. Preserve the existing SQL collation and embedded check constraints. EF mapping is not a
replacement for those database constraints; only explicit setup repairs them.

## Input and result invariants

- User inputs are checked before database work in the same order as SqlUserService. Null user,
  blank/overlength strings and negative age retain their existing argument-exception categories.
- Trim Name/Login into an operation-owned snapshot; never change the caller's User object.
- Single-login retrieval returns the stored values or null. Multiple-login retrieval returns
  each matching stored row once, ordered by Login; empty input returns an empty read-only list.
- Normalize each input with the original trim/length rules. Distinct counting uses ordinal
  string equality, matching the original; database matching still uses the SQL collation.
- Permit at most 2,000 distinct trimmed inputs; reject 2,001 before querying. Preserve the
  original null-input / cancellation / element-validation ordering.
- Materialize read-only results using AsNoTracking. No entities or contexts remain cached in
  the service instance; later reads observe completed writes through either implementation.

## Operation-owned EF state

| Operation | Entry state and outcome |
|---|---|
| Read | Fresh context; no tracked result cache. |
| Create | Added normalized snapshot; one successful save persists one user. |
| Update | Attach snapshot; mark Name/Age modified even if unchanged; never modify Login. |
| Delete | Attach key-only stub and mark Deleted; no required Name needed for a deleted entry. |
| Missing update/delete | Zero affected row raises EF concurrency; normalize to false for that single entry. |
| Duplicate create | Normalize SQL 2601/2627 to existing DuplicateLoginException; no partial save. |
| Failure/cancellation | Preserve existing caller-visible categories; dispose context, never return empty/false as a substitute. |

There are no concurrency tokens: preserve current last-writer-wins updates. Duplicate identity
remains enforced by the existing database key. Cancellation can prevent or interrupt work but
cannot promise reversal of a write that already committed.

## Context and setup lifecycle

Construct EfUserService without creating a context or initializing EF. Validate the connection
independently and store normalized target/master connection strings and catalog name. Never
reference or instantiate SqlUserService. Normal operations
create/use/dispose their own context inside a worker async flow; native EF queries/saves take
the operation token. UserDbConfiguration is applied once before first context use, and disables
the initializer. No implicit setup, migrations or history tables.

Explicit setup uses EF-owned master/target contexts, EF database commands and a transaction
with the shared schema lock. Both services apply the unchanged embedded schema definition.
No context is shared between operations. A pre-canceled or failed operation never justifies dropping/recreating storage.

## Implementation selection

UserServiceImplementation is an application setting, not stored user data:

| Input | Selection |
|---|---|
| Missing, empty or whitespace | Sql |
| Sql, any case with surrounding whitespace | Original SqlUserService |
| EntityFramework, any case with surrounding whitespace | EfUserService |
| Other nonblank value | Argument/configuration error; no silent fallback |

The connection remains UserDatabase for both. Selection does not initialize storage, change
permissions or rewrite user data. The existing MainWindow loading/empty/failed/closed state
model and read-only UI are unchanged.
