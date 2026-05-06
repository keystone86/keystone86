# Keystone86 / Aegis — Rung 6 Verification

## Scope Recorded

This document records verification evidence for committed Rung 6 work.

Current recorded implementation commit:

```text
1dfe1f32912cebed91971aef6bd08b9849e9f0ce
```

Short commit:

```text
1dfe1f3
```

Recorded scope:

```text
Bounded Rung 6 Pass 4A only:
B0-B7 — MOV r8, imm8
```

The existing proven `B8-BF` `MOV r32, imm32` path is preserved at this
checkpoint.

Additional Pass 3 confirmation checkpoint:

```text
9fed045007e85a3a1551e47ef7e0fd0d34ceb340
```

Short commit:

```text
9fed045
```

Pass 3 records a documentation-only confirmation. No implementation change was
required: the committed Pass 2 implementation already satisfies the bounded
Pass 3 target for the `B8-BF` `MOV r32, imm32` GPR/commit proof.

This is not full Rung 6 completion.
This does not claim the full Appendix D MOV matrix.
This confirms only bounded Pass 4A:

- `B0-B7` `MOV r8, imm8`
- preservation of `B8-BF` `MOV r32, imm32`

## Donor Material Status

The Rung 6 donor/context import is present in the repository:

- `third_party/ao486_notes/`
- `third_party/z8086_notes/`

These imported materials do not expand Rung 6 scope and do not authorize full
Rung 6 completion by themselves.

## Verification Run

Date recorded: 2026-05-06 UTC.

Commands run after commit `1dfe1f3`:

```sh
make codegen
make ucode
make rung5-regress
make rung6-pass2-sim
make rung6-pass4a-sim
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
| `make rung6-pass4a-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing Icarus/Iverilog warnings about constant selects, time units, and
ignored `unique` case qualities were present during simulation builds. They did
not fail the commands.

Rung 5 regression still passes at this committed state.
Rung 7 remains blocked.

## Pass 3 Confirmation

Date recorded: 2026-05-06 UTC.

Commands run from checkpoint `9fed045007e85a3a1551e47ef7e0fd0d34ceb340`:

```sh
git fetch origin
git checkout rung-6-codex
git pull --ff-only origin rung-6-codex
make codegen
make ucode
make rung5-regress
make rung6-pass2-sim
git diff --check
git status --short
git diff --stat
git diff
```

Results:

| Command | Result |
|---|---|
| `git fetch origin` | PASS |
| `git checkout rung-6-codex` | PASS |
| `git pull --ff-only origin rung-6-codex` | PASS, already up to date |
| `make codegen` | PASS |
| `make ucode` | PASS |
| `make rung5-regress` | PASS |
| `make rung6-pass2-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |
| `git diff --stat` | PASS, empty output |
| `git diff` | PASS, empty output |

No files were changed during the Pass 3 confirmation session.

Pass 3 required no RTL, microcode, script, Makefile, or testbench changes.
Rung 5 regression still passes. Rung 7 remains blocked.

## Pass 4A Evidence

The bounded Rung 6 Pass 4A simulation proves only the authorized byte
immediate-to-register slice:

- all eight `B0-B7` opcodes route to `ENTRY_MOV`
- `FETCH_IMM8` is issued for each byte-register immediate MOV
- byte-register forms pass for `AL`, `CL`, `DL`, `BL`, `AH`, `CH`, `DH`, and
  `BH`
- low-byte writes update bits `[7:0]` of the containing 32-bit GPR
- high-byte writes update bits `[15:8]` of the containing 32-bit GPR
- `ENDI CM_MOV_REG` is used for the bounded register-destination MOV path
- architectural GPR visibility remains commit-only through `CM_MOV_REG`
- EFLAGS remain unchanged
- no bus writes occur for register-immediate MOV
- final EIP matches fall-through for the bounded Pass 4A instruction sequence
- no fault occurs during the bounded Pass 4A MOV sequence

The existing Pass 2 simulation still proves preservation of the `B8-BF`
`MOV r32, imm32` path at commit `1dfe1f3`.

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
- full Rung 6 acceptance
- `MOV r16, imm16` support
- `0x66` operand-size override support
- `FETCH_IMM16` use for `B8-BF`
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

- `MOV r16, imm16`, pending explicit `0x66` / operand-size decision
- `0x66` operand-size override
- `FETCH_IMM16` for `B8-BF`
- `88/89/8A/8B`
- `C6/C7`
- register-register MOV
- memory MOV
- `EA_CALC`
- `LOAD_RM` / `STORE_RM`
- `LOAD_REG_META` / `STORE_REG_META`
- memory-destination visibility decision
- full opcode-class dispatch
- full MOV matrix verification
- final Rung 6 acceptance
