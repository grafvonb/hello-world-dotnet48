# Implementation Plan: Third User Service Using Stored Procedures

**Branch**: `003-ef-stored-procedures` | **Date**: 2026-11-02 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-ef-stored-procedures/spec.md`.

## Summary

Add `EfStoredProcedureUserService` as the third complete, independent IUserService implementation.
Use EF6 to invoke six fixed stored procedures for all normal user-data operations; only explicit
setup may execute DDL. Give it its own small context, independent connection/input validation and
bootstrap workflow. Preserve both older services and their helpers unchanged. Share contracts,
the user model and the existing schema definition, never implementation-specific helpers.

Use one typed Unicode login-list parameter and explicit update/delete result rows. Extend the
existing factory and validation scripts; retain current choices and add
`EntityFrameworkStoredProcedures`. Preserve the user's local EntityFramework configuration.

## Technical Context

**Language/Version**: C# 7.3, .NET Framework 4.8, classic WPF/service projects.

**Primary Dependencies**: Existing exact EntityFramework [6.5.2] references and
EntityFramework.SqlServer/System.Data.SqlClient. No package or project-format changes.
Keep copy-local deployment. Add the framework System.Xml reference to the service project
for DataTable metadata; do not add a NuGet transport package.

**Storage**: Same dbo.User, existing three columns and Latin1_General_100_CI_AS login identity.
Add six procedures and the schema-only dbo.UserLoginList parameter type, not a persisted table.
Existing Schema.sql remains unchanged. Bootstrap/ALTER batches avoid increasing the existing
effective SQL Server 2012+ syntax baseline.

**Testing**: Extend the three existing Windows PowerShell scripts. Service/window selectors
retain Sql, EntityFramework and Both, add the third choice and All. Extend the existing
EF-only compile/run check for the third service. Use owned SQL fixtures, command interception,
fresh copied hosts and original fake-window checks; no new test framework.

**Target Platform**: Existing Windows desktop, Visual Studio MSBuild and SQL Server environment.

**Project Type**: Existing WPF application plus service library; no new application project.

**Performance Goals**: Loading feedback, supplied-result layout for up to 1,000 users and
pending-close interaction retain the inherited one-second targets. Cold EF work runs off the
Dispatcher. No throughput benchmark or implementation ranking.

**Constraints**: All seven methods independently supported; six normal user-data operations
only through EF procedure calls; no fallback, SaveChanges or direct provider execution.
No references to either previous service/context/configuration in new implementation sources.
Keep public types, prior service/helper files, Schema.sql, selection fallback and local config.
No implicit setup, migrations, new persisted tables, user copies or automatic permission changes.

**Scale/Scope**: Three implementations, seven service operations, six procedures, one TVP,
0/1/1,000 users, 2,000 ordinal-distinct login inputs and six directed cross-service pairings.

## Constitution Check

| Principle | Before research | After design | Evidence |
|---|---|---|---|
| I. Desktop compatibility | PASS | PASS | Same net48/C# 7.3/classic projects and pinned package; no provider/runtime upgrade. |
| II. Service boundary | PASS | PASS | EF execution, procedure parameters and explicit setup stay in the library. |
| III. Responsive explicit UI | PASS | PASS | Lazy service construction, worker-owned cold context, native async calls and existing close/Retry flow. |
| IV. Data/configuration | PASS | PASS | Bound scalar/TVP inputs, unchanged identity/schema, explicit transactional setup, preserved local selection. |
| V. Observable verification | PASS | PASS | Original suites retained; procedure-use, independent compilation, three-way parity and fresh-host checks added. |
| Scope/governance | PASS | PASS | Procedure bootstrap exception is explicit in the spec; no automatic setup or policy amendment. |

No constitution exception is needed. Research resolves every design unknown; runtime/deployment
behavior remains an implementation verification gate, not a claimed pass.

## Project Structure

### Documentation (this feature)

```text
specs/003-ef-stored-procedures/
├── spec.md
├── checklists/requirements.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   ├── user-service.md
│   ├── stored-procedures.md
│   └── implementation-selection.md
└── quickstart.md
```

Tasks belong to the next `$speckit-tasks` phase and are not generated here.

### Source Code (repository root)

```text
UserDatabaseService/
├── EfStoredProcedureUserService.cs       # New: all seven operations and independent setup.
├── StoredProcedureUserDbContext.cs       # New: empty raw-query context, own initializer disabled.
├── Database/StoredProcedures/
│   ├── Bootstrap.sql                     # Conditional type/stub creation, type validation.
│   ├── GetAll.sql                        # One ALTER PROCEDURE batch per operation.
│   ├── GetByLogin.sql
│   ├── GetByLogins.sql
│   ├── Create.sql
│   ├── Update.sql
│   └── Delete.sql
├── UserServiceFactory.cs                 # Add third choice.
└── UserDatabaseService.csproj            # Compile/resource entries, framework reference.
HelloWorldWpf48/
└── MainWindow.xaml.cs                    # Add SQL2812 to existing storage-error category.
scripts/
├── Test-UserDatabaseService.ps1           # Three choices/All, procedure guard and shared parity.
├── Test-MainWindow.ps1                    # Third copied host, missing procedure, cold preparation.
└── Test-EfIndependence.ps1                # Separate source allowlist for third-only executable.
README.md                                # Third choice, explicit setup and validation commands.
```

**Structure Decision**: Two new C# implementation files and seven focused setup resources.
No shared helper extraction, new global EF configuration, service wrapper, repository layer,
SQL batch parser or new test script. Leave SqlUserService.cs, EfUserService.cs, UserDbContext.cs,
UserDbConfiguration.cs, IUserService.cs, User.cs, DuplicateLoginException.cs and Schema.sql unchanged.
Do not edit App.config merely to add a documented choice.

## Phase 0: Research Outcome

[research.md](research.md) resolves EF raw procedure calls, async/parameter behavior, result-row
semantics, TVP collation/duplicates, configuration discovery, independent setup and validation.
Decisions use pinned EF6 source and Microsoft documentation; no runtime probe was necessary
to choose the design. No unresolved clarification remains.

## Phase 1: Design

- Service constructors independently apply the original connection validation and store
  normalized target/master strings and catalog name. No EF or storage access in constructors.
  Input validation/trim order mirrors existing behavior; snapshot writes without mutating callers.
- Each nonempty operation enters its own Task.Run async flow, creates/uses/disposes its own
  StoredProcedureUserDbContext and forwards cancellation. Keep synchronous EF first-use work
  inside that flow and check cancellation after preparation. Dispose TVP payloads only after
  awaited execution. Empty multi-login input bypasses context/storage.
- The new context has no DbSet, mapping or DbConfiguration attribute/subclass. Its static
  constructor disables its initializer. Do not refer to either older EF helper or register
  configuration repeatedly. Validate full-library configuration order and isolated provider
  discovery in fresh processes before accepting this design's runtime behavior.
- Execute only the constant procedure invocations in [stored-procedures.md](contracts/stored-procedures.md).
  Reads use Database.SqlQuery<User>; create uses ExecuteSqlCommandAsync; update/delete use
  Database.SqlQuery<int>. Never infer success from ExecuteSqlCommand's affected-row return.
- Preserve direct SqlException numbers and genuine cancellation through known wrapper unwrapping.
  Translate duplicate creates to the shared DuplicateLoginException. Missing/invalid procedure
  result shapes fail; only the defined 0 outcome means not found.
- Independently implement explicit setup through own EF master/target contexts. Use autocommit
  for catalog creation, then the exact shared transaction-owned schema lock for Schema.sql,
  Bootstrap.sql and six ALTER resources. Preserve cancellation-before-commit, creation races,
  data, definitions and grants. No normal path repairs missing procedures.
- UserServiceFactory adds EntityFrameworkStoredProcedures with the same trim/case rules.
  Existing fallback stays Sql; explicit local EntityFramework remains untouched. The window
  needs only SQL2812 alongside SQL208; its state machine and XAML stay unchanged.

### Validation Handoff

- Keep original service assertions and old EF scalar-parameter interception. Add one third-service
  procedure guard covering reader/nonquery/scalar callbacks and all six fixed invocations.
  Inspect actual scalar/TVP parameters and async execution; scope bootstrap/fixture maintenance
  separately. Verify expected observations so bypassing EF cannot pass vacuously.
- All runs each provider's full suite and one shared fixture for 0/1/1,000 comparisons,
  all six directed fresh-read pairings, and mixed setup/constraint/procedure repair. Do not
  rerun the entire pair matrix inside every provider pass.
- Owned negative tests cover every missing procedure without auto-repair, direct SQL2812,
  explicit repair/recovery, missing tables, incompatible TVP schema, malformed write results,
  duplicate races and denied execution using only a disposable database principal/scope.
  No server login or normal principal permissions are changed.
- Extend copied SQL hosts for third selection and SQL2812/Retry. Provision third-service
  fixtures in a separate process, then launch fresh Full/ColdClose UI hosts without warming
  the third context. Also test third-first/original-EF-first configuration use in fresh hosts.
- Extend the existing independence script with original-EF/third/Both selection and separate
  source/resource allowlists; retain its original default. Reuse the compact seven-operation
  smoke flow, add missing read-all procedure/explicit repair, and avoid duplicating the full
  parity suite there. The third executable excludes
  both older services, UserDbContext, UserDbConfiguration, factory and baseline service DLL.
- Run Windows MSBuild restore/build, original fake suite, real-source All, service All and
  independent Both. Record only actual results in [quickstart.md](quickstart.md).
  Manual keyboard/readability/resize/scroll/pending-close and real-third inspection remain
  required; preserve inherited unexecuted status if Computer Use is still unavailable.
