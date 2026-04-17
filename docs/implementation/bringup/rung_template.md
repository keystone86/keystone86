# Keystone86 / Aegis — Rung <N> Bring-Up Scope

## Purpose

This file defines the functional scope and proof target for Rung <N> bring-up.

Read `docs/process/developer_directive.md` first.

That directive defines the general development rules for this project, including scope control, handoff requirements, validation discipline, anti-drift expectations, and required reading.

This file defines **what Rung <N> is**, **what it must prove**, and **what remains out of scope**.

---

## Rung <N> intent

Rung <N> is the <short rung name> rung.

It builds on the proven baseline from the prior rung(s).

Rung <N> is functional implementation work, not cleanup.

Rung <N> must be treated as a **complete integrated slice**, not as isolated opcode recognition or partial structural progress. The rung is only complete when the required decode, control, data-path, microcode/service, and commit-visible behavior work together to produce the intended architectural result.

---

## In scope

Rung <N> covers the minimum integrated functional slice needed to prove correct <short behavior name> behavior as a working system.

That includes:

- `<opcode/form 1>`
- `<opcode/form 2>`
- `<opcode/form 3>`
- minimum decode support required for the in-scope forms
- minimum data-path behavior required for correctness
- microcode/service support needed to complete the in-scope flows
- commit-visible architectural effects needed to prove correctness
- required proof behavior within the defined acceptance cases

Rung <N> includes whatever narrowly scoped support is genuinely required to make that slice function correctly end to end.

---

## Out of scope

Unless explicitly requested, Rung <N> does **not** include:

- unrelated cleanup
- directory restructuring
- package/include cleanup unrelated to this rung
- Makefile cleanup unrelated to this rung
- debug-framework redesign
- Python-generation cleanup unrelated to this rung
- README modernization unrelated to the requested handoff
- unrelated instruction-family bring-up
- broader architectural expansion beyond this rung’s slice
- speculative future-rung preparation
- pre-implementation of Rung <N+1> or later behavior
- generic framework work intended mainly for later rungs

Rung <N> should be expanded only enough to make the intended system slice work and be provable.

---

## Architectural constraints

Rung <N> must preserve the frozen ownership boundaries.

In particular:

- decoder remains classification / byte-consumption logic
- microsequencer remains control owner
- commit path remains architectural visibility boundary
- helper logic must not silently become policy owner
- important architectural distinctions must not be collapsed into overloaded signals

Do not bypass architecture just to make a test pass.

If an apparent fix requires architectural boundary smearing, stop and surface that explicitly in the handoff.

---

## Required behavior

Rung <N> is not complete because decode exists.

Rung <N> is complete only when the requested slice works behaviorally as an integrated system.

The required proof points are:

- `<proof point 1>`
- `<proof point 2>`
- `<proof point 3>`
- `<proof point 4>`
- decode, control, data-path, microcode/service, and commit-visible behavior agree on the same architectural result

Partial structural progress is not sufficient. Rung <N> must prove working architectural behavior.

---

## Minimum implementation surfaces

The exact RTL changes are determined by the current repo state, but Rung <N> should be expected to touch only the surfaces genuinely needed for the intended slice.

That may include:

- decoder classification for the in-scope forms
- microsequencer control flow for the required entry points
- data-path support needed for the required effects
- commit-visible state updates required for architectural correctness
- targeted microcode/service support required to complete the sequence

These surfaces are in scope only to the extent required to make Rung <N> function correctly as a system.

Do not broaden implementation beyond what these behaviors require.

---

## Acceptance criteria

Rung <N> is ready for review only when all of the following are true:

- the in-scope forms are implemented
- the required decode support is correct
- the required data-path effects are correct
- the required control/microcode path completes correctly
- the commit-visible architectural result is correct
- the required proof cases have been run
- the actual verification results are reported
- preserved baseline behavior from earlier rungs remains intact

Rung <N> is not complete until the integrated system slice works together and is proven.

---

## Validation expectations

Use the validation and handoff rules from `docs/process/developer_directive.md`.

Where applicable, validation for Rung <N> should include:

- required generation steps for local-only generated artifacts
- targeted proof cases for the in-scope behavior
- broader regression checks needed to show the preserved baseline still holds

Typical prerequisite steps may include:

- `make codegen`
- `make ucode`

Typical proof should include:

- `<targeted proof case 1>`
- `<targeted proof case 2>`
- `<targeted proof case 3>`

Report only what actually ran.

---

## Summary

Rung <N> is the <short rung name> rung.

Its job is to prove correct <short behavior name> behavior, including the minimum integrated decode, control, data-path, microcode/service, and commit-visible support required to make the slice work as a system, while preserving the established architecture and avoiding unrelated expansion.