# Keystone86 / Aegis — Developer Handoff Contract

## Purpose

This file defines the minimum required structure for a developer handoff.

A handoff is not review-ready unless it contains the required information in a form that allows direct inspection, reproduction, and validation.

---

## Core rule

Do not claim completion from intent, partial progress, or inferred behavior.

A handoff is review-ready only when it reflects:

- the exact changed state
- the exact files changed
- the exact commands run
- the actual observed results

---

## Required status line

Every handoff must begin with one of:

- `Status: READY FOR REVIEW`
- `Status: NOT READY FOR REVIEW`

Do not use softer substitutes.

Do not imply readiness indirectly.

---

## Required handoff contents

Every handoff must include all of the following.

### 1. Base state

State the exact base used for the work:

- base commit hash, if working from the repo
- or explicit package/bundle name, if working from a provided package

### 2. Scope summary

State what was requested and what was attempted.

Keep this short and concrete.

### 3. Changed file manifest

List every modified or newly created file using repo-relative paths.

Do not omit generated artifacts if they are part of the delivered change set.

Do not include untouched files.

### 4. Full file delivery

Provide full replacement content for all changed/new source and document files unless a different delivery format was explicitly requested.

Do not provide partial patch fragments unless explicitly requested.

### 5. Verification commands

List the exact commands run against the exact handoff state.

Examples:

- `make codegen`
- `make ucode`
- `make test`
- targeted simulation/test commands used for rung proof

### 6. Actual verification results

State what actually happened when those commands ran.

Acceptable examples:

- pass
- fail
- pass with warnings
- specific failing test names
- specific observed mismatch

Do not report:

- expected pass
- should pass
- likely pass
- not rerun but unchanged
- inferred pass from prior state

### 7. Deferred items

List anything intentionally not completed.

If nothing is deferred, say so explicitly.

---

## Architectural accounting requirement

This project is a microcoded design.

Instruction behavior must remain dispatch/microcode controlled and patchable through microcode-driven execution.

Therefore, any handoff that adds, expands, or materially changes instruction behavior must explicitly show the corresponding control-source change.

That means the handoff must identify the relevant updates in one or both of:

- dispatch selection
- microcode source/content

It is not acceptable to grow instruction behavior only in RTL while leaving dispatch selection and microcode source/content unchanged.

A handoff that changes instruction behavior without corresponding dispatch/microcode-content change is not review-ready and must be rejected.

Do not hide instruction semantics in decoder-side logic, commit-side logic, or helper RTL.

---

## Validation integrity rule

The handoff must describe only work that was actually validated from the delivered state.

If the code changed after the last validation run, the prior run does not count for the final handoff.

Rerun the relevant validation and report the new result.

---

## Packaging rule

Do not send a full repository snapshot unless explicitly requested.

For normal work, send only:

- changed files
- newly created files

If a zip is included, it must preserve repo-relative paths and contain only the changed/new files unless a full snapshot was explicitly requested.

---

## Not-ready rule

Use `Status: NOT READY FOR REVIEW` when:

- required validation was not run
- validation failed
- architectural drift remains unresolved
- file delivery is incomplete
- instruction behavior changed without corresponding dispatch/microcode-content change
- the requested scope was not actually completed

Do not present a not-ready package as if it is nearly complete.

Be explicit.

---

## Minimal handoff template

Use this structure:

Status: READY FOR REVIEW

Base:
- `<commit hash or package name>`

Scope:
- `<one short paragraph>`

Changed files:
- `path/to/file_a`
- `path/to/file_b`

Control-source accounting:
- dispatch change: `<path and short note>` or `none`
- microcode source/content change: `<path and short note>` or `none`

Verification run:
- `<exact command>`
- `<exact command>`

Verification results:
- `<actual result>`
- `<actual result>`

Deferred:
- `none`