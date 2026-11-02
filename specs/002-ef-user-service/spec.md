# Feature Specification: Parallel User Service for Comparison

**Feature Branch**: `002-ef-user-service`

**Created**: 2026-11-02

**Status**: Draft

**Input**: User description: "provide same functionality for user list in userdatabase service but implemented using entity framework do not remove first implementation keep both for comparity reasons bit"

## Clarifications

### Session 2026-11-02

- Q: Should the Entity Framework implementation cover the full existing user service or only retrieval operations? → A: Full service: setup, all retrieval operations, create, update, and delete.

- User correction: EfUserService must remain buildable and runnable if SqlUserService.cs is
  deleted. Setup and connection validation must be implemented independently; no wrapper or composition.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read the Same Users Through Either Implementation (Priority: P1)

As a developer comparing data-access approaches, I want the new implementation to return the
same users as the original so that I can compare their behavior against existing data.

**Why this priority**: A second implementation is useful only if it can read the existing records
without replacing or changing the original implementation.

**Independent Test**: Prepare a known collection, retrieve it through each implementation, and
compare all returned values, ordering, filtered results, and missing-user outcomes.

**Acceptance Scenarios**:

1. **Given** prepared storage containing users, **When** either implementation retrieves all users,
   **Then** both return the same Name, Login, and Age values, once per user, in the existing login order.
2. **Given** empty prepared storage, **When** either implementation retrieves all users,
   **Then** both return a successful empty collection without creating sample data.
3. **Given** mixed-case, accented, and whitespace-padded login inputs, **When** a single or
   multiple-login lookup runs through either implementation, **Then** both preserve the existing
   trimming, case-insensitive and accent-sensitive matching, unique-result, and ordering behavior.
4. **Given** missing logins or an empty multiple-login selection, **When** either implementation
   performs the lookup, **Then** a missing single user has the existing not-found result and
   multiple-user retrieval returns only existing matches or an empty collection.
5. **Given** one implementation has completed a change, **When** the other subsequently reads
   that user, **Then** it sees the completed change without copying or synchronizing separate records.

---

### User Story 2 - Preserve Existing Service Behavior (Priority: P2)

As a developer using the user service, I want either implementation to support the same existing
operations and validation rules so that choosing one does not change how callers manage users.

**Why this priority**: Matching only the displayed list would leave the new implementation
incomplete as a substitute for the current service.

**Independent Test**: Run the same isolated setup, create, read, update, delete, invalid-input,
duplicate-login, not-found, and cancellation scenarios against each implementation.

**Acceptance Scenarios**:

1. **Given** valid user details, **When** either implementation creates, updates, or deletes a user,
   **Then** persisted values, trimming, immutable login identity, and success/not-found outcomes match.
2. **Given** invalid user details, invalid lookup inputs, or a duplicate login,
   **When** either implementation receives the operation,
   **Then** it produces the same caller-visible validation or duplicate-login outcome without
   partially saving the rejected operation.
3. **Given** absent or already prepared storage, **When** explicit setup runs through either
   implementation, **Then** it creates missing storage or applies the existing repeatable
   updates while preserving records and the existing data constraints.
4. **Given** setup is repeated or requested concurrently, **When** the calls complete successfully,
   **Then** storage remains valid and existing records are preserved.
5. **Given** a canceled request or unavailable/denied storage, **When** either implementation
   performs an operation, **Then** callers can distinguish cancellation or failure from a
   successful empty/not-found result, without new incompatible error handling.

---

### User Story 3 - Choose and Compare Without Losing the Original (Priority: P2)

As a developer learning from both approaches, I want to choose either implementation and run
the same application and comparison checks so that both remain usable in one project.

**Why this priority**: Retaining source alone is insufficient if the original can no longer be
selected or the new implementation cannot be exercised through the existing application.

**Independent Test**: Run the application once with the default option and once with the
explicit alternative; run the documented shared behavior checks against both.

**Acceptance Scenarios**:

1. **Given** no implementation override is configured,
   **When** the application starts, **Then** it uses the original implementation.
2. **Given** the documented alternative is configured,
   **When** the application starts, **Then** the same main-window list uses the new implementation
   with unchanged populated, loading, empty, safe-failure, Retry, and shutdown behavior.
3. **Given** an unrecognized implementation choice,
   **When** the application starts, **Then** it stays open with configuration-related feedback
   rather than silently choosing a different option.
4. **Given** either choice is selected, **When** the application loads users,
   **Then** it uses the same configured user storage without initializing it or changing user data.
5. **Given** the comparison instructions, **When** a developer runs the shared checks,
   **Then** each result identifies the selected implementation and reports matching outcomes
   or specific differences; all test writes remain confined to owned fixtures.

### Edge Cases

- Duplicate names remain separate users; age zero, Unicode, and 100-character text are preserved.
- Logins differing only by case identify the same user; accented characters retain existing distinctions.
- Null, blank, or overlength values and negative ages preserve the existing rejection behavior.
- Multiple-login lookup retains the existing limit of 2,000 distinct trimmed input values;
  repeated inputs resolving to one user never duplicate its returned record.
- Updating or deleting an absent user preserves the existing not-found outcome.
- A duplicate-login race cannot create duplicate identities or bypass the existing duplicate outcome.
- Reads reflect completed writes made through the other implementation; retained state cannot
  silently return an older version of a user.
- Cancellation remains observable as cancellation. No stronger rollback guarantee after a
  write has already completed is introduced.
