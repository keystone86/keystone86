# Keystone86 / Aegis — Rung 3 Bring-Up Scope

## Purpose

This file defines the functional scope and proof target for Rung 3 bring-up.

Read `docs/process/developer_directive.md` first.

That directive defines the general development rules for this project, including scope control, handoff requirements, validation discipline, anti-drift expectations, and required reading.

This file defines **what Rung 3 is**.

---

## Rung 3 intent

Rung 3 is the CALL/RET bring-up rung.

It is the first rung that must prove correct stack-touching control flow beyond the Rung 2 redirect/jump baseline.

Rung 3 is functional implementation work, not cleanup.

---

## In scope

Rung 3 covers the minimum functional slice needed to prove correct near CALL/RET behavior.

That includes:

- direct near CALL (`E8`)
- indirect near CALL (`FF /2`)
- near RET (`C3`)
- near RET with immediate stack adjustment (`C2`)
- minimum push/pop support needed for CALL/RET correctness
- microcode support needed to complete CALL/RET flows
- commit-visible control/stack effects needed to prove correct return flow

---

## Out of scope

Unless explicitly requested, Rung 3 does **not** include:

- unrelated cleanup
- directory restructuring
- package/include cleanup unrelated to CALL/RET bring-up
- Makefile cleanup unrelated to CALL/RET bring-up
- debug-framework redesign
- Python-generation cleanup unrelated to CALL/RET bring-up
- README modernization unrelated to the requested handoff
- JCC bring-up
- broader control-transfer family work beyond the CALL/RET slice
- general stack-engine redesign beyond what CALL/RET requires
- speculative future-rung preparation
- pre-implementation of Rung 4+ behavior

---

## Architectural constraints

Rung 3 must preserve the frozen ownership boundaries.

In particular:

- decoder remains classification / byte-consumption logic
- microsequencer remains control owner
- commit path remains architectural visibility boundary
- helper logic must not silently become policy owner
- important architectural distinctions must not be collapsed into overloaded signals

Do not bypass architecture just to make a Rung 3 test pass.

If an apparent fix requires architectural boundary smearing, stop and surface that explicitly in the handoff.

---

## Required behavior

Rung 3 is not complete because decode exists.

Rung 3 is complete only when the requested CALL/RET slice works behaviorally.

The required proof points are:

- CALL pushes the correct return address
- the pushed return address matches the correct next architectural EIP / `M_NEXT_EIP`
- ESP decrements by the correct amount on CALL
- RET restores control flow correctly
- ESP increments by the correct amount on RET
- `RET imm16` applies the required post-pop stack adjustment
- nested CALL/RET behavior returns correctly through multiple frames

---

## Minimum implementation surfaces

The exact RTL changes are determined by the current repo state, but Rung 3 should be expected to touch only the surfaces genuinely needed for the CALL/RET slice.

That may include:

- decoder classification for the in-scope CALL/RET forms
- microsequencer control flow for CALL/RET entry points
- stack data-path support needed for push/pop effects
- commit-visible state updates required for architectural correctness
- targeted microcode/service support required to complete the sequence

Do not broaden implementation beyond what these behaviors require.

---

## Acceptance criteria

Rung 3 is ready for review only when all of the following are true:

- the in-scope CALL/RET forms are implemented
- the required stack effects are correct
- return flow is restored correctly
- the requested proof cases have been run
- the actual verification results are reported
- preserved baseline behavior from earlier rungs remains intact

---

## Validation expectations

Use the validation and handoff rules from `docs/process/developer_directive.md`.

Where applicable, validation for Rung 3 should include:

- required generation steps for local-only generated artifacts
- targeted CALL/RET proof cases
- broader regression checks needed to show the preserved baseline still holds

Typical prerequisite steps may include:

- `make codegen`
- `make ucode`

Typical proof should include:

- direct CALL/RET pair correctness
- indirect CALL correctness
- `RET imm16` stack-adjust correctness
- nested CALL/RET return correctness

Report only what actually ran.

---

## Summary

Rung 3 is the CALL/RET bring-up rung.

Its job is to prove correct near CALL/RET behavior, including correct stack effects and correct return restoration, while preserving the established architecture and avoiding unrelated expansion.