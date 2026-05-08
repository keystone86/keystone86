# Keystone86 / Aegis — Rung 6 Verification

## Scope Recorded

This document records verification evidence for committed Rung 6 work.

Current recorded implementation commit:

```text
49d3e84a96f99c5de0fe08644fcabcd1c46b3da9
```

Short commit:

```text
49d3e84
```

Recorded scope:

```text
Bounded Rung 6 Pass 6B-1 only:
memory-destination MOV using default 32-bit addressing, absolute disp32 only
```

Implemented Pass 6B-1 forms:

- `88 /r` `MOV r/m8, r8`, memory destination only
- `89 /r` `MOV r/m32, r32`, memory destination only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination only

Implemented Pass 6B-1 addressing subset:

- `ModRM.mod = 00`
- `ModRM.r/m = 101`
- `disp32` absolute address
- default 32-bit addressing only
- no SIB
- no base register
- no index register
- no scale
- no disp8
- no `mod=01`
- no `mod=10`
- no `0x67`

Implemented Pass 6B-1 memory-destination visibility policy:

- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are direct
  microcode-sequenced `load_store` service-side bus writes
- `STORE_RM*` completes before `ENDI`
- memory-destination MOV uses `ENDI CM_NOP|CM_EIP`, not `CM_MOV_REG`
- `ENDI` performs normal sequential completion / EIP cleanup only
- no new memory-store commit mask was added
- no new frozen-spec field was added
- no new microinstruction was added
- no commit-time memory-store policy was added

Implemented Pass 6A-1 forms:

- `8A /r` `MOV r8, r/m8`, memory source only
- `8B /r` `MOV r32, r/m32`, memory source only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source only

Implemented Pass 6A-1 addressing subset:

- `ModRM.mod = 00`
- `ModRM.r/m = 101`
- `disp32` absolute address
- default 32-bit addressing only
- no SIB
- no base register
- no index register
- no scale
- no disp8
- no `mod=01`
- no `mod=10`
- no `0x67`

Implemented Pass 4B form:

- `0x66` + `B8-BF` `MOV r16, imm16`

Implemented Pass 5B forms:

- `0x66` + `89 /r` `MOV r/m16, r16`, register destination only
- `0x66` + `8B /r` `MOV r16, r/m16`, register source only

Implemented Pass 5A forms:

- `88 /r` `MOV r/m8, r8`, register destination only
- `89 /r` `MOV r/m32, r32`, register destination only
- `8A /r` `MOV r8, r/m8`, register source only
- `8B /r` `MOV r32, r/m32`, register source only