- Unprepared or inaccessible storage is a failure, not an empty collection; normal reads do
  not create storage or additional application-managed tables.
- Closing during a pending load or Retry remains safe for either choice.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The service MUST retain the original implementation and add a separately selectable
  Entity Framework implementation for comparison. Both MUST remain directly usable by existing consumers.
- **FR-002**: EfUserService MUST be completely independent of SqlUserService for all seven
  operations, including connection validation and explicit setup. It MUST NOT construct,
  reference or delegate to SqlUserService. Removing SqlUserService.cs MUST leave the EF service
  buildable and runnable with its shared contracts, model, schema resource and EF support classes.
  Keep the original SqlUserService class implementation unchanged; shared exception contracts
  MUST live outside either implementation file.
- **FR-003**: Both implementations MUST support the full existing service contract: explicit storage
  setup/update, retrieve-all, single-login retrieval, multiple-login retrieval, create, update,
  and delete, without breaking existing callers.
- **FR-004**: Both implementations MUST use the same existing user storage and identity rules,
  with no separate user copies, data conversion requirement, new user fields, or loss of existing records.
- **FR-005**: Both implementations MUST return matching user fields, source ordering, lookup
  matching, missing-user outcomes, empty results, unique filtered results, and the existing
  multiple-login input limit.
- **FR-006**: Both implementations MUST preserve validation, trimming, immutable login identity,
  uniqueness, nonnegative age, duplicate-login handling, and update/delete success or not-found
  outcomes. Rejected operations MUST NOT partially save changes.
- **FR-007**: Explicit setup through either implementation MUST preserve existing records and
  constraints, be repeatable, and support the existing concurrent-setup behavior. Reading users
  or opening the application MUST NOT initialize or migrate storage or insert demonstration data.
- **FR-008**: Both implementations MUST preserve asynchronous operation and cancellation support.
  The application MUST remain responsive while loading and safe to close with work pending.
- **FR-009**: Callers MUST retain compatible handling of validation failures, duplicate logins,
  cancellation, and storage failures. The application MUST preserve safe failure categories,
  Retry behavior, and the exclusion of raw exception and connection details from its messages.
- **FR-010**: A documented configuration choice MUST select the application's implementation.
  The original MUST remain the default; invalid choices MUST produce configuration feedback.
- **FR-011**: Subsequent reads through either implementation MUST reflect completed changes
  made through the other; selecting an implementation MUST NOT require separate initialization,
  copying, or synchronization of records.
- **FR-012**: The project MUST provide repeatable behavior-comparison checks and usage
  instructions for both implementations. Checks MUST identify the selected option, cover all
  existing operations and boundary outcomes, use isolated owned test data, and report results
  without claiming unexecuted checks passed.

### Key Entities *(include if feature involves data)*

- **User**: The existing person record: required nonblank Name and Login, each at most 100
  characters, and required nonnegative Age. Login is the immutable unique identity with the
  existing case-insensitive, accent-sensitive semantics. Names may be duplicated.
- **Implementation Choice**: The developer-selected data-access option for the existing
  application or comparison run. It changes behavior's implementation, not the user records,
  connection destination, or access permissions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For unchanged acceptance collections of 0, 1, and 1,000 users, both choices
  return identical field values and ordering for 100% of records and matching filtered/not-found results.
- **SC-002**: The shared comparison checks exercise all seven existing service operations;
  100% of defined valid-input, invalid-input, duplicate, missing-record, and cancellation
  scenarios have matching caller-visible outcomes.
- **SC-003**: In both directions, records created, updated, or deleted through one choice are
  reflected by the next read through the other. Repeated and concurrent successful setup
  checks preserve 100% of existing fixture records and their constraints.
- **SC-004**: Application acceptance runs for each choice cover populated, empty, failure,
  Retry, and close-during-load states with zero unexpected terminations and zero writes caused
  by list viewing or implementation selection.
- **SC-005**: Existing consumers continue using the original option without code changes,
  and 100% of existing regression checks applicable to the original behavior still pass.
  A comparison run reports separate results for both choices and zero changes to normal user data.

## Assumptions

- Confirmed scope: both implementations cover the full existing user-service contract,
  including setup, all retrieval operations, create, update, and delete. The desktop UI
  remains a read-only list.
- Entity Framework is the explicitly requested alternative, and the existing ADO.NET
  SqlUserService is retained. These names identify the user's technology requirement and
  existing dependency; package version and internal design belong to planning.
- Both implementations satisfy the existing IUserService integration contract and use the
  existing User model, UserDatabase connection, SQL Server storage, and login collation.
- Configuration-based selection is sufficient for comparison. A new on-screen implementation
  picker, simultaneous duplicate lists, performance-ranking dashboard, authentication flow,
  or different database backend is outside this feature.
- The requested comparison supplies the need for the additional dependency. Planning must
  verify compatibility with .NET Framework 4.8, C# 7.3, classic project builds, and the current
  provider constraints; no framework or language migration is requested.
- Explicit setup remains the only operation allowed to prepare or update storage. No automatic
  destructive initialization or extra application-managed storage is required by the alternative.
- Failure compatibility means existing callers retain their documented handling and user-visible
  categories; raw internal exception wording and stack traces need not match.
- The feature preserves existing window acceptance requirements and does not claim the new
  implementation is faster. A formal performance benchmark is outside this comparison.
- The earlier feature's outstanding manual keyboard/visual check remains outstanding; this
  specification does not convert it into a passed check.
