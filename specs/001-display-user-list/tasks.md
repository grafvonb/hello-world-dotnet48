# Tasks: Display Users in the Main Window

**Branch**: `001-display-user-list`
**Inputs**: [spec.md](spec.md), [plan.md](plan.md), [data-model.md](data-model.md),
[UI contract](contracts/main-window.md), [source contract](contracts/user-source.md),
[research.md](research.md), [quickstart.md](quickstart.md).
**Governance**: `.specify/memory/constitution.md`, version 1.0.0.

All paths are repository-relative. `[P]` permits parallel authoring in separate files, with
dependencies below; execution waits for a built implementation. Keep the existing net48/C# 7.3
projects, source ordering, and service/schema unchanged. Only GetAllAsync is allowed in the view.

## Phase 1: View Existing Users on Launch — US1 (P1)

**Independent acceptance**: Display all returned users accurately; remain responsive during
loading and close safely even when the provider completes afterwards.

- [ ] T001 [P] [US1] Replace the greeting in `HelloWorldWpf48/MainWindow.xaml` with a resizable constrained Grid containing an explicit Name/Login/Age DataGrid, status text, and an initially hidden Retry button; use UsersGrid, LoadStatusText, and RetryButton identifiers plus accessible names, read-only cells, no insertion/deletion/sorting, native scrolling/keyboard navigation, virtualization, and complete 100-character values accessible without mouse-only tooltips; defer Retry event wiring to T005.
- [ ] T002 [US1] Implement the complete startup/load/close lifecycle in `HelloWorldWpf48/MainWindow.xaml.cs`: retain parameterless startup and add the lazy Func<IUserService> constructor, resolve UserDatabase inside the loading try block, guard first Loaded and concurrent attempts, render loading feedback before awaiting GetAllAsync with the lifetime token, and bind its non-null result once without changing values/order; maintain the states in `specs/001-display-user-list/data-model.md`, use safe failure feedback, remove the greeting handler, cancel on Closed, ignore late success/fault and post-close catch/finally UI updates, and dispose the token source after closure when active work settles; never block the UI thread or call setup/CRUD.
- [ ] T003 [P] [US1] Create `scripts/Test-MainWindow.ps1` as the complete shared STA driver plus US1 checks: support -Configuration Debug|Release and -Interactive, load built assemblies, use an Add-Type fake IUserService and bounded Dispatcher pumping, reject/count all non-GetAllAsync calls, and clean up multiple windows without ending the harness; assert observable rows/order/read-only/accessibility for 1/100/1,000 users with duplicate names, Unicode, age zero, and 100-character text, one startup request, the one-second feedback/display targets, and safe pending closure with cooperative or cancellation-ignoring providers that later succeed/fault; provide the interactive 1,000-row view and a nonzero exit on failure.

**Existing data constraints**: T002 displays `UserDatabaseService/User.cs` unchanged; it does
not add validation or normalize stored data.

| Field | Constraint from data-model.md |
|---|---|
| Name | "Required, nonblank; duplicates allowed"; "string / nvarchar(100)" |
| Login | "Required, nonblank, immutable identity; unique, case-insensitive and accent-sensitive"; "string / nvarchar(100)" |
| Age | "Required, zero or greater"; "int" |

## Phase 2: Recognize an Empty Result — US2 (P2)

**Independent acceptance**: An empty successful result shows exactly "No users found", with no
rows, loading/error text, Retry, sample data, or writes.

- [ ] T004 [US2] Add the Empty transition to the shared load flow in `HelloWorldWpf48/MainWindow.xaml.cs` and its acceptance case in `scripts/Test-MainWindow.ps1`; preserve "A non-null collection containing zero records is a successful empty result", clear loading/error feedback, hide grid/Retry, show "No users found", and assert zero setup/write calls.

## Phase 3: Recover from a Loading Failure — US3 (P2)

**Independent acceptance**: A failed load stays in an open window; one Retry obtains current
rows or the empty state, while repeated input never overlaps requests.

