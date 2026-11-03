# Tasks: Independent EF6 Stored-Procedure Service

**Inputs**: [spec](spec.md), [plan](plan.md), [data model](data-model.md),
[user contract](contracts/user-service.md), [procedure contract](contracts/stored-procedures.md),
[selection contract](contracts/implementation-selection.md), [validation guide](quickstart.md).
**Branch**: `003-ef-stored-procedures`. **Constitution**: 1.0.0.
Paths are repository-relative. Each script is extended once; T006 owns execution and evidence.

## Boundaries

Preserve `UserDatabaseService/SqlUserService.cs`, `EfUserService.cs`, `UserDbContext.cs`,
`UserDbConfiguration.cs`, `IUserService.cs`, `User.cs`, `DuplicateLoginException.cs` and
`Database/Schema.sql` under that directory. Preserve the user's `HelloWorldWpf48/App.config`.
The third service shares only contracts/model/schema, never either older implementation/helper.
Keep classic net48/C# 7.3, EF [6.5.2] and copy-local deployment. Only explicit setup executes DDL;
all six data operations use EF procedure calls. No partial service, new global configuration,
package, abstraction, SQL parser, direct-table fallback or public test-phase switch.

## Phase 1: Complete Service — US1 Reads / US2 Independent Operations (P1)

**Acceptance**: Same three retrieval results for 0/1/1,000 users; all seven methods work when
both older services and their helpers are excluded. The shared interface is delivered in one increment.

- [X] T001 [US1] Extend `scripts/Test-UserDatabaseService.ps1` with the service checks below before T002. Add EntityFrameworkStoredProcedures/All; preserve default Sql, Both=original pair, existing checks and old EF scalar-parameter probes. Reuse helpers and table-driven cases; run the all-three dataset/pairing matrix once per All invocation, not inside every provider pass. Scope interceptors, fixture-only principals/impersonation and cleanup with finally. Define assertions here; execute them in T006.

- [X] T002 [US2] Deliver the complete core in `UserDatabaseService/EfStoredProcedureUserService.cs`, `UserDatabaseService/StoredProcedureUserDbContext.cs`, `UserDatabaseService/Database/StoredProcedures/` and `UserDatabaseService/UserDatabaseService.csproj`. Register both classes, System.Xml and seven embedded resources: Bootstrap.sql, GetAll.sql, GetByLogin.sql, GetByLogins.sql, Create.sql, Update.sql, Delete.sql. Use an empty context with Database.SetInitializer<StoredProcedureUserDbContext>(null) in its static constructor, proxies/lazy loading disabled, no sets/mappings/configuration attribute or older-helper references. Constructors store validated strings only. Independently validate connections ("1–128-character name", "non-system catalog", "no AttachDBFilename") and preserve Name "nvarchar(100), required" / "Nonblank after trim; duplicates allowed.", Login "nvarchar(100), required, primary key" / "Trimmed, immutable; Latin1_General_100_CI_AS identity.", Age "int, required" / "Zero or greater." Implement all seven methods per the contracts: original validation order, private snapshots, ordinal-distinct 2,000 limit/empty fast path, worker-owned context/TVP lifetime, native async calls, read-only results and cancellation. Use the six exact EXEC templates, SqlQuery<User>, ExecuteSqlCommandAsync for create and SqlQuery<int> with strictly validated single 0/1 results for update/delete; preserve duplicate and SQL/cancellation categories. Bootstrap dbo.UserLoginList with "nvarchar(100) COLLATE Latin1_General_100_CI_AS" and "NOT NULL; no primary/unique constraint."; reject incompatible types. Install fixed stubs then six separate ALTER batches without GO, NOCOUNT, ordered explicit columns, EXISTS matching and immediate @@ROWCOUNT after unconditional matching writes. Own master autocommit creation with bound DB_ID/escaped catalog and narrow SQL1801 handling, then target transaction/shared UserDatabaseService.Schema lock, unchanged Schema.sql and ordered resources; retain 30-second lock/60-second command timeouts, grants, cancellation-before-commit and rollback without catalog deletion. No normal operation installs assets.

- [X] T003 [P] [US2] Extend `scripts/Test-EfIndependence.ps1` with EntityFramework/EntityFrameworkStoredProcedures/Both selection, retaining the original default. Compile separate executables from explicit allowlists; the third includes only its service/context/resources and shared contracts/model/schema. Exclude both older services, UserDbContext, UserDbConfiguration, factory and baseline service DLL; assert their types are absent and copy only required EF DLLs. Reuse the compact seven-operation smoke: normal discovery, cold concurrent/repeated setup, preserved rows, missing-check/read-all-procedure repair, duplicate and unchanged/missing-write outcomes, validation/cancellation and finally cleanup. Keep the full boundary/parity matrix in T001; run both isolated executables in T006.

### Service Checks Owned by T001

