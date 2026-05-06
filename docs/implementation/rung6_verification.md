# Keystone86 / Aegis — Rung 6 Verification

## Scope Recorded

This document records verification evidence for committed Rung 6 work.

Current recorded implementation commit:

```text
da378236a7ec2dcbc848f66be8582d52c164096c
```

Short commit:

```text
da37823
```

Recorded scope:

```text
Bounded Rung 6 Pass 2 first slice only:
B8+rd id — MOV r32, imm32
```

This is not full Rung 6 completion.
This does not claim the full Appendix D MOV matrix.
This proves only the bounded `B8-BF` `MOV r32, imm32` first slice.

## Donor Material Status

The Rung 6 donor/context import is present in the repository:

- `third_party/ao486_notes/`
- `third_party/z8086_notes/`

These imported materials do not expand Rung 6 scope and do not authorize full
Rung 6 completion by themselves.

## Verification Run

Date recorded: 2026-05-06 UTC.

Commands run after commit `da37823`:

```sh
make codegen
make ucode
make rung5-regress
make rung6-pass2-sim
git diff --check
git status --short
```

Results:

| Command | Result |
|---|---|
| `make codegen` | PASS |
| `make ucode` | PASS |
| `make rung5-regress` | PASS |
| `make rung6-pass2-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing `iverilog` warnings about constant selects and time units were present
during simulation builds. They did not fail the commands.

Rung 5 regression still passes at this committed state.

## Pass 2 First-Slice Evidence

The bounded Rung 6 Pass 2 simulation proves the first slice only:

- all eight `B8-BF` opcodes route to `ENTRY_MOV`
- `FETCH_IMM32` is issued for each first-slice MOV instruction
- `ENDI CM_MOV_REG` is used for the bounded register-destination MOV path
- eight MOV instructions complete
- destination GPR values match the eight immediate values used by the test
- final EIP matches fall-through after eight 5-byte instructions
- EFLAGS remain unchanged
- no bus writes occur for register-immediate MOV

## Explicit Non-Claims

This verification record does not claim:

- full Rung 6 completion
- full Appendix D MOV matrix completion
- `B0-B7` support
- `88/89/8A/8B` support
- `C6/C7` support
- register-register MOV support
- memory-source MOV support
- memory-destination MOV support
- `EA_CALC_16` or `EA_CALC_32` completion
- `LOAD_RM*` or `STORE_RM*` completion
- `LOAD_REG_META` or `STORE_REG_META` completion
- memory-destination visibility-path resolution
- final Rung 6 acceptance
- Rung 7 behavior

## Remaining Rung 6 Blockers

Remaining Rung 6 blockers include:

- `B0-B7`
- `88/89/8A/8B`
- `C6/C7`
- register-register MOV
- memory MOV
- `EA_CALC`
- `LOAD_RM` / `STORE_RM`
- `LOAD_REG_META` / `STORE_REG_META`
- full MOV matrix verification
- memory-destination visibility decision
- final Rung 6 acceptance

