# Keystone86 / Aegis — Rung 2 Verification

## Scope

This artifact records verification for the bounded Rung 2 direct-JMP bring-up path.

Rung 2 acceptance requires:

- earlier required baselines still pass
- the bounded direct-JMP service path works end to end
- redirect becomes architecturally visible only at ENDI
- committed redirect flush occurs
- actual commands were run against the delivered state
- actual results are recorded here

This file is a verification artifact. It is not a scope document and it is not the source of implementation intent.

## Required reading

Before interpreting this verification record, read:

1. `docs/process/developer_directive.md`
2. `docs/process/developer_handoff_contract.md`
3. `docs/implementation/coding_rules/source_of_truth.md`
4. `docs/spec/frozen/appendix_d_bringup_ladder.md`
5. `docs/implementation/bringup/rung2.md`

## Commands run

Run from repo root.

    make rung2-regress

This command is the active Rung 2 regression entry point and includes the required earlier-rung baseline checks for the delivered Rung 2 state.

## Active verification target

The active bounded Rung 2 RTL verification target is:

- `sim/tb/tb_rung2_jmp.sv`

That bench proves the bounded direct-JMP self-loop service path used for current Rung 2 bring-up.

## What the active Rung 2 bench checks

The active bench verifies:

- no fault during the bounded direct-JMP loop
- committed JMP retires are observed
- committed redirect flushes are observed
- the active decoded entry remains `ENTRY_JMP_NEAR`

Default output is summary-oriented. Verbose trace is available only when explicitly enabled in the bench.

## Current recorded result

Recorded from the delivered passing state:

    Keystone86 / Aegis — Rung 2 Regression
      Rung 2: direct JMP service path, committed redirect, bounded self-loop

    Rung 2 Regression Summary
      [x] Rung 0 baseline still passes
      [x] Rung 1 baseline still passes
      [x] No fault during bounded direct JMP loop
      [x] Committed JMP retires observed: 2
      [x] Committed redirect flushes observed: 3
      [x] Active decoded entry remains ENTRY_JMP_NEAR

    RESULT: ALL RUNG 2 TESTS PASSED

## Acceptance status

Rung 2 is currently considered passing for the bounded direct-JMP path because:

- the required earlier-rung baselines still pass
- the active Rung 2 regression passes
- the bounded direct-JMP path is proven through the active bench
- committed redirect and flush behavior are observed

## What Rung 2 does not claim

This passing result does **not** claim:

- generic broader control-transfer coverage
- CALL / RET / Jcc coverage
- generalized later-rung framework completion
- more instruction coverage than the active delivered regression demonstrates

## Notes

- Verbose trace output is gated behind a debug flag in `sim/tb/tb_rung2_jmp.sv` and is off by default.
- If the active bench, active command, or bounded scope changes, this file must be updated from a fresh actual run.

## Delivered state record

Fill this in from the actual committed state after commit/push:

    git log --oneline -1

- Commit: _fill in after commit_
- Date: _fill in after commit_
- Branch: _fill in if needed_