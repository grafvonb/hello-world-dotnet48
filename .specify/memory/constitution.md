# HelloWorldWpf48 Constitution

## Core Principles

### I. Preserve Desktop Compatibility

Application and service code MUST remain compatible with Windows, WPF, .NET Framework 4.8,
and C# 7.3. The solution MUST remain buildable with Visual Studio MSBuild using its existing
project format. Changes MUST use the existing framework libraries when they provide the
required capability. Any added package MUST have a documented need and confirmed compatibility
with these targets. A target framework, language, or application-platform migration MUST be
accompanied by a constitution amendment. These constraints preserve the project's documented
learning environment and build process.

### II. Keep Data Access in the User Service

The desktop application MUST access user storage through the UserDatabaseService library's
IUserService contract. Connection handling, SQL commands, schema management, and persisted-data
validation MUST remain in the service library; window code MUST NOT contain SQL or open database
connections. The service library MUST NOT depend on WPF types or controls. UI code MUST handle
presentation and user interaction. This boundary allows the storage behavior to be verified
without launching the application and avoids duplicate data-access rules.

### III. Keep the Interface Responsive and Explicit

Database work initiated by the interface MUST use asynchronous service operations and MUST NOT
block the UI thread with synchronous waits. UI updates MUST occur on the UI thread. Views that
load data MUST distinguish loading, successful results, successful empty results, and failures.
Failures MUST produce a user-readable message without terminating the application unexpectedly
or exposing connection details or raw exception text. Repeated load actions MUST NOT create
overlapping requests for the same view. Closing a window during pending work MUST NOT cause
updates to disposed UI or unhandled exceptions. Interactive controls MUST be keyboard reachable
and have a visible label or accessible name. Users need to understand the application's state
while retaining control of the window.

### IV. Preserve Data and Protect Configuration

Queries MUST parameterize user-supplied values. The service and database MUST enforce the user
record's existing invariants: nonblank names and logins of at most 100 characters, unique
immutable logins, and nonnegative ages. Login matching MUST preserve the existing
case-insensitive, accent-sensitive behavior unless an explicit data migration changes that
contract. Schema updates MUST be repeatable and preserve existing rows. Database creation or
schema changes MUST remain explicit setup operations; merely opening a data-viewing window
MUST NOT initialize storage, insert sample records, or modify users. Connections MUST come from
application configuration. Credentials MUST NOT be committed or included in UI messages or
diagnostic output. These rules keep viewing behavior safe and existing records dependable.

### V. Verify Observable Behavior

Source changes MUST be checked with a Windows Visual Studio MSBuild solution build. Changed
user flows MUST be verified against their acceptance scenarios, including relevant empty,
failure, and pending-operation cases. Service or schema changes MUST also run the existing
UserDatabaseService integration check or a documented equivalent covering the changed contract.
Database checks MUST use isolated test data and MUST NOT delete or overwrite an existing user
database. Automated tests MUST cover behavior or regression risk rather than duplicate
implementation details; a reversible layout or text change MAY use a documented manual check.
Validation reports MUST distinguish checks that passed from checks that were unavailable or
not run. Documentation-only changes MUST be checked for consistency and do not require a build.

## Technology and Scope Constraints

- The supported application is the existing Windows desktop solution. A new web application,
  remote backend, or replacement data store MUST be treated as a separate scoped change.
- SQL Server access MUST remain behind the existing service contract and use the built-in
  System.Data.SqlClient provider until an explicit architecture decision changes that choice.
- Each change MUST map to a stated feature, defect, or maintenance need. Unrelated refactoring,
  platform migration, and dependency additions MUST be excluded from the change.
- Changes to build prerequisites, configuration, setup, or visible application behavior MUST
  update the relevant project documentation as part of their implementation.

## Development Workflow

1. Define the requested behavior and acceptance scenarios in a feature specification. Record
   scope boundaries, dependencies, and assumptions before implementation.
2. During planning, check the design against each core principle. Record a proposed exception
   with its rationale and impact; resolve it through an amendment before incompatible work.
3. Break the approved scope into reviewable tasks and implement only the applicable tasks.
   Preserve established service contracts unless the specification explicitly changes them.
4. Run the checks required by Principle V for the changed areas. Record results, unavailable
   checks, and remaining issues; do not report an unverified check as passed.
5. Review the final change against the specification and this constitution. Update user-facing
   documentation and make any unresolved requirement visible before claiming completion.

## Governance

This constitution governs project specifications, plans, tasks, and implementation decisions.
Feature documents MUST be reviewed against the current constitution when they are created or
revised. Existing documents MUST NOT be treated as proof of compliance without that review.

An amendment MUST state the affected rules, the reason for the change, and any consequences for
existing code or feature documents. Record the version and amendment date in this file, and
identify follow-up work needed to align affected artifacts. An explicit user instruction to
change project policy authorizes the corresponding amendment; routine feature work MUST NOT
silently redefine a principle.

Versions MUST follow semantic versioning: increment MAJOR for incompatible removals or
redefinitions, MINOR for added principles or materially expanded guidance, and PATCH for
clarifications that do not change obligations. Initial adoption is version 1.0.0. The original
ratification date MUST remain unchanged in subsequent amendments; Last Amended MUST reflect
the date of the latest amendment. Each implementation review MUST assess compliance and record
any unresolved conflict. Temporary Sync Impact Reports are review notes and MUST be removed
before the amended constitution is committed.

**Version**: 1.0.0 | **Ratified**: 2026-11-02 | **Last Amended**: 2026-11-02