- [ ] T005 [US3] Complete error/retry behavior in `HelloWorldWpf48/MainWindow.xaml.cs` and add the built-in System.Data reference in `HelloWorldWpf48/HelloWorldWpf48.csproj`: map configuration errors and SQL 18456/229/230, 208, 4060, and fallback errors to the fixed safe categories in `specs/001-display-user-list/contracts/user-source.md`; wire RetryButton to the same guarded load method, accept retries only from Failed while open/not busy, clear old errors, hide/disable Retry while loading, restore it after failure, and handle open-window cancellation as recoverable; preserve the existing targets/references and never display exception/connection details.
- [ ] T006 [P] [US3] Extend `scripts/Test-MainWindow.ps1` with throwing configuration factories, generic failure, recovery to populated/empty results, repeated failure, repeated Retry while pending, cancellation while open, and close during Retry; drive actual controls and assert exclusive states, safe messages, no duplicates/overlap/writes, and no late UI updates; test real SQL categories in T010 rather than manufacturing SqlException through reflection.

## Phase 4: Documentation and Final Validation

- [ ] T007 [P] Update `README.md` with the final user-list behavior, automatic loading, read-only scope, explicit storage preparation, UserDatabase configuration, empty/error/retry states, unchanged build prerequisites, and automated/interactive commands; remove greeting instructions.
- [ ] T008 Build `HelloWorldWpf48.sln` with Visual Studio MSBuild in Debug/Any CPU and run `scripts/Test-MainWindow.ps1` in Windows PowerShell STA; fix failures and record actual build/scenario results and 1/100/1,000-row timings in `specs/001-display-user-list/quickstart.md`.
- [ ] T009 Execute and record the keyboard/readability and window-interaction checks in `specs/001-display-user-list/quickstart.md`: complete first/last values in the interactive 1,000-row view, read-only F2/Delete behavior, keyboard Retry, resizing/scrolling, and moving/closing during pending work.
- [ ] T010 Execute and record the owned-database/copied-build smoke checks in `specs/001-display-user-list/quickstart.md`: empty/populated results, missing/invalid configuration, unavailable/unprepared storage, denied access followed by Retry, unchanged stored data, and cleanup limited to owned fixtures; run `scripts/Test-UserDatabaseService.ps1` only if service/schema code unexpectedly changed, and distinguish unavailable checks from passed checks.

## Dependencies and Parallel Work

| Work | Prerequisite |
|---|---|
| T001 UI and T003 driver | Existing contracts; may be authored together |
| T002 load lifecycle | T001 control names; can overlap T003 authoring |
| T004 empty result | T002 and T003 |
| T005 recovery and T006 recovery cases | T004; may be authored together |
| T007 README | May overlap implementation; reconcile with final behavior |
| T008 automated validation | T001–T006 and a buildable solution |
| T009–T010 manual/SQL validation | T008; run sequentially because they update the same quickstart |

There is no separate setup/foundation phase: the solution and service already exist. Constructor
setup and shutdown belong to the loading lifecycle (T002); the framework reference belongs to
the error handling that uses it (T005). T004 intentionally combines one small behavior with its
acceptance case rather than creating a separate harness-edit task.

## Coverage

| Requirements | Implementation | Verification |
|---|---|---|
| FR-001, FR-002: automatic, accurate ordered list | T001–T002 | T003, T008, T010 |
| FR-003: read-only, no storage changes | T001–T002 | T003–T004, T006, T010 |
| FR-004, FR-005: distinct states and empty results | T002, T004–T005 | T003–T004, T006, T008, T010 |
| FR-006, FR-007, FR-008: safe errors and guarded Retry | T002, T005 | T003, T006, T010 |
| FR-009: responsive lifetime | T002 | T003, T006, T009 |
| FR-010, FR-011: complete values and accessible controls | T001, T005 | T003, T009 |
| SC-001, SC-002: counts/order and one-second targets | T001–T002 | T003, T008–T009 |
| SC-003, SC-004: safe states and recovery without duplicates/writes | T002, T004–T005 | T003–T004, T006, T010 |
| SC-005: keyboard readability and Retry | T001, T005 | T009 |

**MVP**: T001–T003 deliver the populated-list demonstration. US2 and US3 remain required for the
complete feature. Build and exercise that milestone only if demonstrating it; after later changes,
perform the final T008–T010 checks. The quickstart owns detailed procedures and recorded evidence.
