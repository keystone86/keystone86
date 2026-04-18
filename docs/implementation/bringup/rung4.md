# Keystone86 / Aegis — Rung 4 Bring-Up Scope

## Purpose

This file defines the functional scope and proof target for Rung 4 bring-up.

Read `docs/process/developer_directive.md` first.

That directive defines the general development rules for this project, including scope control, handoff requirements, validation discipline, anti-drift expectations, and required reading.

This file defines **what Rung 4 is**, **what it must prove**, and **what remains out of scope**.

---

## Rung 4 intent

Rung 4 is the Jcc bring-up rung.

It is the first rung that must prove conditional control transfer based on architectural flags, building on the proven Rung 2 near-JMP redirect baseline and the broader control-flow integration established through Rung 3.

Rung 4 is functional implementation work, not cleanup.

Rung 4 must be treated as a **complete integrated slice**, not as isolated opcode recognition. The rung is only complete when the required decode, condition evaluation, control flow, microcode, and commit-visible behavior work together to produce correct architectural short conditional branch behavior.

---

## In scope

Rung 4 covers the minimum integrated functional slice needed to prove correct short Jcc behavior as a working system.

That includes:

- short conditional branches `70h`–`7Fh`
- all 16 condition codes represented by those opcodes
- decode support required to classify short Jcc forms
- condition-code propagation required to preserve the architectural meaning of each Jcc form
- minimum condition-evaluation support required to decide taken vs not-taken behavior from the relevant architectural flags
- control-flow support required to apply the signed 8-bit displacement when the branch is taken
- not-taken flow behavior that correctly falls through to the next architectural instruction
- microcode support needed to complete the Jcc flow
- commit-visible control-transfer effects needed to prove correct architectural EIP update and prefetch behavior
- required proof behavior for taken and not-taken cases across the defined acceptance set

Rung 4 includes whatever narrowly scoped support is genuinely required to make that Jcc slice function correctly end to end.

---

## Out of scope

Unless explicitly requested, Rung 4 does **not** include:

- unrelated cleanup
- directory restructuring
- package/include cleanup unrelated to Jcc bring-up
- Makefile cleanup unrelated to Jcc bring-up
- debug-framework redesign
- Python-generation cleanup unrelated to Jcc bring-up
- README modernization unrelated to the requested handoff
- near/long Jcc expansion beyond the in-scope short conditional forms
- LOOP/LOOPE/LOOPNE/JCXZ family bring-up
- INT/IRET bring-up
- broader flags-production redesign beyond what is required to consume already established architectural flags correctly
- speculative future-rung preparation
- pre-implementation of Rung 5+ behavior
- generic framework work intended mainly for later rungs

Rung 4 should be expanded only enough to make the Jcc system slice work and be provable.

---

## Architectural constraints

Rung 4 must preserve the frozen ownership boundaries.

In particular:

- decoder remains classification / byte-consumption logic
- microsequencer remains control owner
- condition evaluation must not be hidden inside unrelated helper logic
- commit path remains architectural visibility boundary
- helper logic must not silently become policy owner
- important architectural distinctions between condition-code selection, flag state, and transfer outcome must not be collapsed into overloaded signals

Do not bypass architecture just to make a Rung 4 test pass.

If an apparent fix requires architectural boundary smearing, stop and surface that explicitly in the handoff.

---

## Required behavior

Rung 4 is not complete because decode exists.

Rung 4 is complete only when the requested Jcc slice works behaviorally as an integrated system.

The required proof points are:

- each short Jcc opcode maps to the correct architectural condition
- the selected condition is evaluated against the correct architectural flag state
- taken Jcc applies the correct signed 8-bit displacement from the correct next architectural EIP / `M_NEXT_EIP`
- not-taken Jcc falls through to the correct next architectural EIP / `M_NEXT_EIP`
- EIP is correct for both taken and not-taken outcomes
- prefetch/control-transfer behavior is correct for taken branches
- branch direction works correctly for both forward and backward short displacements within the defined proof cases
- all 16 condition codes are proven in both taken and not-taken cases
- decode, condition evaluation, control flow, microcode, and commit-visible behavior agree on the same architectural result

Partial structural progress is not sufficient. Rung 4 must prove working architectural behavior.

---

## Minimum implementation surfaces

The exact RTL changes are determined by the current repo state, but Rung 4 should be expected to touch only the surfaces genuinely needed for the Jcc slice.

That may include:

- decoder classification for the in-scope Jcc forms
- condition-code metadata generation/transport for the in-scope forms
- control-path condition evaluation needed to resolve taken vs not-taken behavior
- microsequencer control flow for the Jcc entry point
- commit-visible EIP update / redirect behavior required for architectural correctness
- targeted prefetch flush / fall-through handling required to complete the sequence

These surfaces are in scope only to the extent required to make Rung 4 function correctly as a system.

Do not broaden implementation beyond what these behaviors require.

---

## Acceptance criteria

Rung 4 is ready for review only when all of the following are true:

- the in-scope short Jcc forms are implemented
- the required decode support for those forms is correct
- all 16 architectural conditions are represented correctly
- taken and not-taken behavior is correct for the required proof cases
- signed 8-bit displacement handling is correct
- the required microcode/control path completes correctly
- the commit-visible architectural result is correct
- the required proof cases have been run
- the actual verification results are reported
- preserved baseline behavior from earlier rungs remains intact

Rung 4 is not complete until the integrated Jcc slice works together and is proven.

---

## Validation expectations

Use the validation and handoff rules from `docs/process/developer_directive.md`.

Where applicable, validation for Rung 4 should include:

- required generation steps for local-only generated artifacts
- targeted Jcc proof cases
- broader regression checks needed to show the preserved baseline still holds

Typical prerequisite steps may include:

- `make codegen`
- `make ucode`

Typical proof should include:

- each of the 16 short Jcc conditions in a taken case
- each of the 16 short Jcc conditions in a not-taken case
- forward short-branch correctness
- backward short-branch correctness
- fall-through correctness for not-taken Jcc

Report only what actually ran.

---

## Summary

Rung 4 is the Jcc bring-up rung.

Its job is to prove correct short conditional branch behavior, including the minimum integrated decode, condition evaluation, control-flow, microcode, and commit-visible support required to make the slice work as a system, while preserving the established architecture and avoiding unrelated expansion.