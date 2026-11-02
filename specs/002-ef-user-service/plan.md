# Implementation Plan: Parallel Entity Framework User Service

**Branch**: `002-ef-user-service` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)

**Input**: `specs/002-ef-user-service/spec.md`; full seven-operation scope confirmed in clarification.

## Summary

Add EfUserService implementing the unchanged IUserService contract beside SqlUserService.
Use EF6 for all user queries and CRUD; share only original constructor validation and explicit
schema setup through composition. Both target the same table and data rules. A small factory
selects Sql (default) or EntityFramework from application configuration. Preserve the current
window, original service, and schema. Extend existing checks to prove behavior parity.

## Technical Context

**Language/Version**: C# 7.3, .NET Framework 4.8, existing WPF/classic project files.

**Primary Dependencies**: EntityFramework 6.5.2, exact PackageReference `[6.5.2]` in both existing
projects; EF6 EntityFramework.SqlServer using System.Data.SqlClient. No new application project.
Set CopyLocalLockFileAssemblies=true for predictable DLLs in both standalone service and app outputs.
Add the framework System.ComponentModel.DataAnnotations reference in the service project for
explicit database-generation metadata; User itself remains annotation-free.

**Storage**: Existing dbo.User with Login primary key and Latin1_General_100_CI_AS collation.
No migrations, new tables, history tables, seed data, or automatic initialization.

**Testing**: Existing Windows PowerShell service and STA window harnesses, extended for Sql,
EntityFramework, and Both; real SQL Server owned fixtures; test-only EF command interception.
Visual Studio MSBuild restore/build and copied-host deployment checks. No new test framework.

**Target Platform**: Existing Windows runtime/build environment capable of net48 execution,
Visual Studio MSBuild with PackageReference restore and NuGet access.

**Project Type**: Existing desktop application plus UserDatabaseService library.

**Performance Goals**: Preserve previous window targets: loading feedback within one second,
layout within one second after a supplied result up to 1,000 users, responsive pending work.
EF cold metadata/query preparation is source work and must execute off the UI thread.
No formal throughput benchmark or claim that one implementation is faster.

**Constraints**: Retain original public types, validation and outcomes, source ordering, async
cancellation, parameterized user values, read-only application startup, safe failure messages,
and System.Data.SqlClient. Preserve SqlUserService.cs unchanged.

**Scale/Scope**: Seven service operations, datasets 0/1/1,000, filtered input limit 2,000.
Configuration selection only; no new picker, editing UI, backend, or authentication model.

## Constitution Check

*GATE: Pass before research and re-check after design.*

| Principle | Before research | After design | Evidence |
|---|---|---|---|
| I. Compatibility | PASS | PASS | Pinned EF6 net45 assets support net48; classic projects/C# 7.3 retained. |
| II. Service boundary | PASS | PASS | EF/context/configuration stay in the library; window only selects IUserService. |
| III. Responsive UI | PASS | PASS | Lazy construction, worker-owned cold model preparation, native async I/O, existing close guards. |
| IV. Data/configuration | PASS | PASS | Explicit shared setup, disabled initializer, same constraints, bound inputs, unchanged original/schema. |
| V. Verification | PASS | PASS | Both existing suites plus cross-provider, SQL interception and copied-host checks. |
| Scope/documentation | PASS | PASS | User-requested dependency has a documented comparison purpose; README/quickstart describe restore and selection. |

No amendment or exception is needed: EF6 keeps the required SQL provider and target. The package
exists specifically to fulfill the requested comparison; built-in libraries cannot demonstrate
that alternative. Runtime translation, restore and deployment remain implementation acceptance
gates, not claims of already executed tests.

## Project Structure

### Documentation (this feature)

```text
specs/002-ef-user-service/
├── spec.md
├── checklists/requirements.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   ├── user-service.md
│   └── implementation-selection.md
└── quickstart.md
```

tasks.md belongs to the next command and is not created here.

### Source Code (repository root)

