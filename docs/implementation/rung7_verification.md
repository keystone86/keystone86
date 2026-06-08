# Keystone86 / Aegis - Rung 7 Verification

## Verification Scope

This document records only the first Rung 7 implementation slice.

Verified forms:

- `01 /r` `ADD r/m32, r32` with `ModRM.mod=11` only
- `39 /r` `CMP r/m32, r32` with `ModRM.mod=11` only

This is not full Rung 7 completion.
This is not Rung 7 acceptance.
Rung 8 and later remain blocked.

The active directive boundary for this record is:

```text
docs/implementation/bringup/rung7.md
```

That directive states that no partial implementation slice is Rung 7
complete. This document records actual first-slice evidence only.

## Commit Under Test

Implementation commit:

```text
0af4ef901a7fad30b6d86b879ef1c1048d944760
```

Subject:

```text
rung7: implement reg32 ADD/CMP first slice
```

Directive commit:

```text
34d201b docs: add rung7 ALU operations directive
```

## Verification Commands and Results

The following post-commit verification was run from clean implementation commit
`0af4ef901a7fad30b6d86b879ef1c1048d944760`.

| Command or check | Result |
|---|---|
| `make codegen` | PASS |
| `git status --short` after codegen | clean |
| `make ucode` | PASS |
| `git status --short` after ucode | clean |
| `make rung7-alu-reg32-sim` | PASS |
| `make rung5-regress` | PASS |
| `make rung6-regress` | PASS |
| `git diff --check` | PASS |
| final `git status --short` | clean |
| final `git diff --stat` | empty |
| final `git diff` | empty |
| `git status --ignored --short build` | `!! build/` |

Generated `build/` outputs were ignored.

## Rung 7 First-Slice Proof Summary

The focused first-slice test proved the bounded register-register path for:

- `ADD 01 /r` reg32 register-register path
- `CMP 39 /r` reg32 register-register path

The focused test covered three ADD cases and three CMP cases.

The checked behavior included:

- destination updated for ADD
- destination unchanged for CMP
- CF, PF, AF, ZF, SF, and OF checked
- no early GPR visibility before ENDI
- no early EFLAGS visibility before ENDI
- no memory write for register-register forms
- final EIP equals EIP+2
- unsupported adjacent forms do not route to `ENTRY_ALU_RM_R`

The proof uses the intended Rung 7 first-slice shape:

- decoder routes only the verified forms to `ENTRY_ALU_RM_R`
- microcode loads both register operands through `LOAD_REG_META`
- bounded ALU services perform `ALU_ADD32` or `ALU_CMP32`
- ADD ends through `CM_ALU_REG`
- CMP ends through `CM_FLAGS`
- architectural GPR and EFLAGS visibility remains commit-owned

## Unsupported Adjacent Forms Covered

The focused first-slice test covered 18 unsupported adjacent forms.

Covered unsupported examples included:

- `00 /r`
- `02 /r`
- `38 /r`
- `3A /r`
- `66 01 /r`
- `66 39 /r`
- `03 /r`
- `3B /r`
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

- `make codegen` produced no tracked drift.
- `make ucode` produced no tracked drift.
- `build/` outputs are ignored.
- The final working tree was clean.

## Prior-Rung Regression Status

- `make rung5-regress` PASS
- `make rung6-regress` PASS

Rung 5 INT/IRET and Rung 6 MOV baseline behavior remained preserved by this
verification run.

## Known Warnings

Existing non-fatal Icarus/Iverilog warnings appeared during the verification
commands, including warnings such as:

- time unit/precision warnings
- constant-select limitations in `always_*`
- ignored `unique` / `unique0` qualities

These warnings did not fail the commands.

## Non-Claims

This document does not claim:

- full Rung 7 completion
- Rung 7 acceptance
- SUB/AND/OR/XOR implementation
- 8-bit or 16-bit ALU forms
- opposite-direction ALU forms
- immediate ALU forms
- accumulator ALU forms
- memory ALU forms or memory RMW
- ADC/SBB support
- TEST/INC/DEC/NEG/NOT or other adjacent ALU-family support

## Recommended Next Step

Review this verification document. If review passes, commit only:

```text
docs/implementation/rung7_verification.md
```

Do not create acceptance documentation until explicitly authorized and
appropriate for actual Rung 7 acceptance.
