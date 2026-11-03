# Contract: Independent Third IUserService Implementation

## Public Boundary and Independence

`EfStoredProcedureUserService` implements the existing IUserService with the existing User,
DuplicateLoginException and optional CancellationToken signatures. No EF type appears in that API.

No new source may reference, construct or delegate to SqlUserService, EfUserService,
UserDbContext or UserDbConfiguration. No shared-helper extraction from those files.
Shared public contracts/model, Schema.sql and framework/package dependencies are allowed.

The independent executable includes only the new service/context, its procedure resources,
IUserService, User, DuplicateLoginException and shared Schema.sql. It excludes the factory and
the normal service DLL as well as both earlier implementations and their helpers.
It must exercise all seven methods with normal provider discovery and no manual EF configuration.

## Operations

| Method | Required behavior |
|---|---|
| CreateOrUpdateDatabaseAsync | Independently create missing catalog and install/update shared schema, type and procedures; repeatable, concurrent, non-destructive and explicit. |
| GetAllAsync | Read-only collection of User rows ordered by stored Login; empty success only for an available, prepared source with no users. |
| GetByLoginAsync | Validated/trimmed equality; one stored User or null; unexpected extra rows fail. |
| GetByLoginsAsync | Validated/trimmed ordinal-distinct values; up to 2,000; unique matches in Login order; empty fast path with no context/connection. |
| CreateAsync | Normalize a private snapshot, invoke create procedure; duplicate SQL2601/2627 becomes DuplicateLoginException with normalized login. |
| UpdateAsync | Normalize a private snapshot; update Name/Age for Login; 1 means true, 0 false, including true for unchanged existing values. |
| DeleteAsync | Validate/trim Login; 1 means true, 0 false. |

The six data operations use only the EF invocation/result contracts in
[stored-procedures.md](stored-procedures.md); setup is not part of those paths.
No direct user-table SQL, LINQ-to-Entities read, SaveChanges, direct SqlCommand execution,
fallback service, pre-write existence query or repair-on-failure.

## Validation, Lifetime and Errors

- Match [data-model.md](../data-model.md) for connection checks, field rules and validation ordering.
  Reject invalid input before context construction; never mutate supplied User objects.
- Per operation: worker boundary → own context/preparation → native async EF execution →
  materialize results → dispose. Forward cancellation to scheduling and EF I/O and check after
  synchronous preparation. No shared context or caller-owned disposal.
- Preserve direct System.Data.SqlClient.SqlException with Number for storage/access failures
  by unwrapping known EF wrappers; preserve OperationCanceledException and unexpected failures.
  Missing procedure remains SQL2812; no data/schema operation runs to hide it.
  Framework attention-only SQL0 (all errors state 0/class 11) becomes cancellation only when
  the operation's token is canceled, keeping the provider exception as the inner cause.
  Other SQL errors and uncanceled SQL0 remain failures.
- Update/delete require exactly one int result in {0,1}. Malformed results are contract failures.
  Zero is not a general error fallback. Do not use ExecuteSqlCommand's count as bool.
- Repeated calls through retained service instances observe completed writes from all three
  choices. Cancellation does not promise reversal of a write already committed.

## Required Verification

Run the original complete contract suite for the third choice and retain both baselines.
Inspect all six real EF procedure calls and actual bound parameters. Test all six directed
writer/reader pairings once, including reads primed before writes.

Verify 0/1/1,000 records; empty/missing; text/age boundaries; Unicode, case and accents;
caller-object preservation; unchanged/missing writes; duplicate races; cancellation; missing
storage/procedures; denied procedure execution; mixed setup and explicit repair.
Compile/run the third-only executable with every excluded type verified absent.
All setup/negative cases use owned fixtures; no normal data or principal permissions change.
