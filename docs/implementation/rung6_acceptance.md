# Rung 6 Acceptance

## Status

Accepted / ready to close, based on committed evidence.

This acceptance record is docs-only acceptance cleanup. It does not add
implementation scope beyond the committed Rung 6 Appendix D MOV matrix evidence.

## Acceptance Basis

- Final MOV matrix implementation/test commit:
  `39749d4643642eef1b41b354505c9ff26d271002`
- Verification doc commit:
  `a4a3c07 docs: record rung6 final MOV matrix verification`
- Current acceptance cleanup base commit:
  `a4a3c07`
- Rung 5 acceptance remains preserved by
  `docs/implementation/rung5_acceptance.md`.

## Commands Rerun For Acceptance

Commands rerun from the current committed tree at acceptance cleanup base
`a4a3c07ec95d912075ba9a113973eeda13a5d3f5`:

```sh
make codegen
make ucode
make rung5-regress
make rung6-regress
git diff --check
git status --short
```

## Results

- all commands passed
- `make rung6-regress` passed, including:
  `PASS: Rung 6 Appendix D MOV matrix completed`
- `git diff --check` produced no output
- final `git status --short` was clean before this acceptance doc edit
- `make codegen` and `make ucode` did not leave tracked generated drift
- existing non-fatal Icarus/Iverilog warnings remained non-fatal

Rung 5 regression passed during the acceptance rerun.

## Accepted Rung 6 Scope

Accepted Rung 6 scope is the Appendix D MOV matrix only:

- `B0-B7` `MOV r8, imm8`
- `B8-BF` `MOV r32, imm32`
- `66+B8-BF` `MOV r16, imm16`
- `88` `MOV r/m8, r8`
- `89` `MOV r/m32, r32`
- `66+89` `MOV r/m16, r16`
- `8A` `MOV r8, r/m8`
- `8B` `MOV r32, r/m32`
- `66+8B` `MOV r16, r/m16`
- `C6 /0 ib` `MOV r/m8, imm8`
- `C7 /0 id` `MOV r/m32, imm32`
- `66+C7 /0 iw` `MOV r/m16, imm16`
- bounded `C6/C7 /0` `ModRM.mod=11` immediate-to-register forms as
  already covered by the Rung 6 flow

All accepted forms were verified through the final matrix/reference harness.

## Verified Matrix Dimensions

- register-immediate forms cover all eight destinations for 8-bit, 16-bit, and
  32-bit widths
- register-register forms cover all 8x8 source/destination combinations for
  8-bit, 16-bit, and 32-bit widths in both opcode directions
- register-from-memory forms cover all eight destination registers across all
  13 addressing classes
- memory-from-register forms cover all eight source registers across all
  13 addressing classes
- memory-immediate forms cover all 13 addressing classes for applicable 8-bit,
  16-bit, and 32-bit forms
- EFLAGS unchanged checks pass
- EIP advance / `M_NEXT_EIP` checks pass
- store bus address checks pass
- store byte-enable checks pass
- store data-byte checks pass

## Verified Addressing Classes

- default-32 direct disp32
- default-32 non-SIB no-displacement base
- default-32 non-SIB `mod=01` signed disp8
- default-32 non-SIB `mod=10` signed disp32
- default-32 base-only SIB
- default-32 SIB no-base disp32
- default-32 SIB base-present indexed
- default-32 SIB no-base indexed disp32
- addr16 direct disp16
- addr16 no-displacement non-BP
- addr16 no-displacement BP pair
- addr16 `mod=01` signed disp8
- addr16 `mod=10` disp16

## Explicit Non-Scope

This acceptance does not claim:

- segment-base addition
- default-SS linearization
- protected/page/segment behavior
- `A0-A3`/moffs forms
- segment/control/debug/test MOV forms
- `MOVS`, `MOVSX`, or `MOVZX`
- broad `0x66` behavior
- full `0x67` behavior
- broad x86 MOV beyond Appendix D Rung 6
- ALU or flags-producing behavior
- Rung 7

## Protected Files

No protected authority files were changed for this acceptance cleanup.

`docs/implementation/coding_rules/source_of_truth.md` remains protected and
out of scope even if stale relative to the accepted Rung 6 state.

Unchanged protected files include:

- `AGENTS.md`
- `docs/spec/frozen/**`
- `docs/implementation/bringup/rung6.md`
- `docs/implementation/coding_rules/source_of_truth.md`
- `docs/process/**`

## Rung 7 Status

Rung 7 remains blocked until this acceptance doc is committed and pushed.

Starting Rung 7 requires an explicit Rung 7 start directive after this
acceptance checkpoint.
