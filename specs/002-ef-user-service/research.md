# Research: Parallel Entity Framework User Service

**Date**: 2026-11-02
**Status**: Complete. Decisions are based on repository inspection and primary documentation;
no package installation, implementation, build, or database operation was performed.

## 1. Framework and package

**Decision**: Use EntityFramework **6.5.2**, pinned exactly, with its .NET Framework assets and
System.Data.SqlClient SQL provider. Add `PackageReference Include="EntityFramework" Version="[6.5.2]"`
to both existing classic projects. Restore with Visual Studio MSBuild `-restore`.

**Rationale**: The package was released April 28, 2026, targets .NET Framework 4.5 among its assets,
and is compatible with net48. That asset group has no additional NuGet dependencies. Explicit
same-version references in both projects make application runtime copying predictable; they do
not change project format or the public service contract.

**Alternatives considered**: Current EF Core requires a platform migration. The 6.6 preview is
unnecessary. The separate Microsoft.EntityFramework.SqlServer package changes the SQL provider.
packages.config would also work, but requires more package/install bookkeeping in a project
currently using neither package-management style.

**Sources**: [package/version metadata](https://www.nuget.org/packages/EntityFramework/6.5.2),
[EF releases](https://learn.microsoft.com/en-us/ef/ef6/what-is-new/),
[PackageReference support](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files),
[restore guidance](https://learn.microsoft.com/en-us/nuget/consume-packages/package-restore).

## 2. Retain the original and share only explicit setup

**Decision**: Add EfUserService beside SqlUserService. Leave SqlUserService.cs, IUserService.cs,
User.cs, and Database/Schema.sql unchanged. Compose SqlUserService only for its existing
connection validation and explicit CreateOrUpdateDatabaseAsync operation. EF performs every
user query, insertion, update, and deletion independently.

**Rationale**: The existing setup already handles repeatability, constraint repair, creation
races, transactions and schema locking. Reusing that infrastructure avoids a second schema
authority while preserving both data-access implementations for comparison. Constructor validation
does not access storage. No normal EF operation invokes setup.

**Alternatives considered**: EF migrations/initializers would introduce different schema ownership
and potentially extra tables. Extracting shared internals from the original obscures the baseline;
delegating EF data operations to it would fail the comparison goal.

**Evidence**: `UserDatabaseService/SqlUserService.cs`, `Database/Schema.sql`, and existing service
integration checks. This setup composition is a project-specific design decision.

## 3. Explicit model and provider configuration

**Decision**: Map the existing User directly to dbo.User using an operation-owned UserDbContext.
Use Login as a non-generated key; map required Unicode strings of length 100 and the existing
integer Age. Disable the context initializer, proxies, and lazy loading. Use a single
UserDbConfiguration associated through DbConfigurationType, registering
System.Data.SqlClient -> SqlProviderServices.Instance.

**Rationale**: No data conversion, EF-specific DTO, migration history, implicit database creation,
or host-specific EF XML is needed. Code configuration works for the WPF application, PowerShell
checks and disposable hosts. Configuration is AppDomain-wide and must not be repeatedly replaced.

**Alternatives considered**: Host-specific EF config sections are easier to miss when tests create
temporary executables. Default conventions risk table/key mismatch or unwanted initialization.

**Sources**: [code configuration](https://learn.microsoft.com/en-us/ef/ef6/fundamentals/configuring/code-based),
[provider model](https://learn.microsoft.com/en-us/ef/ef6/fundamentals/providers/provider-model),
[fluent mapping](https://learn.microsoft.com/en-us/ef/ef6/modeling/code-first/fluent/types-and-properties),
[initializer control](https://learn.microsoft.com/en-us/dotnet/api/system.data.entity.database.setinitializer?view=entity-framework-6.2.0).

## 4. Fresh results and parameterized multi-login queries

**Decision**: Use a disposed context per operation, AsNoTracking reads, database equality/order,
and native async materialization. Preserve original validation/trim ordering and ordinal
distinct-input counting. Build multiple-login queries as a balanced OR tree of separately
captured equality values; replace only the entity parameter when combining expressions.

**Rationale**: EF6 Contains can inline constants, conflicting with the constitution's requirement
to parameterize user input. Retained closure member expressions allow EF to bind values.
Balanced composition avoids a 2,000-deep expression chain. SQL collation remains authoritative.
Fresh contexts prevent stale reads after writes through the other service.

**Alternatives considered**: Contains, Expression.Constant(userValue), string-built SQL,
client-side filtering and a shared long-lived context are unsuitable for these constraints.

**Verification gate**: A test-only DbCommandInterceptor must confirm that 1 and 2,000 distinct
inputs are bound Unicode parameters rather than literals, with punctuation/case variants;
2,001 inputs are rejected before querying. This translation choice is supported by EF sources,
but must be verified against the pinned provider during implementation.

**Sources**: [EF6 performance guide](https://learn.microsoft.com/en-us/ef/ef6/fundamentals/performance/perf-whitepaper),
[closure parameter handling](https://github.com/dotnet/ef6/blob/v6.5.2/src/EntityFramework/Core/Objects/ELinq/Funcletizer.cs),
[no-tracking](https://learn.microsoft.com/en-us/ef/ef6/querying/no-tracking),
[context lifetime](https://learn.microsoft.com/en-us/ef/ef6/fundamentals/working-with-dbcontext).

## 5. Write and error parity

**Decision**: Validate and snapshot inputs without changing caller objects. Create with Add and
SaveChangesAsync. For update, attach the normalized snapshot and mark only Name/Age modified
unconditionally. Delete a key-only attached stub. A successful save returns true; a zero-row
DbUpdateConcurrencyException for these single-entity operations returns false. Add no concurrency
token. Translate insert duplicate codes 2601/2627 to the existing DuplicateLoginException.
Unwrap known EF failures to preserve underlying SqlException type/number and genuine cancellation.

**Rationale**: A tracked no-op update could skip the command despite the original returning true
for an existing record. Forced modifications preserve that outcome and last-writer-wins behavior.
Deleted entries do not require full field validation. Raw provider categories must remain
recognizable by existing callers and MainWindow's safe message mapping.

**Alternatives considered**: Reading before each update/delete adds a race and round trip.
Returning false for every EF exception hides real storage errors. Exposing EF wrappers breaks
existing SqlException handling.

**Sources**: [forced property modification](https://learn.microsoft.com/en-us/ef/ef6/saving/change-tracking/property-values),
[validation states](https://learn.microsoft.com/en-us/dotnet/api/system.data.entity.dbcontext.shouldvalidateentity?view=entity-framework-6.2.0),
[save outcomes](https://learn.microsoft.com/en-us/dotnet/api/system.data.entity.dbcontext.savechangesasync?view=entity-framework-6.2.0),
[save exception wrappers](https://learn.microsoft.com/en-us/dotnet/api/system.data.entity.infrastructure.dbupdateexception?view=entity-framework-6.2.0).

## 6. Cold loading, selection and validation

**Decision**: Keep constructors free of EF initialization. After original input validation,
schedule the EF operation on a worker so cold synchronous model setup cannot block the UI;
create/use/dispose the context inside that worker, await EF async I/O, and forward cancellation.
No context crosses threads or operations. Retain the window's existing awaiting/close guards.

Select through UserServiceFactory and the UserServiceImplementation app setting: Sql or
EntityFramework, case-insensitive after trimming; missing/blank defaults to Sql, invalid values
produce an argument/configuration failure. Keep UserDatabase as the sole connection setting.
Direct construction of either service remains supported.

**Rationale**: The worker boundary has a specific purpose: EF6 performs synchronous work before
its first query. It is not a replacement for native async I/O. Factory selection keeps provider
logic out of the window and provides a shared entry for test hosts.

**Alternatives considered**: Initializing the model in a constructor blocks before the error UI.
A UI picker, hot switching, separate databases or benchmark dashboard add unrequested scope.

Extend existing service/window checks rather than introducing a test framework. Verify both
implementations independently and mixed-provider operations, interception, cold startup, copied-host
dependency loading, no new tables and cancellation. Do not claim the earlier manual UI checks passed.

**Sources**: [cold query work](https://learn.microsoft.com/en-us/ef/ef6/fundamentals/performance/perf-whitepaper),
[EF6 async operations](https://learn.microsoft.com/en-us/ef/ef6/fundamentals/async).
