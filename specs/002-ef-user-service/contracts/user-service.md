# Contract: Two Implementations of IUserService

**Implementations**: Existing SqlUserService and new EfUserService.
**Public boundary**: Existing IUserService, User and DuplicateLoginException remain unchanged.
**Shared model**: [data-model.md](../data-model.md).
**Technology boundary**: EF types do not appear in public service signatures or UI code.

## Operations and outcomes

All existing optional CancellationToken arguments remain supported.

| Operation | Required behavior |
|---|---|
| CreateOrUpdateDatabaseAsync | Explicit setup only; create missing database, apply embedded repeatable schema, preserve records/constraints and concurrent setup behavior. |
| GetAllAsync | Non-null IReadOnlyList<User>, all records ordered by Login; empty storage produces an empty collection. |
| GetByLoginAsync | Validate/trim login; SQL collation determines matching; return one stored User or null. |
| GetByLoginsAsync | Preserve normalization and ordinal distinct counting, cap 2,000, unique matched records ordered by Login; empty input yields an empty collection without storage access. |
| CreateAsync | Validate/snapshot/trim; persist one user; duplicate identity yields the existing DuplicateLoginException. |
| UpdateAsync | Validate/snapshot/trim; update Name/Age using Login key; true for an existing record even when values are unchanged, false for an absent record. |
| DeleteAsync | Validate/trim Login; true if deleted, false if absent. |

Constructors retain the original connection validation: nonblank SQL connection string, named
application catalog of 1–128 characters, no system catalog or AttachDBFilename. EfUserService
implements these checks independently and must not create a context or access storage there.

## Data ownership and setup

Both use the same dbo.User and existing collation. Keep the original SqlUserService class
implementation and schema intact. Move the unchanged DuplicateLoginException contract into its
own source file so removing SqlUserService.cs does not remove a shared public type.

EfUserService must not reference, construct or delegate to SqlUserService. Its own EF contexts
execute explicit setup: create the catalog through master outside a transaction, then acquire
the same transaction-owned schema lock and apply the embedded schema using EF database commands.
Its own constructor validates the connection. Reads and CRUD use EF independently.
Setup is not invoked by a constructor, context initializer, read, provider selection or app launch.

No implicit migrations, extra history/application tables, dropped/recreated storage, or duplicate
user copies. Database/Schema.sql is a shared schema definition, independent of either service.
No EF operation requires the original service source, class or instance.

## Parameterization and matching

Name/Login remain required nonblank Unicode strings up to 100 after trimming, Age nonnegative,
Login immutable/unique and Name nonunique. Caller objects remain unchanged.

Single equality and multiple-login queries must bind user values. Multi-login EF predicates use
balanced OR expressions retaining separately captured equality operands; do not inline constants
or use Contains that translates inputs into SQL literals. Parameter interception must verify
actual commands for 1 and 2,000 inputs; 2,001 is rejected before query execution. Matching and
ordering are database operations, never lowercase/client-culture approximations.

## Errors and cancellation

| Condition | Caller-visible outcome |
|---|---|
| Null/blank/overlength inputs; negative age; excessive lookup count | Existing ArgumentNullException / ArgumentException / ArgumentOutOfRangeException categories and validation order. |
| Duplicate insert (SQL 2601/2627) | Existing DuplicateLoginException with normalized login. |
| Missing update/delete | false; only a zero-row single-entity EF concurrency outcome maps to this. |
| SQL connection/access/schema failure | Underlying System.Data.SqlClient.SqlException remains catchable with its Number preserved. |
| Canceled work | OperationCanceledException, including derived cancellation types; never empty/false. |
| Unexpected EF/model failure | A failure; do not fabricate a not-found outcome. |

Only known wrapping of SQL/cancellation errors is normalized. Preserve underlying exception
dispatch when rethrowing; raw stack/message text need not match and is never shown in the UI.
Reject invalid inputs before starting I/O. Cancellation after a commit cannot guarantee rollback.

## State and lifetime

- Operation-owned context, disposed after completion/failure/cancellation; no shared tracking cache.
- Reads use no-tracking results and observe completed cross-provider changes on the next call.
- Update attaches a normalized snapshot, modifying Name/Age unconditionally; no Login update.
- Delete uses an attached key-only stub. No new concurrency token or pre-read is required.
- Cold EF preparation runs off the UI thread, inside the async operation boundary, followed by
  native async queries/saves. Preserve original cancellation/validation ordering and check the
  token after synchronous preparation. Empty multi-login input remains a no-context fast path.
- Public service methods never expose a context, require callers to dispose a context, or change
  MainWindow's existing await/close contract.

## Verification

The same seven-operation suite must run against each provider on owned fixtures, plus both
cross-provider write/read directions using reused service instances. Cover unchanged updates,
case variants, duplicates/races, boundaries, SQL punctuation, cancellation, failure categories,
mixed-provider repeated/concurrent setup, constraint repair, and one-table/three-column storage.
Only executed checks may be reported passed.

Compile and execute the EF sources without SqlUserService.cs or the two-provider factory.
Exercise all seven operations, duplicate handling, explicit repeatable/concurrent setup and
constraint repair against an owned fixture, with no normal service DLL available.
