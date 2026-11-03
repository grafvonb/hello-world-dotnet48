# Feature Specification: Third User Service Using Stored Procedures

**Feature Branch**: `003-ef-stored-procedures`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "provide third userserviceimplementation which uses onyl stored procedures with ef6, other two must be kept"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read the Same Users Through Stored Procedures (Priority: P1)

As a developer comparing data-access approaches, I want a third service that retrieves users
through stored procedures so that I can compare three approaches against the same records.

**Why this priority**: A third selectable name has no comparison value unless its reads actually
use the requested approach and preserve the established results.

**Independent Test**: Prepare an isolated source explicitly, exercise all three retrieval
operations through the third service, compare results with each existing service, and observe
that every user-data read by the third service invokes stored procedures.

**Acceptance Scenarios**:

1. **Given** an unchanged source containing 0, 1, or 1,000 users, **When** all users are requested
   through each service, **Then** all three return identical Name, Login and Age values in
   the same login order.
2. **Given** matched and missing logins, **When** single or multiple users are requested through
   the third service, **Then** matching, trimming, ordering, missing results and duplicate-input
   handling agree with the existing services.
3. **Given** the third service performs a user-data read, **When** its executed commands are
   inspected, **Then** that read uses stored procedures, with bound input values and no direct
   user-table query or fallback to either existing service.
4. **Given** the required procedures are missing or execution is denied, **When** a read is
   requested, **Then** it fails through the established error handling without creating
   procedures, returning an empty success, or switching implementations.

---

### User Story 2 - Independently Prepare and Manage the Same Users (Priority: P1)

As a developer, I want the third service to support the complete existing contract independently
so that it remains useful even if either other implementation is removed.

**Why this priority**: Complete independence and full service parity are established requirements
of this comparison. Delegating setup or validation to another service repeats the rejected design.

**Independent Test**: Build and run the third service with shared contracts and its own support
assets, excluding both existing implementations and their implementation-specific helpers;
exercise explicit setup and all six user-data operations against an owned fixture.

**Acceptance Scenarios**:

1. **Given** both existing implementations are excluded, **When** the third service is built
   and used on an isolated source, **Then** connection validation, explicit setup, all three
   retrieval operations, create, update and delete work without either existing implementation.
2. **Given** absent or prepared storage, **When** explicit setup is requested through the third
   service, **Then** storage and required procedures are prepared without losing records or
   changing the established identity and field rules.
3. **Given** prepared users, **When** creation, update or deletion is requested through the
   third service, **Then** those user-data changes execute only through stored procedures and
   produce the same success, duplicate-login, validation and not-found outcomes as the other services.
4. **Given** an existing user with unchanged values or an absent login, **When** update is
   requested, **Then** unchanged existing update succeeds and absent update returns not found;
   deleting an absent login also returns not found.
5. **Given** concurrent duplicate inserts, **When** operations finish, **Then** exactly one
   identity is stored and losing inserts produce the existing duplicate-login outcome.
6. **Given** a completed create, update or delete through any of the three services, **When**
   either other service reads the affected users again using a retained service instance,
   **Then** it observes the completed change without synchronization or record copying.
7. **Given** records and previously installed setup assets, **When** setup is repeated or
   requested concurrently through different services, **Then** rows survive, required
   constraints and third-service procedures are present, and all three services remain usable.

---

### User Story 3 - Select and Compare Three Implementations (Priority: P2)

As a developer running the existing desktop application, I want to select the third service
through the existing configuration approach while retaining both earlier choices.

**Why this priority**: All three approaches must remain directly usable and demonstrable through
the same window and repeatable comparison checks.

**Independent Test**: Run the existing window with each documented choice using isolated test
configuration, then run the shared comparison checks across all three implementations.

**Acceptance Scenarios**:

1. **Given** either existing implementation choice is configured, **When** the application
   starts, **Then** that choice retains its existing meaning and behavior.
2. **Given** the third implementation is configured, **When** the application starts, **Then**
   the same main window loads the same source through the third service and preserves loading,
   populated, empty, safe-failure, Retry and close behavior.
3. **Given** missing or blank selection, **When** the application starts, **Then** the existing
   original-service fallback is retained. A nonblank unknown choice remains a configuration
   failure rather than silently selecting another service.
