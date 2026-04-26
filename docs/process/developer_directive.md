# Keystone86 / Aegis — Developer Directive

## Purpose

This file is the short front-door directive for normal development work.

It exists so handoff messages can stay brief while still pointing to the full project process expectations.

Before starting work, the developer must read the process files referenced below.

---

## Required reading

Read these files before starting:

- For Codex-based rung work, read `AGENTS.md` first and follow
  `docs/process/codex_workflow.md`.
- `docs/process/developer_handoff_contract.md`
- `docs/process/rung_execution_and_acceptance.md`
- `docs/process/tooling_and_observability_policy.md`
- `docs/implementation/coding_rules/source_of_truth.md`
- `docs/implementation/coding_rules/review_checklist.md`

These files define:

- what counts as review-ready
- how rung work must be scoped and validated
- Makefile / aggregate command / debug expectations
- current source-of-truth and implementation ownership expectations for the repo

---

## Primary instruction

Work only from the current committed/pushed repository state or from the package explicitly provided for this request.

Review the current repo state first before making changes.

Do not widen scope beyond the specific rung or task requested.

---

## Functional-work rule

For normal rung work:

- functionality first
- cleanup later

Do **not** perform unrelated cleanup unless the request explicitly asks for it.

That includes:

- cosmetic cleanup
- restructuring directories
- package/include cleanup
- Makefile cleanup
- debug-framework work
- Python-generation cleanup
- README modernization
- future-rung expansion

---

## Architectural rule

Preserve the frozen ownership boundaries.

In particular:

- decoder remains classification / byte-consumption logic
- microsequencer remains control owner
- commit path remains architectural visibility boundary
- helper logic must not silently become policy owner
- important architectural distinctions must not be collapsed into overloaded signals

This is a microcoded design.

Instruction behavior must remain microcode / microsequencer driven.

That means:

- decoder must not become a hidden per-opcode execution engine
- commit logic must not become a hidden per-instruction semantic owner
- helper RTL must not embed instruction semantics that belong in dispatch or microcode-controlled execution
- instruction-support growth must not be implemented as hard-coded RTL behavior

The reason is architectural and practical: instruction semantics must remain patchable through dispatch and microcode-controlled execution.

If instruction behavior is implemented in RTL instead of dispatch/microcode-controlled execution, many CPU bugs can no longer be corrected by microcode update alone.

That is not acceptable for this project.

A design that moves instruction semantics into RTL is drifting away from a repairable microcoded CPU and toward fixed hard-coded silicon behavior.

Such drift must be rejected.

If a change adds, expands, or materially alters instruction behavior, the corresponding dispatch selection and/or microcode source/content must be updated to carry that behavior.

For normal rung work, it is not acceptable to add or change instruction behavior while leaving dispatch selection and microcode source/content unchanged.

A handoff that changes instruction behavior without corresponding dispatch/microcode-content change is not review-ready and must be rejected.

Do not bypass architecture just to make a test pass.

---

## Review-ready rule

Do not send intermediate fix attempts.

Iterate privately until the requested work is actually ready for review.

Do not label a package as:

- passing
- fixed
- complete
- ready for review

unless the required verification commands were actually run against the exact state being handed off.

---

## Required handoff standard

Every handoff must follow `docs/process/developer_handoff_contract.md`.

At minimum, that means the handoff must include:

- `Status: READY FOR REVIEW` or `Status: NOT READY FOR REVIEW`
- base commit used
- exact changed/new file manifest
- repo-relative file paths
- full replacement files where needed
- exact verification commands run
- actual results
- explicit deferred items

Do not send a full repo snapshot unless explicitly requested.

For normal work, send only:

- modified files
- newly created files

Optionally, include a zip containing only those changed/new files with repo-relative paths preserved.

---

## Validation rule

Before claiming completion, run the relevant verification commands and report the actual results.

Do not report inferred success.
Do not report expected success.
Do not report “should pass.”

Report only what actually ran.

---

## Debug rule

If debugging is needed:

- trace the first incorrect internal value
- identify where corruption begins
- propose the minimal fix
- prove the fix with actual rerun results

Keep useful debug instrumentation until the failing path is visibly corrected.

---

## Summary

Default behavior for this project:

- read the current repo first
- stay within the requested scope
- preserve architecture
- keep instruction semantics microcode-driven and patchable
- reject RTL-only instruction-semantic growth
- iterate until genuinely review-ready
- hand back only validated changed/new files
- report exact commands and actual results