| Group | Required coverage |
|---|---|
| Parity | All seven methods; three reads at 0/1/1,000 users; empty/missing, null/blank, 100/101 characters, Unicode/case/accent, zero/negative age, trimming, caller snapshots, unchanged update=true, missing writes=false, duplicate races and validation/cancellation ordering. |
| Procedure proof | Reader/nonquery/scalar interception observes every exact invocation and async call (fixed parameterized Text EXEC is valid); bound scalar types/sizes and TVP type/rows; actual matched Unicode/punctuation inputs at 1/2,000, ordinal-distinct case variants and trim duplicates; reject 2,001 before connection even on unprepared storage. Inspect installed definitions/type metadata; separate bootstrap/exact provider metadata, reject direct-table commands and vacuous zero observations. |
| Shared state | One All fixture tests all six directed writer→primed-retained-reader pairings for create/update/delete and repeated/concurrent mixed setup. |
| Setup/failures | Missing storage/table, each missing/stale procedure, direct SQL2812 with no auto-repair then explicit recovery, real SQL229 through fixture-only scope, incompatible type and malformed write-result failures. Preserve rows/grants, one application table/three columns, existing missing-check repair scope, normal data/permissions and owned cleanup. |

## Phase 2: Existing Window — US3 Selection and Comparison (P2)

**Acceptance**: Three configured choices preserve the existing states, Retry and data.
Fresh processes prove cold responsiveness and both EF configuration-use orders.

- [X] T004 [P] [US3] Extend `scripts/Test-MainWindow.ps1` before T005. Preserve Sql/default, Both=old pair, Phase/Interactive and the fake suite; add third/All and exact procedure observation. Reuse copied hosts for populated/empty/error/access, default/blank/case/trim/unknown selection and unchanged rows; test missing procedure feedback/no installation, explicit external repair and one Retry. Prepare third-service fixtures in a separate process; fresh Full/ColdClose hosts must not warm the third context. Assert feedback/Dispatcher and close under one second, cancellation/no late mutation and existing supplied-result layout. Add fresh third→original-EF and original-EF→third cases without forcing old configuration; honor real-source Interactive. Keep DLL/config copies and fixture identity/cleanup owned. Execute in T006.

- [X] T005 [US3] Add EntityFrameworkStoredProcedures → EfStoredProcedureUserService to `UserDatabaseService/UserServiceFactory.cs` under existing trim/case/fallback rules; add SQL2812 alongside SQL208 in `HelloWorldWpf48/MainWindow.xaml.cs`. Preserve lazy construction, UserDatabase, both earlier choices, the UI state machine/XAML and local `HelloWorldWpf48/App.config`.

## Phase 3: Documentation and Verification

- [X] T006 Update `README.md` and `specs/003-ef-stored-procedures/quickstart.md`, restore/build `HelloWorldWpf48.sln` with Visual Studio MSBuild Debug/Any CPU, then run `scripts/Test-UserDatabaseService.ps1 -Implementation All`, `scripts/Test-EfIndependence.ps1 -Implementation Both` and `scripts/Test-MainWindow.ps1` in fake mode plus real `-SqlServer localhost -Implementation All` mode. Document third choice, independent explicit setup/bootstrap exception, setup versus runtime procedure EXECUTE/type EXECUTE+REFERENCES privileges, selectors, deployment and Interactive commands; replace planning caveats and record actual per-provider outcomes/timings/cleanup, including all service checks, isolation and configuration order. Verify both EF DLLs in app/service outputs, protected files and pre-existing local config, then git diff --check. Fix failures and rerun affected checks; avoid full-suite repetition without a relevant change. Leave manual acceptance pending for T007.

- [ ] T007 Perform the keyboard/readability/resize/1,000-row-scroll/Retry-focus/pending-move-close and actual third-configured interactive scenarios using `scripts/Test-MainWindow.ps1 -Interactive` and its real third-choice mode; record results in `specs/003-ef-stored-procedures/quickstart.md`. Reattempt Computer Use; preserve inherited unexecuted acceptance and leave this task unchecked with the exact reason if desktop access still fails.

## Dependencies and Completion

```text
T001 -> T002 -> (T003 + T004)
T004 -> T005
T003 + T005 -> T006 -> T007
```

T003 and T004 are independent harness-authoring tasks after T002; neither includes production
fixes, builds or test runs. Their `[P]` markers apply only then. All core/project/resource edits
are consolidated in T002. T004 precedes factory/UI integration T005. T006 starts after T003–T005,
owns documentation/evidence and runs the required complete checks once before any failure-driven
reruns. Manual evidence T007 follows it, avoiding concurrent guide writes.

The first buildable milestone is T002; acceptance is established by T006. US1/US2 share a core
but retain separate read-parity and removal proofs; US3 uses copied configuration. All seven
tasks are required, with unavailable manual work reported honestly.

| Requirement/outcome | Delivery | Evidence |
|---|---|---|
| FR-001, FR-003, SC-004: retained independent full service | T002, T005 | T001, T003, T006 |
| FR-002, FR-007, SC-003: procedures and bound data | T002 | T001, T004, T006 |
| FR-004, FR-005, FR-006, SC-001, SC-002: same contract/data | T002 | T001, T003, T006 |
| FR-008, FR-009, SC-005: explicit setup and fresh shared state | T002 | T001, T003, T004, T006 |
| FR-010, FR-012, SC-006: safe errors/async/window | T002, T005 | T001, T004, T006, T007 |
| FR-011: selection/defaults | T005 | T004, T006 |
| FR-013, SC-007: runnable checks and honest evidence | T001, T003, T004 | T006, T007 |

## Execution Status — 2026-11-03

T001–T006 completed; actual evidence is recorded in [quickstart.md](quickstart.md).
T007 remains unchecked: Computer Use rejects the WSL workspace URI before desktop access,
including after a kernel reset. Manual acceptance from earlier features remains unexecuted.