4. **Given** missing procedures or unavailable storage, **When** the window loads, **Then** it
   shows safe failure feedback, performs no setup, and can recover through Retry after the
   underlying source is explicitly repaired.
5. **Given** a first request is pending, **When** the user interacts with or closes the window,
   **Then** it remains responsive and ignores any late completion after closure.
6. **Given** the documented comparison entry points, **When** a developer runs them, **Then**
   results identify each of the three services, report actual parity and procedure-use outcomes,
   and confine all setup and writes to owned fixtures.

### Edge Cases

- Duplicate names, age zero, Unicode and 100-character names/logins retain their established values.
- Names/logins longer than 100 characters after trimming, blanks, null inputs and negative ages
  preserve existing validation categories and ordering, including interactions with cancellation.
- Login identity remains case-insensitive and accent-sensitive; updates preserve stored login spelling.
- An empty multi-login input returns an empty collection without requiring storage or procedures.
- Multiple-login input accepts up to 2,000 distinct trimmed values counted with ordinal comparison,
  rejects 2,001 before storage access, and returns each matched user once even for case variants.
- Quotes, delimiters, comment-like text and other SQL punctuation in user values remain data;
  they cannot change procedure commands or match unrelated users.
- Procedure return values and affected-row reporting distinguish unchanged existing updates from
  missing users without converting real failures into not-found outcomes.
- Missing or outdated procedure definitions are repaired only during explicit setup.
- Existing sources prepared by either earlier service need explicit third-service setup before
  the new choice is usable; their records and earlier service choices remain usable throughout.
- Repeated/concurrent setup from any combination of services cannot remove third-service procedures,
  duplicate users, drop prepared storage or lose existing records.
- Denied procedure execution, missing tables, absent procedures and broken connections remain
  failures; none triggers an inline-query fallback or automatic installation.
- Cancellation remains cancellation. Cancellation after a completed write cannot promise rollback.
- First-use preparation and late success/failure/cancellation do not block or mutate a closed window.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Add a third implementation of the complete existing user-service contract while
  retaining both existing implementations, their behavior and their direct construction.
  Preserve existing public contracts and user-record fields.
- **FR-002**: Every user-data retrieval, insertion, update and deletion by the third service
  MUST execute stored procedures through the user-requested EF6 approach. It MUST NOT issue
  direct user-table queries, generate direct user-table changes, bypass EF6 for execution,
  or fall back to either existing implementation.
- **FR-003**: The third service MUST independently perform connection validation and all seven
  operations: explicit setup/update, retrieve-all, single-login retrieval, multiple-login
  retrieval, create, update and delete. It MUST NOT construct, reference or delegate to either
  existing implementation or depend on their implementation-specific helpers. Excluding those
  implementations MUST leave the third service buildable and runnable with shared contracts,
  the user model, shared schema definition and its own support assets.
- **FR-004**: All three services MUST operate on the same existing user records and constraints.
  Do not introduce separate user copies, new user fields, destructive conversions or additional
  persisted application/history tables. Adding the required procedure definitions is in scope.
- **FR-005**: Third-service retrieval MUST preserve fields, login ordering and matching,
  unique filtered results, empty/missing outcomes and the 2,000-input boundary described above.
  Subsequent reads MUST reflect completed changes from either other service.
- **FR-006**: The third service MUST preserve text trimming, nonblank Unicode names/logins of
  at most 100 characters, nonnegative age, immutable case-insensitive/accent-sensitive login
  identity, unchanged caller objects, duplicate-login handling and existing success/not-found
  write outcomes, including unchanged existing updates.
- **FR-007**: All user-supplied values MUST remain bound data in procedure invocations and any
  procedure-internal commands. Invalid inputs MUST be rejected before user-data execution,
  and concurrent inserts MUST enforce the existing unique-login outcome.
- **FR-008**: Explicit third-service setup MUST prepare missing storage and install or update
  its required procedure definitions, preserve existing rows, restore required constraints
  and support repeatable/concurrent setup with all three services. It MUST leave both earlier
  implementations usable without modifying their class implementations.
- **FR-009**: Procedure/database definition commands are permitted solely for explicit setup.
  Constructors, service selection, normal reads/writes and application launch MUST NOT create
  or repair storage or procedures. Missing required procedures MUST produce a failure.