The existing proven immediate-register paths are preserved at this checkpoint:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`

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
This does not claim full Pass 6A.
This does not claim the full Appendix D MOV matrix.
This confirms only bounded Pass 6B-1 memory-destination absolute disp32
support, plus the previously recorded bounded Pass 6A-1, Pass 4B, Pass 5A, and
Pass 5B support:

- `88 /r` `MOV r/m8, r8`, memory destination only, direct absolute disp32 only
- `89 /r` `MOV r/m32, r32`, memory destination only, direct absolute disp32 only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination only, direct absolute
  disp32 only
- `8A /r` `MOV r8, r/m8`, memory source only, direct absolute disp32 only
- `8B /r` `MOV r32, r/m32`, memory source only, direct absolute disp32 only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source only, direct absolute
  disp32 only
- `0x66` + `B8-BF` `MOV r16, imm16`
- `0x66` + `89 /r` `MOV r/m16, r16`, `ModRM.mod=11` only
- `0x66` + `8B /r` `MOV r16, r/m16`, `ModRM.mod=11` only
- register-only `88/89/8A/8B` with `ModRM.mod=11`
- preservation of `B0-B7` `MOV r8, imm8`
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

## Pass 6B-1 Evidence

Date recorded: 2026-05-08 UTC.

Commands run after commit `49d3e84a96f99c5de0fe08644fcabcd1c46b3da9`:

```sh
make codegen
make ucode
make rung5-regress
make rung6-pass2-sim
make rung6-pass4a-sim
make rung6-pass4b-sim
make rung6-pass5a-sim
make rung6-pass5b-sim
make rung6-pass6a1-sim
make rung6-pass6b1-sim
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
| `make rung6-pass4b-sim` | PASS |
| `make rung6-pass5a-sim` | PASS |
| `make rung6-pass5b-sim` | PASS |
| `make rung6-pass6a1-sim` | PASS |
| `make rung6-pass6b1-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing Icarus/Iverilog warnings about time units, constant selects, and
ignored `unique` case qualities were present during simulation builds. They did
not fail the commands.

The bounded Rung 6 Pass 6B-1 simulation proves only the authorized
memory-destination absolute-disp32 slice:

- `88 /r` byte stores to absolute disp32 memory destination pass for all eight
  raw byte-register sources
- `89 /r` dword stores to absolute disp32 memory destination pass for all eight
  `r32` sources
- `0x66` + `89 /r` word stores to absolute disp32 memory destination pass for
  all eight `r16` sources
- `EA_CALC_32` is issued once per authorized memory-destination MOV and is
  bounded to direct absolute disp32 only
- `LOAD_REG_META` is issued to read each bounded memory-destination source
  register
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths only
- `STORE_RM8` uses bus byte enable `0001`
- `STORE_RM16` uses bus byte enable `0011`
- `STORE_RM32` uses bus byte enable `1111`
- final memory values match the expected byte, word, and dword stores
- `STORE_RM*` completes before `ENDI`
- memory-destination MOV uses `ENDI CM_NOP|CM_EIP`, not `CM_MOV_REG`
- no new memory-store commit mask, frozen-spec field, microinstruction, or
  commit-time memory-store policy is used
- EFLAGS remain unchanged
- no unintended GPR changes occur for memory-destination MOV
- final EIP matches fall-through for the bounded Pass 6B-1 instruction
  sequence
- unsupported adjacent memory-destination forms tested with `mod=01`, `mod=10`,
  SIB, `0x66` + `88`, and `0x67` remain unsupported and do not execute MOV
- no fault occurs during the authorized bounded Pass 6B-1 memory-destination
  MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, and Pass 6A-1
simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11` only
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11` only
- `8A /r` byte loads from absolute disp32 memory source
- `8B /r` dword loads from absolute disp32 memory source
- `0x66` + `8B /r` word loads from absolute disp32 memory source

Rung 5 regression still passes at this committed state.
Rung 7 remains blocked.

## Pass 6A-1 Evidence

Date recorded: 2026-05-08 UTC.

Commands run after commit `c45af9b266e6bdddff1d7f5a8bd1eb3d5956428f`:

```sh
make codegen
make ucode
make rung5-regress
make rung6-pass2-sim
make rung6-pass4a-sim
make rung6-pass4b-sim
make rung6-pass5a-sim
make rung6-pass5b-sim
make rung6-pass6a1-sim
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
| `make rung6-pass4b-sim` | PASS |
| `make rung6-pass5a-sim` | PASS |
| `make rung6-pass5b-sim` | PASS |
| `make rung6-pass6a1-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing Icarus/Iverilog warnings about time units, constant selects, and
ignored `unique` case qualities were present during simulation builds. They did
not fail the commands.

The bounded Rung 6 Pass 6A-1 simulation proves only the authorized
memory-source absolute-disp32 slice:

- `8A /r` byte loads from absolute disp32 memory source pass for all eight raw
  byte-register destinations
- `8B /r` dword loads from absolute disp32 memory source pass for all eight
  `r32` destinations
- `0x66` + `8B /r` word loads from absolute disp32 memory source pass for all
  eight `r16` destinations
- `EA_CALC_32` is issued once per authorized memory-source MOV and is bounded
  to direct absolute disp32 only
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths only
- `LOAD_RM8` returns a zero-extended byte through the temporary path before the
  existing byte-register commit merge
- `LOAD_RM16` returns a zero-extended little-endian word through the temporary
  path before the existing low-word commit merge
- `LOAD_RM32` returns a little-endian dword through the temporary path
- no bus writes occur for the Pass 6A-1 memory-source MOV sequence
- memory-destination `88/89` forms remain unsupported and do not execute MOV
- unsupported `8A/8B` memory addressing forms tested with `mod=01`, `mod=10`,
  and SIB remain unsupported and do not execute MOV
- `0x66` + `8A` memory-source byte remains unsupported
- `0x66` + `8B` with `mod=01` remains unsupported
- `ENDI CM_MOV_REG` is used for the bounded register-destination MOV paths
- architectural GPR visibility remains commit-only through `CM_MOV_REG`
- EFLAGS remain unchanged
- final EIP matches fall-through for the bounded Pass 6A-1 instruction
  sequence
- no fault occurs during the authorized bounded Pass 6A-1 memory-source MOV
  sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, and Pass 5B simulations still
prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11` only
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11` only

Rung 5 regression still passes at this committed state.
Rung 7 remains blocked.

## Pass 5A Evidence

Date recorded: 2026-05-07 UTC.

Commands run after commit `d2485136ef73f774eb4ca1b935fad14de52cc540`:

```sh
make codegen
make ucode
make rung5-regress
make rung6-pass2-sim
make rung6-pass4a-sim
make rung6-pass5a-sim
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
| `make rung6-pass5a-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing Icarus/Iverilog warnings about time units, constant selects, and
ignored `unique` case qualities were present during simulation builds. They did
not fail the commands.

The bounded Rung 6 Pass 5A simulation proves only the authorized
register-register slice:

- all 8x8 `r8` register combinations pass
- all 8x8 `r32` register combinations pass
- `88/89` destination-`r/m` direction behavior passes for `ModRM.mod=11`
- `8A/8B` destination-`reg` direction behavior passes for `ModRM.mod=11`
- non-`ModRM.mod=11` forms remain unsupported and do not execute memory MOV
- `LOAD_REG_META` and `STORE_REG_META` are bounded metadata-only register
  services for this slice
- no `EA_CALC`, `LOAD_RM`, `STORE_RM`, memory access, or memory visibility
  decision is implemented
- no bus writes occur for the register-only MOV sequence
- `ENDI CM_MOV_REG` is used for the bounded register-destination MOV paths
- architectural GPR visibility remains commit-only through `CM_MOV_REG`
- EFLAGS remain unchanged
- final EIP matches fall-through for the bounded Pass 5A instruction sequence
- no fault occurs during the bounded Pass 5A register-only MOV sequence

The Pass 2 and Pass 4A simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`