```text
UserDatabaseService/
├── EfUserService.cs             # New; validation, EF operations, exception normalization.
├── UserDbContext.cs             # New; explicit existing-table mapping, operation-owned.
├── UserDbConfiguration.cs       # New; one EF provider configuration, initializer disabled.
├── UserServiceFactory.cs        # New; Sql/EntityFramework selection, no configuration file I/O.
├── UserDatabaseService.csproj   # Exact EF package, explicit Compile entries, copy-local output.
├── SqlUserService.cs            # Retained unchanged, including DuplicateLoginException.
├── IUserService.cs              # Retained unchanged.
├── User.cs                      # Retained unchanged.
└── Database/Schema.sql          # Retained unchanged.
HelloWorldWpf48/
├── MainWindow.xaml.cs          # Existing lazy factory reads app setting and calls service factory.
├── App.config                  # Existing connection; new implementation app setting.
├── HelloWorldWpf48.csproj      # Matching EF package/copy-local runtime assets.
└── MainWindow.xaml             # No required change.
scripts/
├── Test-UserDatabaseService.ps1 # Extend existing suite with provider selection/parity/interception.
└── Test-MainWindow.ps1          # Extend real-source host with provider selection/cold EF checks.
README.md                      # Both implementations, package restore, configuration and checks.
```

**Structure Decision**: Keep the implementation alternatives readable side by side in the current
library. New small EF-specific classes meet framework needs; avoid a new repository abstraction,
DTO, shared-context singleton, test project, or refactor of the original baseline.

### Phase 0: Research outcome

[research.md](research.md) resolves version/restore, provider configuration, schema ownership,
parameterization, update/delete semantics, error parity and cold loading. Its decisions reference
primary package metadata, Microsoft documentation and EF source.

### Phase 1: Design

- EfUserService stores a validated connection and a composed SqlUserService used solely for
  constructor validation and explicit CreateOrUpdateDatabaseAsync. Never delegate user reads/CRUD.
- Data operations, except the empty multiple-login fast path, validate inputs in original order
  and enter a library-internal
  Task.Run async boundary for context creation/model preparation and native EF asynchronous work.
  Create/use/dispose one context within that worker; pass the token to scheduling and EF I/O,
  checking it after synchronous preparation. Never share a context or block the UI.
- Map the existing User without annotations or schema changes. AsNoTracking reads use SQL
  collation/order. Snapshot writes trim values without mutating caller objects.
- Multi-login validation preserves ordinal distinct counting, cancellation order and the 2,000
  cap. Compose a balanced OR predicate from individually captured equality values; retain closure
  members so the provider binds parameters. No Contains, input constants, interpolated SQL or
  client filtering. Verify actual generated commands for the pinned provider.
- Update attaches a normalized snapshot and forces Name/Age modified; delete attaches a key-only
  stub. Save once. No concurrency tokens; zero-row single-entry concurrency returns false.
  An unchanged existing update returns true, preserving original DML behavior.
- Normalize known EF wrappers: insert duplicate SQL codes become the existing DuplicateLoginException;
  other underlying SqlException values remain directly catchable with their Number intact.
  Preserve OperationCanceledException. Unexpected failures never become empty/not-found results.
- Code-based provider configuration is established once per AppDomain and disables automatic
  initialization. No EF XML transforms, migrations or schema management on normal access.
- UserServiceFactory.Create(implementation, connectionString) resolves trimmed, case-insensitive
  Sql/EntityFramework. Missing/blank selects Sql; unsupported text throws ArgumentException.
  MainWindow's existing safe configuration handling and state machine remain unchanged.
- Add the exact EF PackageReference to both projects and copy all built DLLs into test hosts.
  Verify EF execution from that copied directory rather than depending on a developer package cache.

[data-model.md](data-model.md) defines mapping/lifetime invariants;
[contracts/user-service.md](contracts/user-service.md) and
[contracts/implementation-selection.md](contracts/implementation-selection.md) define caller behavior.

### Validation handoff

Extend Test-UserDatabaseService.ps1 with -Implementation Sql|EntityFramework|Both (default Sql).
Both runs the same full suite per implementation on owned fixtures and additional mixed-provider
checks, including repeated/concurrent setup, unchanged updates, duplicate races, 2,000/2,001
boundaries, and parameter interception. No normal database is used for destructive tests.

Extend Test-MainWindow.ps1 with the same implementation choice for real-source mode. Its fake
suite remains provider-independent. A copied-host EF run must exercise the parameterless window
and configuration path before other EF queries warm the model; use the original service only to
prepare that fixture. Check cold UI responsiveness, safe provider errors, Retry, data preservation
and complete DLL deployment.

[quickstart.md](quickstart.md) specifies commands, outcomes and evidence. Both service suites and
window checks are required after implementation. The earlier manual UI limitation remains open;
do not convert it to a pass. This command creates design documentation only.

## Complexity Tracking

No constitution violations. Shared explicit schema setup deliberately avoids a second schema
authority while retaining independent user-data implementations.
