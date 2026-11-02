# Tasks: Parallel Entity Framework User Service

**Branch**: `002-ef-user-service`
**Inputs**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md),
[service contract](contracts/user-service.md), [selection contract](contracts/implementation-selection.md),
[research.md](research.md), [quickstart.md](quickstart.md).
**Governance**: `.specify/memory/constitution.md`, version 1.0.0.

Preserve the SqlUserService class implementation, IUserService.cs, User.cs and Database/Schema.sql.
Move the shared DuplicateLoginException into its own file unchanged. Both implementations use
the same storage. EfUserService independently implements all seven operations, connection
validation and explicit setup, with no reference or delegation to SqlUserService. Paths are
repository-relative. Write contract assertions first; `[P]` permits parallel authoring in
different files after the prerequisites below, not checks against an incomplete build.

## Phase 1: Complete Service Comparison — US1 (P1), US2 (P2)

**Acceptance**: Matching reads for 0/1/1,000 users and matching seven-operation outcomes,
including cross-provider visibility, parameterization, constraints, cancellation and failures.

- [X] T001 Bootstrap EF6 in `UserDatabaseService/UserDatabaseService.csproj` and `HelloWorldWpf48/HelloWorldWpf48.csproj`: exact EntityFramework [6.5.2], CopyLocalLockFileAssemblies=true, service System.ComponentModel.DataAnnotations reference, unchanged classic/net48/C# 7.3 targets; add/register `UserDatabaseService/UserDbContext.cs` and `UserDatabaseService/UserDbConfiguration.cs` mapping dbo.User with Name "Required Unicode string, maximum 100; dbo.User.Name" / "Nonblank after trimming; duplicates allowed.", Login "Required Unicode string, maximum 100; dbo.User.Login; non-generated primary key" / "Trimmed, nonblank, immutable; case-insensitive/accent-sensitive identity.", and Age "Required int; dbo.User.Age" / "Zero or greater."; register System.Data.SqlClient once and disable initializers, proxies and lazy loading, with no new schema/history tables or concurrency tokens.
- [X] T002 [P] [US1] Extend `scripts/Test-UserDatabaseService.ps1` once with -Implementation Sql|EntityFramework|Both (default Sql) and the shared full-contract suite: compare fields/order/lookups, empty/missing results, Unicode/case/accent/trim rules, 100/101-character and 2,000/2,001-input boundaries, unchanged caller objects, unchanged update=true, absent update/delete=false, duplicate races, validation/cancellation/SqlException outcomes, two-way fresh reads using reused service instances, and repeatable/concurrent mixed-provider setup with constraint repair; establish provider configuration before test interception and prove Unicode-bound parameters for 1/2,000 inputs and punctuation, reject 2,001 before querying, report each provider separately, and clean up only owned fixtures/interceptors.
- [X] T003 [US2] Implement the complete seven-method `UserDatabaseService/EfUserService.cs` and register it in `UserDatabaseService/UserDatabaseService.csproj`, following `specs/002-ef-user-service/contracts/user-service.md`: independent constructor validation and explicit EF setup without context/model initialization in the constructor, original validation order, worker-owned context and native async I/O/cancellation, no-tracking ordered reads, empty-input fast path, ordinal distinct counting and balanced OR predicates retaining captured parameters; snapshot writes, force only Name/Age modified for updates, use key-only deletes, map zero-row concurrency to false and insert 2601/2627 to DuplicateLoginException, preserve underlying SQL/cancellation dispatch, and never normalize real failures to empty/false or initialize storage implicitly.

The EF implementation is one complete file-level increment: no temporary unsupported methods,
read-only release stage, or extra test-phase flag. T003 implements reads and writes for both
stories; T002 verifies both. Their primary labels identify ownership rather than independent
deployment boundaries.

## Phase 2: Application Selection — US3 (P2)

**Acceptance**: Default Sql and explicit EntityFramework really select the intended implementation;
unknown values show safe configuration feedback, and both preserve current window behavior.

