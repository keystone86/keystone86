# Keystone86 / Aegis — Developer Handoff Contract

## Purpose

This document defines what a valid handoff looks like for this project.

Every handoff — whether from a human developer, an AI assistant, or any other contributor — must meet this standard before being presented as ready for review.

---

## Required reading before any handoff

Read these files before starting work:

- `docs/process/developer_handoff_contract.md` (this file)
- `docs/process/rung_execution_and_acceptance.md`
- `docs/process/tooling_and_observability_policy.md`
- `docs/implementation/coding_rules/source_of_truth.md`
- `docs/implementation/coding_rules/review_checklist.md`

For cleanup passes, also read:

- `docs/process/post_rung2_cleanup_plan.md`

---

## Handoff status line

Every handoff must begin with one of:

```
Status: READY FOR REVIEW
```

or

```
Status: NOT READY FOR REVIEW
```

Do not send intermediate work. Do not label work as ready unless the verification commands were actually run against the exact state being handed off.

---

## Required handoff contents

Every handoff must include:

- **Status line** — READY FOR REVIEW or NOT READY FOR REVIEW
- **Base commit** — the exact commit the work was based on
- **Changed/new file manifest** — repo-relative paths for every modified or new file
- **Verification commands run** — the exact commands executed, not inferred
- **Actual results** — what the commands actually printed, not what they were expected to print
- **Deferred items** — anything intentionally left out, and why

Do not report inferred success. Do not report expected success. Do not report "should pass." Report only what actually ran.

---

## File delivery format

For normal work, send only:

- modified files
- newly created files

Do not send a full repo snapshot unless explicitly requested.

Optionally, include a zip containing only the changed/new files with repo-relative paths preserved inside the archive root.

---

## What "not ready" means

If a handoff is NOT READY FOR REVIEW, it must still include:

- what was attempted
- what is blocking completion
- what the next step is

A NOT READY handoff is not a failure — it is an honest status report. An inaccurate READY claim is a failure.

---

## Scope discipline

Every handoff must stay within the scope it was given.

Do not use a cleanup handoff to introduce new functionality. Do not use a bug-fix handoff to widen scope. Do not mix implementation with cleanup. If scope creep is discovered during work, flag it as a deferred item rather than absorbing it silently.

---

## Rung discipline

Do not claim a rung is passing unless all of the following are true:

1. The rung's acceptance criteria (defined in `docs/spec/frozen/appendix_d_bringup_ladder.md`) are met.
2. The rung's simulation testbench passes with zero failures.
3. All prior rungs still pass.
4. The verification commands were run against the exact committed state.

See `docs/process/rung_execution_and_acceptance.md` for the full rung gate process.

---

## Validation rule

Before claiming any work is complete:

1. Run the relevant verification commands from repo root.
2. Record the exact commands and their exact output.
3. Include both in the handoff.

The following are not acceptable substitutes for actual verification results:

- "should pass"
- "expected to pass"
- "passes based on the changes made"
- any inference without execution

---

## Summary

A valid handoff is:

- clearly labeled READY or NOT READY
- based on a known commit
- accompanied by exact changed files
- verified by commands that were actually run
- honest about what was deferred
