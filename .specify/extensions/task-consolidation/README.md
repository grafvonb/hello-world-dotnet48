# Task Consolidation

Remove unnecessary task boundaries without losing requirements, tests or progress.
Assume boundaries are removable until concrete evidence justifies keeping them.
Seek adjacent and nonadjacent merges around shared behavior, callers, prerequisites,
tests and documentation. Judge implementation work after reuse, not description
length or file counts; do not force a target task count.

Requires an initialized Spec Kit project with an agent integration, standard
scripts, and existing `tasks.md`, `spec.md`, and `plan.md`. Spec Kit **1.2.1** is
the tested baseline; the manifest accepts `>=1.2.1,<1.3.0`.

## Install and migrate

From the target project's root, substitute your clone's absolute path:

```bash
# Only if the old preset is installed: remove it before adding the extension.
specify preset remove task-consolidation
specify extension add --dev /absolute/path/to/spec-kit-extension-task-consolidation
```

Confirm the generated tasks command no longer contains the preset wrapper,
including through other overrides. Keep exactly one consolidation hook.

**Hook order matters:** in `.specify/extensions.yml`, place the existing
`task-consolidation` entry first under `hooks.after_tasks`, before publish/commit
hooks. Keep it enabled, with `optional: false` and no non-empty `condition`.
Spec Kit 1.2.1's tasks template follows YAML order, skips non-empty conditions,
and does not sort by `priority`. Reinstallation can append the hook at the end:
recheck order after installation, reinstall, or other hook changes.

## Use

Run the official `speckit.tasks` as usual: it generates the draft, invokes and
waits for consolidation, handles remaining hooks, then reports completion.
The extension does not wrap, replace, or recursively invoke task generation.

For an existing or already-started list, invoke
`/speckit.task-consolidation.consolidate`, or
`$speckit-task-consolidation-consolidate` in Codex skills mode.
Consolidation updates `tasks.md` directly and saves review findings separately in
`consolidation-review.md`. Only these two files may change. Required work, test
coverage and ordering, architectural ownership, explicit repository/story rules,
completed status and partial progress are preserved. Referenced IDs are retained
or explicitly mapped; dependencies and parallel markers are updated.

Retained boundaries require evidence that the combined implementation and validation
are impractical, an explicit rule requires separate execution or delivery, or a
merge would corrupt progress. A new algorithm or lifecycle alone is insufficient.
Before rejecting the strongest candidate, the agent drafts its combined outcome
and validation. After merging, it reviews the resulting list again.

Every invocation prints `TASK CONSOLIDATION STARTED`, then MUST print a fixed
`TASK CONSOLIDATION RESULT` block in the final console/chat response, including
no-merge, blocked and failed runs. Saving a review file or announcing a hook is
not a substitute. The report always includes these labels in this order:

```markdown
**TASK CONSOLIDATION RESULT**
- **Status:** COMPLETED
- **Tasks:** Reviewed 8 → 7 tasks.
- **Merged:** T003 + T004 → T003: service operation and its delegating facade.
- **Retained / rejected:** T002 is completed; absorbing unfinished T003 would corrupt progress.
- **Evidence:** src/facade.py: Facade.execute only delegates; no separate behavior to implement.
- **Files:** /project/specs/001-feature/tasks.md: updated; /project/specs/001-feature/consolidation-review.md: saved
- **Checks:** requirement ownership, dependencies, references, IDs, progress, whitespace and saved-file readback; application tests not run.
- **Limitations:** None identified
```

This is an illustrative report, not evidence of a real run. Status is `COMPLETED`,
`NO MERGES`, `BLOCKED` or `FAILED`; unavailable counts and paths are `unknown`.
Successful reviews require reading back both final files to verify counts and results.
Failures identify partial writes. If nothing merges, the report shows the strongest
combined outcome considered and the specific evidence blocking it. Reference
repairs alone are not consolidation.

The review records current findings and preserves still-needed ID mappings.
Consolidation does not implement tasks or run application tests. Required writes
finish before returning to downstream hooks. The hook requires the parent to include
the populated result block unchanged in its final response after remaining hooks.

## Reinstall or remove

Source edits do not update installed commands automatically. Reinstall with:

```bash
specify extension add --dev /absolute/path/to/spec-kit-extension-task-consolidation --force
```

Recheck hook order afterward. To uninstall:

```bash
specify extension remove task-consolidation
```

## Validation and limits

Spec Kit 1.2.1 installation, reinstall, removal and migration checks passed.
Earlier same-session trials covered execution, ordering, preservation and stability;
they predate the v0.5.0 merge-first instructions. These instructions have not yet
been evaluated in an independent consolidation run.
Independent agent sessions and PowerShell/Python execution remain untested.
Registration success alone does not prove behavioral effectiveness.

Execution is agent-driven. Mandatory hooks require actual invocation and waiting;
malformed hook YAML currently warns and allows the parent to continue. Correct
hook ordering must be established before running tasks.
