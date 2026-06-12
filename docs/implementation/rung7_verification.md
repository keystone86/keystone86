# Keystone86 / Aegis - Rung 7 Verification

## Verification Scope

This document records only the verified partial Rung 7 reg32 subset.

Currently verified forms:

- `01 /r` `ADD r/m32, r32` with `ModRM.mod=11` only
- `03 /r` `ADD r32, r/m32` with `ModRM.mod=11` only
- `29 /r` `SUB r/m32, r32` with `ModRM.mod=11` only
- `2B /r` `SUB r32, r/m32` with `ModRM.mod=11` only
- `39 /r` `CMP r/m32, r32` with `ModRM.mod=11` only
- `3B /r` `CMP r32, r/m32` with `ModRM.mod=11` only

Newly verified by the latest post-commit session:

- `2B /r` `SUB r32, r/m32` with `ModRM.mod=11` only

This is partial Rung 7 verification only.
This is not full Rung 7 completion.
This is not Rung 7 acceptance.
Rung 8 and later remain blocked.

The active directive boundary for this record is:

```text
docs/implementation/bringup/rung7.md
```

That directive states that no partial implementation slice is Rung 7
complete. This document records actual subset evidence only.

## Latest Commit Under Test

Implementation commit:

```text
addcacfda740f42a8ff59ddee61bfc16c864c956
```

Subject:

```text
rung7: implement reg32 SUB opposite direction
```

Directive commit:

```text
34d201b docs: add rung7 ALU operations directive
```

## Latest Commit Scope

Commit `addcacfda740f42a8ff59ddee61bfc16c864c956` implemented only:

- `2B /r` `SUB r32, r/m32` with `ModRM.mod=11`

The implementation commit changed exactly 4 files:

- `microcode/src/entries/entry_alu_r_rm.uasm`
- `rtl/core/decoder.sv`
- `scripts/ucode_build.py`
- `sim/tb/tb_rung7_alu_reg32_add_cmp.sv`

No memory, read-modify-write, immediate, accumulator, 8-bit, 16-bit, logical,
ADC, SBB, TEST, INC, DEC, NEG, or NOT support was added.

The following adjacent forms remain unsupported:

- `66 2B /r`
- `2B /r` with `ModRM.mod != 11`
- `66 29 /r`
- `29 /r` with `ModRM.mod != 11`

## Verification Commands and Results

The following post-commit verification was run from clean implementation commit
`addcacfda740f42a8ff59ddee61bfc16c864c956`.

Verification session result: PASS.

| Command or check | Result |
|---|---|
| `make codegen` | PASS, no tracked drift |
| `make ucode` | PASS, no tracked drift |
| `make rung7-alu-reg32-sim` | PASS |
| `make rung5-regress` | PASS |
| `make rung6-regress` | PASS |
| `git diff --check` | PASS |
| final `git status --short` | clean |
| final `git diff --stat` | empty |
| final `git diff` | empty |

The focused Rung 7 simulation passed with:

```text
PASS: Rung 7 focused ADD/SUB/CMP reg32 smoke completed
```

`make rung6-regress` passed, including:

```text
PASS: Rung 6 Appendix D MOV matrix completed
```

`make rung5-regress` passed, including:

```text
RESULT: RUNG 5 PASS 5 INT/IRET ROUND TRIP PASSED
```

No docs or acceptance docs changed during verification. No files were edited,
staged, committed, or pushed during the verification session. This docs-only
update records that evidence only.

## Rung 7 Reg32 ADD/SUB/CMP Subset Proof Summary

The focused subset test proved the bounded register-register path for:

- `ADD 01 /r` reg32 register-register path
- `ADD 03 /r` reg32 register-register path
- `SUB 29 /r` reg32 register-register path
- `SUB 2B /r` reg32 register-register path
- `CMP 39 /r` reg32 register-register path
- `CMP 3B /r` reg32 register-register path

The previously verified `01 /r`, `03 /r`, `39 /r`, and `3B /r` ADD/CMP
subset and `29 /r` same-direction SUB slice remain part of the verified
partial Rung 7 reg32 subset. The latest verified `2B /r` slice proves
opposite-direction SUB for the same bounded `ModRM.mod=11`
register-register class.

The checked behavior included:

- destination updated for ADD and SUB
- destination unchanged for CMP
- CF, PF, AF, ZF, SF, and OF checked
- no early GPR visibility before ENDI
- no early EFLAGS visibility before ENDI
- no memory write for register-register forms
- final EIP equals EIP+2
- unsupported adjacent forms remain outside the verified support subset

The proof uses the intended Rung 7 subset shape:

- decoder routes only the verified `01/29/39` forms to `ENTRY_ALU_RM_R`
- decoder routes only the verified `03/2B/3B` forms to `ENTRY_ALU_R_RM`
- microcode loads both register operands through `LOAD_REG_META`
- bounded ALU services perform `ALU_ADD32`, `ALU_SUB32`, or `ALU_CMP32`
- ADD and SUB end through `CM_ALU_REG`
- CMP ends through `CM_FLAGS`
- architectural GPR and EFLAGS visibility remains commit-owned

## Unsupported Adjacent Forms Preserved

The verification record preserves the bounded support boundary for adjacent
unsupported forms.

Unsupported adjacent examples include:

- `00 /r`
- `02 /r`
- `28 /r`
- `2A /r`
- `38 /r`
- `3A /r`
- `66 01 /r`
- `66 29 /r`
- `66 2B /r`
- `66 39 /r`
- immediate ADD/SUB/CMP samples
- accumulator ADD/SUB/CMP samples
- logical-operation adjacent samples
- ADC/SBB adjacent samples
- memory ModRM samples for `01 /r`, `29 /r`, `2B /r`, and `39 /r`

This record does not claim support for these adjacent forms. In particular,
`66 2B /r`, `2B /r` with `ModRM.mod != 11`, `66 29 /r`, and `29 /r` with
`ModRM.mod != 11` remain unsupported.

## Generated Artifact Status

- `make codegen` produced no tracked drift.
- `make ucode` produced no tracked drift.
- The final working tree was clean.
- Final `git diff --stat` and `git diff` were empty.

## Prior-Rung Regression Status

- `make rung5-regress` PASS
- `make rung6-regress` PASS, including
  `PASS: Rung 6 Appendix D MOV matrix completed`

Rung 5 INT/IRET and Rung 6 MOV baseline behavior remained preserved by this
verification run.

## Known Warnings

Existing non-fatal Icarus/Iverilog warnings appeared during the verification
commands, including warnings such as:

- missing explicit time unit/precision warnings
- constant-select limitations in `always_*`
- ignored `unique` / `unique0` case qualities

No fatal warnings or command failures were observed. These warnings did not
fail the commands.

## Prior Recorded Verification

Earlier partial Rung 7 verification was recorded for implementation commit:

```text
1d66832f62a48c8053cf8c289b2639c92b67c65b
```

Subject:

```text
rung7: implement reg32 ADD/CMP opposite direction
```

That run recorded the `01 /r`, `03 /r`, `39 /r`, and `3B /r` ADD/CMP
`ModRM.mod=11` subset. The latest `3a75607...` verification extends the
recorded partial subset only with `29 /r` same-direction SUB.

The latest prior partial Rung 7 verification was recorded for implementation
commit:

```text
3a75607b009370fdb5c76a3ba06d8849e85a77a5
```

Subject:

```text
rung7: implement reg32 SUB same-direction slice
```

That run recorded the `29 /r` SUB `ModRM.mod=11` subset. The latest
`addcacf...` verification extends the recorded partial subset only with
`2B /r` opposite-direction SUB.

## Non-Claims

This document does not claim:

- full Rung 7 completion
- Rung 7 acceptance
- complete SUB implementation
- AND/OR/XOR implementation
- 8-bit or 16-bit ALU forms
- `2B /r` support beyond unprefixed `SUB r32, r/m32` with `ModRM.mod=11`
- `66 2B /r` support
- `2B /r` with `ModRM.mod != 11` support
- `66 29 /r` support
- `29 /r` with `ModRM.mod != 11` support
- immediate ALU forms
- accumulator ALU forms
- memory ALU forms or memory RMW
- ADC/SBB support
- TEST/INC/DEC/NEG/NOT or other adjacent ALU-family support

## Recommended Next Step

Review this verification document update. If review passes, commit only:

```text
docs/implementation/rung7_verification.md
```

Do not create acceptance documentation until explicitly authorized and
appropriate for actual Rung 7 acceptance.
