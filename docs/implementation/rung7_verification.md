# Keystone86 / Aegis - Rung 7 Verification

## Verification Scope

This document records only the verified Rung 7 reg32 ADD/CMP subset.

Verified forms:

- `01 /r` `ADD r/m32, r32` with `ModRM.mod=11` only
- `39 /r` `CMP r/m32, r32` with `ModRM.mod=11` only
- `03 /r` `ADD r32, r/m32` with `ModRM.mod=11` only
- `3B /r` `CMP r32, r/m32` with `ModRM.mod=11` only

This is not full Rung 7 completion.
This is not Rung 7 acceptance.
Rung 8 and later remain blocked.

The active directive boundary for this record is:

```text
docs/implementation/bringup/rung7.md
```

That directive states that no partial implementation slice is Rung 7
complete. This document records actual subset evidence only.

## Commit Under Test

Implementation commit:

```text
1d66832f62a48c8053cf8c289b2639c92b67c65b
```

Subject:

```text
rung7: implement reg32 ADD/CMP opposite direction
```

Directive commit:

```text
34d201b docs: add rung7 ALU operations directive
```

## Verification Commands and Results

The following post-commit verification was run from clean implementation commit
`1d66832f62a48c8053cf8c289b2639c92b67c65b`.

Verification session result: PASS.

| Command or check | Result |
|---|---|
| `make ucode` | PASS |
| `git status --short` after ucode | clean |
| `make rung7-alu-reg32-sim` | PASS |
| `make rung5-regress` | PASS |
| `make rung6-regress` | PASS |
| `git diff --check` | PASS |
| final `git status --short` | clean |
| final `git diff --stat` | empty |
| final `git diff` | empty |

`make ucode` caused no tracked drift.

The focused Rung 7 simulation passed with:

```text
PASS: Rung 7 focused ADD/CMP reg32 smoke completed
```

`make rung6-regress` passed, including:

```text
PASS: Rung 6 Appendix D MOV matrix completed
```

No files were edited, staged, committed, or pushed during the verification
session. This docs-only update records that evidence only.

## Rung 7 Reg32 ADD/CMP Subset Proof Summary

The focused subset test proved the bounded register-register path for:

- `ADD 01 /r` reg32 register-register path
- `CMP 39 /r` reg32 register-register path
- `ADD 03 /r` reg32 register-register path
- `CMP 3B /r` reg32 register-register path

The previously verified `01 /r` and `39 /r` first slice remains part of this
verified Rung 7 reg32 ADD/CMP subset. The newly verified `03 /r` and `3B /r`
slice proves the opposite opcode direction for the same bounded
`ModRM.mod=11` register-register class.

The checked behavior included:

- destination updated for ADD
- destination unchanged for CMP
- CF, PF, AF, ZF, SF, and OF checked
- no early GPR visibility before ENDI
- no early EFLAGS visibility before ENDI
- no memory write for register-register forms
- final EIP equals EIP+2
- unsupported adjacent forms do not route to the bounded ALU entries

The proof uses the intended Rung 7 subset shape:

- decoder routes only the verified `01/39` forms to `ENTRY_ALU_RM_R`
- decoder routes only the verified `03/3B` forms to `ENTRY_ALU_R_RM`
- microcode loads both register operands through `LOAD_REG_META`
- bounded ALU services perform `ALU_ADD32` or `ALU_CMP32`
- ADD ends through `CM_ALU_REG`
- CMP ends through `CM_FLAGS`
- architectural GPR and EFLAGS visibility remains commit-owned

## Unsupported Adjacent Forms Covered

The focused subset test covered unsupported adjacent forms.

Covered unsupported examples included:

- `00 /r`
- `02 /r`
- `38 /r`
- `3A /r`
- `66 01 /r`
- `66 39 /r`
- immediate ADD/CMP samples
- accumulator ADD/CMP samples
- SUB/XOR adjacent samples
- ADC/SBB adjacent samples
- memory ModRM samples for `01 /r` and `39 /r`

For these unsupported forms, the focused test checked that they did not route
to `ENTRY_ALU_RM_R`, did not invoke the bounded ALU service, did not use the
ALU ENDI masks, did not issue a bus write before unsupported dispatch, and
left GPRs and EFLAGS unchanged before unsupported dispatch.

## Generated Artifact Status

- `make ucode` produced no tracked drift.
- The final working tree was clean.
  Final `git diff --stat` and `git diff` were empty.

## Prior-Rung Regression Status

- `make rung5-regress` PASS
- `make rung6-regress` PASS, including
  `PASS: Rung 6 Appendix D MOV matrix completed`

Rung 5 INT/IRET and Rung 6 MOV baseline behavior remained preserved by this
verification run.

## Known Warnings

Existing non-fatal Icarus/Iverilog warnings appeared during the verification
commands, including warnings such as:

- time unit/precision warnings
- constant-select limitations in `always_*`
- ignored `unique` / `unique0` qualities

No fatal warnings or command failures were observed. These warnings did not
fail the commands.

## Non-Claims

This document does not claim:

- full Rung 7 completion
- Rung 7 acceptance
- SUB/AND/OR/XOR implementation
- 8-bit or 16-bit ALU forms
- opposite-direction ALU forms beyond the verified `03 /r` and `3B /r`
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
