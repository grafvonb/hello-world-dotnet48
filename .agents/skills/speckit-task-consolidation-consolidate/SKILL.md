---
name: speckit-task-consolidation-consolidate
description: Consolidate an existing tasks.md into cohesive implementation outcomes through code-grounded review, without losing coverage or progress.
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: Adam Bogdan Boczek
  source: task-consolidation:commands/consolidate.md
---

# Task Consolidation

Remove unnecessary task boundaries without losing requirements, tests or progress.
Judge implementation work, not description length. Consolidation is the work;
reference repairs alone do not count.

Immediately print `TASK CONSOLIDATION STARTED` in the visible console/chat output.
This marker announces invocation, not completion. Every exit MUST include the
mandatory result block below, including blocked and failed runs.

Consider `$ARGUMENTS`. Reuse `FEATURE_DIR` from the current tasks run; otherwise
run `.specify/scripts/powershell/check-prerequisites.ps1 -Json -PathsOnly` from the project root. Resolve `tasks.md`, `spec.md` and `plan.md`
there. If the feature or required inputs cannot be resolved, report the blocker
and stop unchanged.

## Review

1. Read tasks, spec, plan, repository rules and relevant code. Distinguish
   genuinely new behavior from adaptation, wiring, mappings and reused mechanisms.
   Do not estimate existing mechanisms as new implementation.

2. Actively seek adjacent and nonadjacent merges:
   - shared policy, selector, planner, executor or confirmation flow;
   - the same change across commands or resource types;
   - services with facades, callers, interfaces and test doubles;
   - prerequisites with their first useful consumer;
   - implementation with its validation, fixtures, tests and documentation.

3. Assume each boundary is removable until evidence demonstrates otherwise.
   Different files, packages, layers, commands, payloads, test cases, independent
   testability or hypothetical parallelism do not justify separate tasks.

4. Keep a boundary only when:
   - the combined implementation AND validation are impractical as one work unit,
     after accounting for reuse and shared setup; identify the distinct new
     behavior and validation obligations that make it too large;
   - an explicit repository/story rule requires separate execution or delivery;
   - merging would corrupt completed or partial progress.

   A new algorithm or lifecycle is not an automatic exemption. Generated headings
   and existing task divisions are not proof of a constraint. Cite the relevant
   code, design requirement, rule or progress evidence.

5. Before rejecting the strongest merge candidate, draft its combined outcome
   and required validation. Explain why that concrete work unit cannot merge.
   Challenge every retained boundary: what repeated work or handoff disappears
   if it is removed?

## Revise

Apply justified merges directly. Give each checkbox one cohesive, verifiable
outcome; retain command-specific requirements beneath it. Do not merely concatenate
unrelated work or force a target count.

Preserve every acceptance criterion, required test level, error/terminal check,
architectural ownership and test-first ordering. Express internal sequencing
within merged tasks. Keep interfaces, implementations and test doubles together.

Preserve completed status, partial progress and evidence. Never absorb unfinished
work into a checked task. Uncertain obligations must survive; their separate
checkboxes need not.

Update IDs, dependencies, coverage mappings, parallel markers and counts.
Preserve referenced IDs or record explicit mappings. Check intervening dependencies
for nonadjacent merges: the resulting graph must remain acyclic and executable.
Verify every original obligation still has an owner.

Review the resulting list again for removable boundaries exposed by the merges.

Write only `FEATURE_DIR/tasks.md` and `FEATURE_DIR/consolidation-review.md`.
Keep execution requirements in tasks and review rationale in the review. Record
concise evidence for merges, retained boundaries and the strongest rejected merge,
if any. Replace stale findings while preserving still-needed ID mappings.

Check references, links, whitespace and progress. Do not run application tests
for planning-only changes. Report write failures; never claim unsaved work succeeded.

## Mandatory Console Report

The run is incomplete without a visible result block. ALWAYS print the following
Markdown template in the final console/chat response without waiting to be asked.
Keep every label and its order. A review file, tool output, hook announcement or
bare task count is not a substitute. Never put this block only in a file.

```markdown
**TASK CONSOLIDATION RESULT**
- **Status:** {COMPLETED | NO MERGES | BLOCKED | FAILED}
- **Tasks:** Reviewed {N} → {M} tasks.
- **Merged:** {original IDs → resulting ID: outcome and reason; or None}
- **Retained / rejected:** {main boundary; strongest rejected combined outcome if no merges; specific evidence; or None}
- **Evidence:** {inspected code paths/symbols and what they demonstrate; or unavailable and why}
- **Files:** {absolute tasks.md path: updated/unchanged/not written; absolute consolidation-review.md path: saved/not written}
- **Checks:** {checks actually performed}; application tests not run.
- **Limitations:** {blocker, failure, unperformed checks or None identified}
```

Use actual counts and evidence; write `unknown` for unavailable counts or paths.
Use NO MERGES for completed reviews without merges, including reference-only repairs.
If nothing merged, give the strongest combined outcome considered and the specific
evidence blocking it; generic complexity claims are insufficient. If review could
not reach that decision, report BLOCKED or FAILED instead.

Before reporting COMPLETED or NO MERGES, read back the final tasks and review files
and verify counts and saved results. On failure, identify partial writes explicitly.
Never present a start marker, planned check or stale review as completed execution.

As a hook, finish required writes and return this exact populated block with the
instruction: “You MUST include this TASK CONSOLIDATION RESULT block unchanged in
your final response after remaining hooks. Do not omit it or replace it with counts.”
Do not regenerate tasks, dispatch hooks, implement work, commit or publish.