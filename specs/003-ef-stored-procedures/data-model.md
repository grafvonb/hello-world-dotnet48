# Data Model: Stored-Procedure Alternative

## Existing User

Reuse the public User and existing dbo.User without annotations or field changes.

| Field | Stored form | Rules |
|---|---|---|
| Name | nvarchar(100), required | Nonblank after trim; duplicates allowed. |
| Login | nvarchar(100), required, primary key | Trimmed, immutable; Latin1_General_100_CI_AS identity. |
| Age | int, required | Zero or greater. |

Return stored values and spelling. Single lookup returns null when absent; collection reads
return read-only results ordered by stored Login. No relationships, additional persisted entity,
tracking cache, concurrency token or user-copy table is introduced.

## Operation Inputs

- Independently validate connection settings using the established nonblank/named application
  catalog, 1–128-character name, non-system catalog and no AttachDBFilename rules.
- Preserve original input-validation ordering: null user, negative age, Name, Login; single-login
  validation before I/O; multiple-login null check, cancellation, then enumeration/validation.
- Trim text, reject values longer than 100, and snapshot writes without mutating caller objects.
- Multi-login input is trimmed and distinct with StringComparer.Ordinal, bounded at 2,001
  while enumerating; reject over 2,000 before context creation. Empty input returns immediately.
- Parameters are NVarChar(100), Int, or the one structured parameter below. User values never
  form SQL command text. Transport construction/lifetime belongs to the operation.

## Login-List Transport

`dbo.UserLoginList` is a schema-only table type used by `@Logins`, not a persisted application table.

| Column | Type | Constraints |
|---|---|---|
| Login | nvarchar(100) COLLATE Latin1_General_100_CI_AS | NOT NULL; no primary/unique constraint. |

The client payload has one string column with the same name/length/nullability. Case variants
survive ordinal input counting. The procedure uses EXISTS so those variants can identify a
single stored user without returning duplicates. The type is READONLY at the procedure boundary.
An existing incompatible type is an explicit setup failure, never a reason to drop data/types.

## Results and State Transitions

| Operation | Result/state |
|---|---|
| GetAll | Ordered User rows, possibly empty. |
| GetByLogin | Zero/one User row; multiple rows indicate broken storage/contract and fail. |
| GetByLogins | Ordered unique matched User rows; unmatched inputs omitted. |
| Create | One new row, or existing duplicate-login/error category. |
| Update | Name/Age only; one integer row, 1 when matched even if unchanged, 0 when absent. |
| Delete | One integer row, 1 when deleted, 0 when absent. |

Update/delete results must contain exactly one integer 0/1. Other shapes fail. SQL/cancellation
failures are never normalized to empty/false. Committed changes are visible to every other
implementation on the next read; cancellation after commit does not guarantee rollback.

## Setup and Context Lifetime

A service constructor stores validated strings only. Each normal operation owns a new
StoredProcedureUserDbContext inside an asynchronous worker flow. The context is empty/unmapped,
has no shared tracking state and disables its own initializer before use.

Explicit setup state is: catalog absent → catalog present → transaction/lock acquired →
shared user schema applied → type/stubs validated/installed → six procedure definitions
installed → commit. Existing prepared sources may enter at any step; reruns preserve users.
The schema/type/procedure phase rolls back on failure/cancellation before commit. Catalog
creation is separately committed and is never compensated by deleting a database.

Normal operations require prepared assets but never transition setup state. Stored procedures
are runtime dependencies installed only by explicit third-service setup. See
[procedure contract](contracts/stored-procedures.md) for names, results and deployment rules.