- [X] T004 [P] [US3] Extend `scripts/Test-MainWindow.ps1` real-source mode with -Implementation Sql|EntityFramework|Both (default Sql), preserving existing flags/fake checks; use copied DLL/config hosts to verify default/blank/case-trimmed/invalid selection, actual EF query execution, populated/empty/error/Retry states, cancellation/closure and unchanged data; prepare fixtures through SqlUserService so the first EF window query is cold, and assert responsive Dispatcher/close behavior during initialization.
- [X] T005 [US3] Add/register `UserDatabaseService/UserServiceFactory.cs` in `UserDatabaseService/UserDatabaseService.csproj` and wire `HelloWorldWpf48/MainWindow.xaml.cs` plus `HelloWorldWpf48/App.config` per the selection contract: missing/blank defaults to Sql, trimmed case-insensitive Sql/EntityFramework selects the matching service, other text fails as configuration; retain UserDatabase, direct service construction, lazy loading and the existing UI state/error/Retry/close flow without a new picker or eager model/storage access.

## Phase 3: Documentation and Verification

- [X] T006 [P] Update `README.md` and `specs/002-ef-user-service/quickstart.md` for package restore, full seven-operation comparison, independent setup using the shared schema definition, selection/defaults and service/window/interactive commands; remove obsolete no-package claims and avoid unsupported performance claims.
- [X] T007 Restore/build `HelloWorldWpf48.sln` using Visual Studio MSBuild Debug/Any CPU, verify both EF DLLs in service/app outputs, run `scripts/Test-UserDatabaseService.ps1` with -Implementation Both, and run the fake plus real-source Both modes of `scripts/Test-MainWindow.ps1`; fix failures and record actual parity/interception/race/schema/cold-start/deployment/timing/cleanup results in `specs/002-ef-user-service/quickstart.md`, including the inherited one-second UI targets and unchanged original service class/public types/schema.
- [ ] T008 Execute and record keyboard/readability/resize/scroll/pending move-close checks and an EF-configured window inspection from `specs/002-ef-user-service/quickstart.md`; keep this task outstanding with the exact reason if desktop control is unavailable, and retain the earlier unexecuted manual check as unexecuted.

- [X] T009 Remove all EF dependencies on SqlUserService, independently validate connections and
  implement explicit setup with EF contexts/commands/transactions and the shared schema lock;
  relocate DuplicateLoginException unchanged, preserving the entire SqlUserService class body;
  add/run scripts/Test-EfIndependence.ps1 compiling only EF/shared sources, execute all seven
  operations without the SQL implementation or baseline DLL, rerun parity/window checks, and
  correct specification/design/usage evidence to require full independence.

## Dependencies and Parallel Work

```text
T001 -> (T002 + T003) -> (T004 + T005) -> T007 -> T008
T006 documentation -------------------> T007
```

- T002/T003 follow T001 and may overlap after assertions are defined; their files differ.
- T004/T005 follow the complete service and may overlap after assertions are defined.
- T006 may overlap implementation; finish it before T007/T008 write evidence to the same guide.
- Service-project edits in T001, T003 and T005 are sequential. Each script is extended in one
  task. Build/run once the complete implementation exists; repeat only after relevant changes.

## Coverage

| Requirements | Implementation | Verification |
|---|---|---|
| FR-001, FR-002, FR-003: retained, independent full service | T001, T003, T005, T009 | T002, T004, T007, T009 |
| FR-004, FR-005, FR-006: shared model, reads and write rules | T001, T003 | T002, T007 |
| FR-007: explicit repeatable setup/no implicit changes | T001, T003 | T002, T004, T007 |
| FR-008, FR-009: async, cancellation, safe failures/Retry | T003, T005 | T002, T004, T007–T008 |
| FR-010: configured selection/default | T005 | T004, T007 |
| FR-011: fresh cross-provider results | T003 | T002, T007 |
| FR-012: repeatable identified comparison | T002, T004, T006 | T007–T008 |
| SC-001, SC-002, SC-003: equal results, full contract, visibility/setup | T001, T003 | T002, T007 |
| SC-004, SC-005: safe window, original regression and evidence | T003, T005 | T002, T004, T007–T008 |

**First buildable milestone**: T001–T003 deliver the complete service library and comparison
suite. US1/US2 deliberately ship together because the confirmed scope is full parity.
T004–T005 integrate application selection; all remaining tasks are required before claiming
the complete feature verified. This refinement changes task organization only.

## Execution status (2026-11-02)

T001–T007 and T009 completed; T009 verifies the independence correction. Automated results and commands are recorded in [quickstart.md](quickstart.md).
T008 remains open: Computer Use fails before desktop access with `sandboxCwd is not a local file URI`
for this WSL workspace, including after a kernel reset. The exact error is recorded in the guide;
manual acceptance from both features remains unexecuted.
