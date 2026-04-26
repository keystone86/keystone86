# Keystone86 / Aegis - Rung 4 Verification Record

## Scope

This record covers the bounded Rung 4 short-Jcc path only.

Rung 4 verifies:

- `70h` through `7Fh` decode as `ENTRY_JCC`
- `M_COND_CODE = opcode[3:0]`
- `flow_control: CONDITION_EVAL` evaluates the 16 Jcc conditions from committed EFLAGS
- `ENTRY_JCC` microcode completes both taken and not-taken paths
- taken Jcc computes the signed disp8 target, validates the near transfer, commits EIP at ENDI, and flushes
- not-taken Jcc commits fall-through EIP at ENDI without taken-path validation or redirect flush
- prior Rung 0 through Rung 3 baselines remain passing

This file is a verification record, not a scope document.

## Testbench

Active Rung 4 testbench:

```text
sim/tb/tb_rung4_jcc.sv
```

The testbench initializes committed EFLAGS directly because flag-producing
instructions are later-rung work. It does not implement or claim ALU/flag
producer behavior.

## Local Verification Run

Date: 2026-04-26

Base commit before local changes:

```text
a7d5d1b New rung4 directives
```

Tree state:

```text
Working tree was dirty with local Rung 4 implementation and verification changes.
This is not a clean committed acceptance baseline.
```

Commands run from `/work`:

```bash
make codegen
make ucode
make rung3-regress
make rung4-sim
make rung4-regress
```

Observed results:

```text
make codegen: pass
make ucode: pass
make rung3-regress: pass
  - Rung 0 baseline: pass
  - Rung 1 baseline: pass
  - Rung 2 regression: RESULT: ALL RUNG 2 TESTS PASSED
  - Rung 3 testbench: 46 passed, 0 failed

make rung4-sim: pass
  - Rung 4 testbench: 204 passed, 0 failed
  - RESULT: ALL RUNG 4 TESTS PASSED

make rung4-regress: pass
  - includes make rung3-regress prior-rung baseline chain
  - Rung 4 testbench: 204 passed, 0 failed
  - RESULT: ALL RUNG 4 TESTS PASSED
```

The Icarus Verilog compile emitted existing warning/sorry diagnostics for
missing explicit time units, ignored `unique` case qualities, and constant
select sensitivity in `always_*` processes. The commands exited successfully.

## What Rung 4 Does Not Claim

- Rung 5 INT/IRET behavior
- LOOP, LOOPE, LOOPNE, or JCXZ family behavior
- near or long Jcc forms beyond short `70h` through `7Fh`
- ALU or flag-producing instruction behavior
- generalized branch prediction or broader control-flow framework behavior
- a clean committed acceptance baseline

## Acceptance Note

This run proves the local delivered state, but the process still requires a
clean committed verification run before recording a final accepted Rung 4
baseline commit.