- **FR-010**: Preserve asynchronous operations, cancellation and safe error handling. Existing
  callers MUST retain compatible validation, duplicate-login, cancellation and storage-error
  categories; unexpected failures MUST NOT become empty collections, success or not found.
- **FR-011**: Extend the existing configuration selection with a documented third choice using
  the same configured source. Retain existing choice meanings, original-service fallback for
  missing/blank values, case/whitespace rules, and unknown-choice failure. Preserve explicit
  user-selected configuration rather than overwriting it when adding the feature.
- **FR-012**: The main window MUST preserve its current read-only fields, ordering, keyboard
  access, loading/empty/failure states, Retry, one pending request and terminal close behavior.
  First-use work MUST allow loading feedback and user interaction within the existing one-second
  target; close MUST remain responsive while work is pending.
- **FR-013**: Provide repeatable checks and instructions covering all three services, their
  full contract and cross-service visibility, actual procedure use with bound values, independent
  operation without the other implementations, explicit setup, failures and unchanged window
  behavior. Checks MUST use owned fixtures, clean up their own assets, preserve normal data and
  permissions, identify tested choices, and distinguish passed, failed and unexecuted checks.

### Key Entities *(include if feature involves data)*

- **User**: The existing record containing required Name and Login and nonnegative Age.
  Login is its immutable, unique identity; names need not be unique.
- **Implementation Choice**: The existing developer-selected approach, extended from two choices
  to three. It changes how operations execute, not the source or meaning of user records.
- **Prepared Procedure Set**: The installed operations required by the third service to retrieve
  and manage users. Availability changes only through explicit setup; it adds no user copies.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For unchanged collections of 0, 1 and 1,000 users, all three choices produce identical
  field values, ordering and matched/missing lookup results in every comparison scenario.
- **SC-002**: The third choice passes all seven operation groups and all documented boundary
  cases while both existing choices retain their complete passing regression behavior.
- **SC-003**: Every documented third-choice user-data read/write is observed to use the required
  stored operation with bound values; zero direct user-data commands or fallback calls occur.
- **SC-004**: With both other implementations excluded, the third choice still completes all
  seven operation groups against an isolated source.
- **SC-005**: Every directed pairing of the three choices observes completed creates, updates
  and deletes on its next read; repeated/concurrent preparation preserves all pre-existing
  records and keeps all three choices usable.
- **SC-006**: With each selected choice, loading feedback appears within one second, supplied
  results of up to 1,000 users become viewable within one second, and closing while work is
  pending produces no late view changes or unhandled failures.
- **SC-007**: Repeatable comparisons identify all three choices and report actual outcomes for
  parity, independence, required-operation use, setup, failures and cleanup without overwriting
  normal data or claiming unavailable checks passed.

## Assumptions

- "Third implementation" carries forward the confirmed full seven-operation scope and the
  user's explicit independence requirement. Neither earlier service is a wrapper, helper
  or prerequisite for the third.
- EF6 with stored procedures is an explicit user requirement. Specific class/choice/procedure
  names, parameter transport for multiple logins and deployment mechanics belong to planning;
  this specification does not select those mechanisms.
- "Only stored procedures" governs all normal user-data reads and writes. Explicit bootstrap
  may create the database and define/install procedures because they must exist before they
  can be called. Provider metadata discovery does not count as user-data access and MUST NOT
  be used to bypass the procedure-only rule.
- Common public contracts, user model and schema definition may be shared. Implementation-specific
  helpers belonging to either earlier service may not be reused by the third service.
- The project constitution and existing desktop compatibility remain applicable. No platform,
  provider or runtime upgrade is requested.
- Setup compatibility assumes the supported existing table layout and login primary key are
  intact. Constraint repair means the existing setup's recreation of missing named check
  constraints; arbitrary schema reconstruction or repair of disabled constraints is outside scope.
- The existing configured source and user identity rules remain authoritative. Setup privileges
  and runtime procedure-execution privileges must be documented separately; no new authentication
  model or normal-account permission changes are requested.
- Existing explicit configuration is preserved. In particular, adding the third choice must not
  overwrite the user's current EntityFramework selection; missing/blank fallback behavior is
  unchanged.
- No new window picker, editing interface, automatic setup, implicit migrations, sample-data
  insertion or performance ranking is requested.
- Existing unexecuted manual desktop acceptance remains unexecuted until it is actually performed.
  This specification creates requirements only; it does not implement or verify the new service.
