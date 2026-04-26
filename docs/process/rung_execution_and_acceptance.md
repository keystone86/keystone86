# Keystone86 / Aegis — Rung Execution and Acceptance

## Purpose

This document defines how bring-up rungs are executed, validated, and accepted.

It exists so that every contributor has an unambiguous understanding of what "rung complete" means and what process gates it.

---

## What a rung is

A rung is a discrete, simulation-proven bring-up milestone. Each rung:

- has a defined goal
- has defined acceptance criteria in `docs/spec/frozen/appendix_d_bringup_ladder.md`
- has a self-checking simulation testbench that proves the criteria
- is gated — a later rung cannot begin until the prior rung is stable

Rungs are not advisory. A rung is either passing or it is not.

---

## Current rung status

| Rung | Goal | Status | Testbench |
|---|---|---|---|
| Rung 0 | Reset/fetch/decode/dispatch loop | **Passing** | `sim/tb/tb_rung0_reset_loop.sv` |
| Rung 1 | NOP classification, EIP advance | **Passing** | `sim/tb/tb_rung1_nop_loop.sv` |
| Rung 2 | JMP SHORT control transfer | **Passing** | `sim/tb/tb_rung2_jmp.sv` |
| Rung 3 | Near CALL and RET | **Passing** | `sim/tb/tb_rung3_call_ret.sv` |
| Rung 4 | Short Jcc | **Verified/documented** | `sim/tb/tb_rung4_jcc.sv` |
| Rung 5 | INT / IRET / fault delivery | **Verified/documented** | `sim/tb/tb_rung5_*.sv` |
| Rung 6+ | Future bring-up rungs | Blocked until Rung 5 is explicitly accepted | — |

Rung 5 verification is recorded in `docs/implementation/rung5_verification.md`.
That record documents committed-state verification, but it does not by itself
record human acceptance.

---

## How to run the current passing baseline

From repo root, with `iverilog` installed:

```bash
make codegen
make ucode
make rung5-regress
```

To run the full regression chain (each level includes all prior rungs):

```bash
make rung5-regress
```

`rung5-regress` is the current full regression chain for the verified/documented
baseline. The verified/documented baseline is Rung 0 through Rung 5 all green;
Rung 5 still requires explicit acceptance before Rung 6 can begin.

---

## Gate criteria for claiming a rung is complete

A rung is complete only when **all** of the following are true:

1. The rung's acceptance criteria in Appendix D are met.
2. The rung's testbench passes with zero failures (`RESULT: ALL TESTS PASSED` or equivalent).
3. All prior rungs still pass — run `make rung{N-1}-regress` to confirm.
4. The verification was run against the **exact committed state**, not a local working tree with uncommitted changes.
5. The commit hash, date, and (optionally) tag are recorded in the rung's verification doc (`docs/implementation/rung{N}_verification.md`).

If any of the above are false, the rung is not complete.

---

## What "prior rungs still pass" means

Each rung regression includes all prior rungs. Specifically:

- `make rung1-regress` runs Rung 0 baseline then Rung 1.
- `make rung2-regress` runs Rung 0 + Rung 1 baseline then Rung 2.
- `make rung3-regress` runs Rung 0 + Rung 1 + Rung 2 baseline checks before running Rung 3.
- `make rung4-regress` runs Rung 0 + Rung 1 + Rung 2 + Rung 3 baseline checks before running Rung 4.
- `make rung5-regress` runs Rung 4 regression before running the Rung 5 Pass 2/3/4/5 simulations.

A new rung implementation that breaks a prior rung is not acceptable. Restore the prior rung before claiming the new rung is complete.

---

## How to start a new rung

Before beginning implementation for Rung N:

1. Confirm Rung N-1 is stable and committed.
2. Read `docs/spec/frozen/appendix_d_bringup_ladder.md` for the Rung N gate criteria.
3. Read the relevant design docs in `docs/spec/design/` for the modules involved.
4. Read `docs/implementation/coding_rules/review_checklist.md`.
5. Read `docs/implementation/coding_rules/source_of_truth.md`.
6. Implement the minimum RTL change that satisfies the contracts.
7. Write or extend the testbench to prove the contracts.
8. Confirm all prior rungs still pass.
9. Record the passing baseline in `docs/implementation/rung{N}_verification.md`.

Do not widen scope beyond what the rung requires. Scope creep deferred to a later rung is not a failure — it is correct discipline.

---

## Rung verification record format

Each rung must have a `docs/implementation/rung{N}_verification.md` that includes:

- how to run the testbench
- what each test proves
- expected output
- passing baseline (date, commit, optional tag)
- what the rung does not cover

The passing baseline section must be filled in with the actual commit hash from `git log` when the rung first passes. It must not be left blank after a rung is accepted.

---

## What invalidates a passing rung

The following actions require re-running verification before the rung can still be claimed as passing:

- any RTL change to a module in the rung's simulation source list
- any change to `build/microcode/` artifacts (re-run `make ucode` then re-verify)
- any change to the testbench itself
- any change to the shared package or include files

Changes to documentation, scaffold files, or unrelated modules do not require re-verification.

---

## Rung scope discipline

A rung implementation must not:

- implement behavior beyond the rung's defined goal
- widen a module's scope beyond what the rung's contracts require
- introduce future-rung semantics under the guise of the current rung
- paper over a contract failure in the testbench to make it pass

If a correct implementation requires broader scope than the rung defines, stop and escalate — do not absorb the scope silently.