Rung 5 regression still passes at this committed state.
Rung 7 remains blocked.

## Pass 4B / Pass 5B Evidence

Date recorded: 2026-05-07 UTC.

Commands run after commit `0e8419f34d5b4df7b8b268bf1a298e988911bbc0`:

```sh
make codegen
make ucode
make rung5-regress
make rung6-pass2-sim
make rung6-pass4a-sim
make rung6-pass5a-sim
make rung6-pass4b-sim
make rung6-pass5b-sim
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
| `make rung6-pass5a-sim` | PASS |
| `make rung6-pass4b-sim` | PASS |
| `make rung6-pass5b-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

The bounded Rung 6 Pass 4B and Pass 5B simulations prove only the authorized
16-bit MOV slice:

- `0x66` + `B8-BF` `MOV r16, imm16` passes for all eight GPR destinations
- `0x66` + `89 /r` `MOV r/m16, r16` passes for `ModRM.mod=11` only
- `0x66` + `8B /r` `MOV r16, r/m16` passes for `ModRM.mod=11` only
- all 8x8 `r16` register-register combinations pass for the authorized `89/8B`
  register-register forms
- `FETCH_IMM16` is issued for the authorized `0x66` + `B8-BF` forms
- `FETCH_IMM16` is a generic immediate fetch only
- 16-bit GPR reads return the low word zero-extended into the temporary path
- 16-bit GPR writes merge bits `[15:0]` and preserve bits `[31:16]`
- bounded `0x66` handling affects only the authorized MOV forms in this record
- `0x66` is not implemented as broad prefix architecture
- `0x67` remains prefix-only; no address-size override behavior is implemented
- no memory MOV, `EA_CALC`, `LOAD_RM`, `STORE_RM`, or memory visibility behavior
  is implemented
- no bus writes occur for the bounded Pass 4B and Pass 5B sequences
- `ENDI CM_MOV_REG` is used for the bounded register-destination MOV paths
- architectural GPR visibility remains commit-only through `CM_MOV_REG`
- EFLAGS remain unchanged
- final EIP matches fall-through for the bounded Pass 4B and Pass 5B instruction
  sequences
- no fault occurs during the bounded Pass 4B and Pass 5B MOV sequences

The existing Pass 2, Pass 4A, and Pass 5A simulations still prove preservation
of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11` only

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
- full Pass 6A completion
- full Appendix D MOV matrix completion
- full Rung 6 acceptance
- broad `0x66` prefix architecture
- `0x66` support for non-authorized instructions
- `0x67` address-size override behavior
- `88/89` memory-destination addressing beyond direct absolute disp32
- `8A/8B` memory-source addressing beyond direct absolute disp32
- `C6/C7` support
- immediate-to-memory MOV support
- `EA_CALC_16` support
- `EA_CALC_32` beyond direct absolute disp32
- `LOAD_RM*` beyond bounded memory-source reads for direct absolute disp32
- `STORE_RM*` beyond bounded memory-destination writes for direct absolute
  disp32 MOV
- general-purpose `LOAD_REG_META` or `STORE_REG_META` completion beyond the
  bounded Pass 5A/5B register-register MOV and Pass 6B-1 memory-destination MOV
  metadata use
- SIB, base/index/scale, disp8, `mod=01`, or `mod=10` memory addressing
- protected-mode, page, or segment behavior
- final Rung 6 acceptance
- Rung 7 behavior

## Remaining Rung 6 Blockers

Remaining Rung 6 blockers include:

- `C6/C7`
- immediate-to-memory MOV
- `STORE_RM*` beyond bounded memory-destination direct absolute disp32 MOV
- SIB/base/index/scale effective-address calculation
- disp8, `mod=01`, and `mod=10` memory addressing
- `0x67` address-size override behavior
- `EA_CALC_16`
- 16-bit addressing
- protected-mode/page/segment behavior
- general-purpose `LOAD_REG_META` / `STORE_REG_META` beyond bounded
  register-register and Pass 6B-1 memory-destination MOV
- full MOV matrix verification
- full opcode-class dispatch
- final Rung 6 acceptance
