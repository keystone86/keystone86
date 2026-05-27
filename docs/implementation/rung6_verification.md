# Keystone86 / Aegis — Rung 6 Verification

## Scope Recorded

This document records verification evidence for committed Rung 6 work.

Current recorded implementation commit:

```text
b3259a0af3ab372024d2580bd2ef966a51ef2c07
```

Short commit:

```text
b3259a0
```

Recorded scope:

```text
Bounded Rung 6 Pass 6H-1 only:
0x67 address-size override for 16-bit direct disp16 MOV memory addressing
```

Implemented Pass 6H-1 addressing subset:

- `0x67` address-size override present
- 16-bit addressing only for direct disp16:
  - `ModRM.mod = 00`
  - `ModRM.r/m = 110`
  - disp16 present
  - effective offset = zero-extended disp16
- `EA_CALC_16` writes `T2 = zero-extended disp16 offset`
- default operand-size forms and bounded `0x66` operand-size forms already
  authorized for MOV
- bounded `0x66` + `0x67` forms only for authorized MOV forms
- no BX/BP/SI/DI register-based 16-bit addressing
- no `mod=00` `r/m=000/001/010/011/100/101/111` 16-bit addressing
- no `mod=01` signed disp8 16-bit addressing
- no `mod=10` disp16 base/displacement 16-bit addressing
- no BP-based default segment / SS behavior
- no segment-base addition
- no protected/page/segment behavior
- no full `0x67` architecture
- no broad `0x66` architecture
- no Rung 7

Implemented Pass 6H-1 MOV forms over this EA subset only:

- `0x67` + `8A /r` `MOV r8, r/m8`, memory source
- `0x67` + `8B /r` `MOV r32, r/m32`, memory source
- `0x66` + `0x67` + `8B /r` `MOV r16, r/m16`, memory source
- `0x67` + `88 /r` `MOV r/m8, r8`, memory destination
- `0x67` + `89 /r` `MOV r/m32, r32`, memory destination
- `0x66` + `0x67` + `89 /r` `MOV r/m16, r16`, memory destination
- `0x67` + `C6 /0 ib` `MOV r/m8, imm8`, memory destination
- `0x67` + `C7 /0 id` `MOV r/m32, imm32`, memory destination
- `0x66` + `0x67` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination

Implemented Pass 6H-1 behavior:

- reuses existing MOV microcode structure after `EA_CALC_16` produces `T2`
- reuses existing decoder displacement metadata
- uses existing authority concepts only:
  - `M_ADDRSZ` / address-size metadata
  - `C_ADDR16`
  - `C_ADDR32`
  - `EA_CALC_16`
  - `MRM_DIRECT16`
- does not add a new frozen-spec field
- does not add a new service ID
- does not add a new microinstruction opcode
- does not add a new commit mask
- does not add a new opcode class
- reuses `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` for memory-source reads
- reuses `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` for memory-destination
  writes
- reuses `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` for `C6/C7`
  immediate-to-memory forms
- preserves all default-32 behavior verified through Pass 6G-2
- preserves bounded `0x66` behavior for authorized MOV forms only
- preserves `ModRM.mod=11` register forms for non-`0x67` forms
- keeps `0x67` + `ModRM.mod=11` register forms unsupported
- preserves `C6/C7` non-`/0` unsupported behavior
- preserves standalone `0x67` prefix-byte boundary behavior where tests
  intentionally check standalone prefix-only exposure
- keeps unsupported complete `0x67` MOV-shaped forms routed as unsupported/null
  rather than claimed
- preserves EFLAGS unchanged

Previously implemented Pass 6G-2 addressing subset:

- default 32-bit addressing only
- `ModRM.mod = 00`
- `ModRM.r/m = 100`
- SIB present
- `SIB.base = 101`
- `SIB.index != 100`
- `SIB.scale = 00/01/10/11`
- disp32 present
- effective address = disp32 + (committed index GPR << SIB.scale)
- no committed base GPR contribution
- ESP cannot be an index because `SIB.index=100` means no index
- no `0x67` address-size behavior was implemented by Pass 6G-2
- no `EA_CALC_16`
- no 16-bit addressing
- no protected/page/segment behavior

Previously implemented Pass 6G-2 MOV forms over this EA subset only:

- `8A /r` `MOV r8, r/m8`, memory source
- `8B /r` `MOV r32, r/m32`, memory source
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source
- `88 /r` `MOV r/m8, r8`, memory destination
- `89 /r` `MOV r/m32, r32`, memory destination
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination
- `C7 /0 id` `MOV r/m32, imm32`, memory destination
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination

Previously implemented Pass 6G-2 behavior:

- reuses existing MOV microcode after `EA_CALC_32` produces `T2`
- reuses existing decoder raw SIB byte capture
- reuses existing decoder disp32 metadata for SIB no-base indexed disp32
- reuses existing Pass 6G-1 index-read sequencing in `EA_CALC_32`
- reuses existing scale arithmetic inside `EA_CALC_32`
- `EA_CALC_32` writes `T2 = meta_disp_value + (committed
  GPR[SIB.index] << SIB.scale)`
- does not use the committed base GPR value for this form
- does not add a second physical committed-GPR read port
- does not add a new service ID
- does not add a new microinstruction
- does not add a new commit mask
- does not add a new opcode class
- does not add a frozen-spec field
- reuses `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` for memory-source reads
- reuses `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` for memory-destination
  writes
- reuses `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` for `C6/C7`
  immediate-to-memory forms
- preserves all non-SIB behavior verified through Pass 6E-3
- preserves base-only SIB behavior verified through Pass 6F-1
- preserves no-base SIB disp32 behavior verified through Pass 6F-2
- preserves base-present indexed SIB behavior verified through Pass 6G-1
- preserves `ModRM.mod=11` register forms
- preserves EFLAGS unchanged

Previously implemented Pass 6G-1 addressing subset:

- default 32-bit addressing only
- `ModRM.r/m = 100`
- SIB present
- `SIB.index != 100`
- `SIB.scale = 00/01/10/11`
- base-present forms only:
  - `ModRM.mod = 00` and `SIB.base != 101`, no displacement
  - `ModRM.mod = 01` and any `SIB.base`, including `101` as EBP, plus
    sign-extended disp8
  - `ModRM.mod = 10` and any `SIB.base`, including `101` as EBP, plus disp32
- effective address = committed base GPR + (committed index GPR << SIB.scale)
  + optional displacement
- ESP cannot be an index because `SIB.index=100` means no index
- no no-base indexed SIB
- no `0x67` address-size behavior
- no `EA_CALC_16`
- no 16-bit addressing
- no protected/page/segment behavior

Previously implemented Pass 6G-1 MOV forms over this EA subset only:

- `8A /r` `MOV r8, r/m8`, memory source
- `8B /r` `MOV r32, r/m32`, memory source
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source
- `88 /r` `MOV r/m8, r8`, memory destination
- `89 /r` `MOV r/m32, r32`, memory destination
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination
- `C7 /0 id` `MOV r/m32, imm32`, memory destination
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination

Previously implemented Pass 6G-1 behavior:

- reuses existing MOV microcode after `EA_CALC_32` produces `T2`
- reuses existing decoder raw SIB byte capture
- reuses existing decoder displacement metadata for SIB disp8/disp32
- `EA_CALC_32` sequences base and index reads over the existing single
  committed-GPR read path
- `EA_CALC_32` computes scaled_index from committed `GPR[SIB.index]` shifted
  left by `SIB.scale`
- `EA_CALC_32` writes `T2` as committed `GPR[SIB.base]` + scaled_index +
  optional displacement
- does not add a second physical committed-GPR read port
- does not add a new service ID
- does not add a new microinstruction
- does not add a new commit mask
- does not add a new opcode class
- does not add a frozen-spec field
- reuses `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` for memory-source reads
- reuses `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` for memory-destination
  writes
- reuses `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` for `C6/C7`
  immediate-to-memory forms
- preserves all non-SIB behavior verified through Pass 6E-3
- preserves base-only SIB behavior verified through Pass 6F-1
- preserves no-base SIB disp32 behavior verified through Pass 6F-2
- preserves `ModRM.mod=11` register forms
- preserves EFLAGS unchanged

Previously implemented Pass 6F-2 addressing subset:

- default 32-bit addressing only
- `ModRM.mod = 00`
- `ModRM.r/m = 100`
- SIB present
- `SIB.index = 100` only, meaning no index
- `SIB.base = 101`
- disp32 present
- effective address = disp32
- no committed base GPR read contribution for this form
- no index read path
- no scale arithmetic
- no `0x67` address-size behavior
- no `EA_CALC_16`
- no 16-bit addressing
- no protected/page/segment behavior

Previously implemented Pass 6F-2 MOV forms over this EA subset only:

- `8A /r` `MOV r8, r/m8`, memory source
- `8B /r` `MOV r32, r/m32`, memory source
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source
- `88 /r` `MOV r/m8, r8`, memory destination
- `89 /r` `MOV r/m32, r32`, memory destination
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination
- `C7 /0 id` `MOV r/m32, imm32`, memory destination
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination

Previously implemented Pass 6F-2 behavior:

- reuses existing MOV microcode after `EA_CALC_32` produces `T2`
- reuses existing decoder raw SIB byte capture
- reuses existing decoder displacement metadata for SIB disp32
- `EA_CALC_32` writes `T2 = meta_disp_value` for this form
- does not use the committed base GPR value for this no-base form
- does not add an index read path
- does not implement scale arithmetic
- reuses `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` for memory-source reads
- reuses `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` for memory-destination
  writes
- reuses `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` for `C6/C7`
  immediate-to-memory forms
- preserves all non-SIB behavior verified through Pass 6E-3
- preserves base-only SIB behavior verified through Pass 6F-1
- preserves `ModRM.mod=11` register forms
- preserves EFLAGS unchanged
- no new frozen-spec field was added
- no new opcode class was added
- no new service ID was added
- no new commit mask was added
- no new microinstruction was added

Previously implemented Pass 6F-1 addressing subset:

- default 32-bit addressing only
- `ModRM.r/m = 100`
- SIB present
- `SIB.index = 100` only, meaning no index
- no index read path
- no scale arithmetic
- no `0x67` address-size behavior
- no `EA_CALC_16`
- no 16-bit addressing
- no protected/page/segment behavior

Implemented Pass 6F-1 SIB forms:

- `ModRM.mod = 00`:
  - `SIB.index = 100`
  - `SIB.base != 101`
  - effective address = committed 32-bit `GPR[SIB.base]`
  - includes ESP base through `SIB.base=100`
  - excludes `SIB.base=101` because `mod=00 base=101` is the no-base disp32
    special case
- `ModRM.mod = 01`:
  - `SIB.index = 100`
  - any `SIB.base`, including `101` as EBP
  - effective address = committed 32-bit `GPR[SIB.base]` + sign-extended disp8
- `ModRM.mod = 10`:
  - `SIB.index = 100`
  - any `SIB.base`, including `101` as EBP
  - effective address = committed 32-bit `GPR[SIB.base]` + disp32

Implemented Pass 6F-1 MOV forms over this SIB subset only:

- `8A /r` `MOV r8, r/m8`, memory source
- `8B /r` `MOV r32, r/m32`, memory source
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source
- `88 /r` `MOV r/m8, r8`, memory destination
- `89 /r` `MOV r/m32, r32`, memory destination
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination
- `C7 /0 id` `MOV r/m32, imm32`, memory destination
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination

Implemented Pass 6F-1 behavior:

- reuses existing MOV microcode after `EA_CALC_32` produces `T2`
- reuses existing committed-base GPR read infrastructure, selecting base from
  `SIB.base` for authorized SIB forms
- does not add an index read path
- does not implement scale arithmetic
- reuses existing decoder raw SIB byte capture
- reuses existing decoder displacement metadata for SIB disp8/disp32
- reuses `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` for memory-source reads
- reuses `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` for memory-destination
  writes
- reuses `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` for `C6/C7`
  immediate-to-memory forms
- preserves all non-SIB behavior verified through Pass 6E-3
- preserves `ModRM.mod=11` register forms
- preserves EFLAGS unchanged
- no new frozen-spec field was added
- no new opcode class was added
- no new service ID was added
- no new commit mask was added
- no new microinstruction was added

Implemented Pass 6D-1 forms:

- `C6 /0 ib` `MOV r/m8, imm8`, register destination only
- `C7 /0 id` `MOV r/m32, imm32`, register destination only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, register destination only

Implemented Pass 6D-1 destination subset:

- register destination only
- `ModRM.mod = 11`
- `ModRM.reg/opcode extension = /0` only
- no memory addressing
- no `EA_CALC`
- no `LOAD_RM`
- no `STORE_RM`
- no memory bus behavior
- no SIB
- no displacement
- no `0x67`

Implemented Pass 6D-1 immediate-to-register behavior:

- reuses `FETCH_IMM8` for `C6 /0 ib`
- reuses `FETCH_IMM32` for `C7 /0 id`
- reuses `FETCH_IMM16` for `0x66` + `C7 /0 iw`
- reuses `STAGE_GPR` with `T4`
- reuses `ENDI CM_MOV_REG` for architectural GPR visibility
- reuses existing byte-register commit behavior, including high-byte registers
  for `r8`
- reuses existing 16-bit low-word merge behavior for `0x66` + `C7`
- no new commit mask was added
- no new frozen-spec field was added
- no new opcode class was added
- no new service ID was added
- no new microinstruction was added

Implemented Pass 6C-1 forms:

- `C6 /0 ib` `MOV r/m8, imm8`, memory destination only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination only

Implemented Pass 6C-1 addressing subset:

- memory destination only
- `ModRM.mod = 00`
- `ModRM.r/m = 101`
- `ModRM.reg/opcode extension = /0` only
- `disp32` absolute address
- default 32-bit addressing only
- no SIB
- no base register
- no index register
- no scale
- no disp8
- no `mod=01`
- no `mod=10`
- no `mod=11` register-destination `C6/C7`
- no `0x67`

Implemented Pass 6C-1 immediate-to-memory behavior:

- reuses `FETCH_IMM8` for `C6 /0 ib`
- reuses `FETCH_IMM32` for `C7 /0 id`
- reuses `FETCH_IMM16` for `0x66` + `C7 /0 iw`
- reuses bounded `EA_CALC_32` direct disp32 only
- reuses `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` as direct
  microcode-sequenced `load_store` service-side bus writes
- `STORE_RM*` completes before `ENDI`
- immediate-to-memory MOV uses `ENDI CM_NOP|CM_EIP`
- `ENDI` performs normal sequential completion / EIP cleanup only
- no new memory-store commit mask was added
- no new frozen-spec field was added
- no new opcode class was added
- no new service ID was added
- no new microinstruction was added
- no commit-time memory-store policy was added

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
This does not claim the full Appendix D MOV matrix.
This confirms only bounded Pass 6H-1 `0x67` direct disp16 MOV support, plus
the previously recorded bounded Pass 6G-2, Pass 6G-1, Pass 6F-2,
Pass 6F-1, Pass 6E-3, Pass 6E-2, Pass 6E-1, Pass 6D-1, Pass 6C-1,
Pass 6B-1, Pass 6A-1, Pass 4B, Pass 5A, and Pass 5B support:

- `0x67` + `8A /r` `MOV r8, r/m8`, memory source, 16-bit direct disp16 EA
  only
- `0x67` + `8B /r` `MOV r32, r/m32`, memory source, 16-bit direct disp16 EA
  only
- `0x66` + `0x67` + `8B /r` `MOV r16, r/m16`, memory source, 16-bit direct
  disp16 EA only
- `0x67` + `88 /r` `MOV r/m8, r8`, memory destination, 16-bit direct disp16
  EA only
- `0x67` + `89 /r` `MOV r/m32, r32`, memory destination, 16-bit direct
  disp16 EA only
- `0x66` + `0x67` + `89 /r` `MOV r/m16, r16`, memory destination, 16-bit
  direct disp16 EA only
- `0x67` + `C6 /0 ib` `MOV r/m8, imm8`, memory destination, 16-bit direct
  disp16 EA only
- `0x67` + `C7 /0 id` `MOV r/m32, imm32`, memory destination, 16-bit direct
  disp16 EA only
- `0x66` + `0x67` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination,
  16-bit direct disp16 EA only

- `8A /r` `MOV r8, r/m8`, memory source, default-32 no-base indexed SIB
  disp32 EA only
- `8B /r` `MOV r32, r/m32`, memory source, default-32 no-base indexed SIB
  disp32 EA only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source, default-32 no-base
  indexed SIB disp32 EA only
- `88 /r` `MOV r/m8, r8`, memory destination, default-32 no-base indexed SIB
  disp32 EA only
- `89 /r` `MOV r/m32, r32`, memory destination, default-32 no-base indexed
  SIB disp32 EA only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination, default-32 no-base
  indexed SIB disp32 EA only
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination, default-32 no-base indexed
  SIB disp32 EA only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination, default-32 no-base
  indexed SIB disp32 EA only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination, default-32
  no-base indexed SIB disp32 EA only

- `8A /r` `MOV r8, r/m8`, memory source, default-32 base-present indexed SIB
  EA only
- `8B /r` `MOV r32, r/m32`, memory source, default-32 base-present indexed
  SIB EA only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source, default-32 base-present
  indexed SIB EA only
- `88 /r` `MOV r/m8, r8`, memory destination, default-32 base-present indexed
  SIB EA only
- `89 /r` `MOV r/m32, r32`, memory destination, default-32 base-present
  indexed SIB EA only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination, default-32
  base-present indexed SIB EA only
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination, default-32 base-present
  indexed SIB EA only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination, default-32 base-present
  indexed SIB EA only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination, default-32
  base-present indexed SIB EA only

- `8A /r` `MOV r8, r/m8`, memory source, default-32 SIB no-base disp32 EA only
- `8B /r` `MOV r32, r/m32`, memory source, default-32 SIB no-base disp32 EA
  only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source, default-32 SIB no-base
  disp32 EA only
- `88 /r` `MOV r/m8, r8`, memory destination, default-32 SIB no-base disp32
  EA only
- `89 /r` `MOV r/m32, r32`, memory destination, default-32 SIB no-base
  disp32 EA only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination, default-32 SIB
  no-base disp32 EA only
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination, default-32 SIB no-base
  disp32 EA only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination, default-32 SIB no-base
  disp32 EA only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination, default-32
  SIB no-base disp32 EA only

- `8A /r` `MOV r8, r/m8`, memory source, default-32 base-only SIB EA only
- `8B /r` `MOV r32, r/m32`, memory source, default-32 base-only SIB EA only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source, default-32
  base-only SIB EA only
- `88 /r` `MOV r/m8, r8`, memory destination, default-32 base-only SIB EA
  only
- `89 /r` `MOV r/m32, r32`, memory destination, default-32 base-only SIB EA
  only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination, default-32
  base-only SIB EA only
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination, default-32 base-only SIB
  EA only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination, default-32 base-only
  SIB EA only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination, default-32
  base-only SIB EA only

- `8A /r` `MOV r8, r/m8`, memory source, default-32 non-SIB `mod=10`
  signed disp32 EA only
- `8B /r` `MOV r32, r/m32`, memory source, default-32 non-SIB `mod=10`
  signed disp32 EA only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source, default-32 non-SIB
  `mod=10` signed disp32 EA only
- `88 /r` `MOV r/m8, r8`, memory destination, default-32 non-SIB `mod=10`
  signed disp32 EA only
- `89 /r` `MOV r/m32, r32`, memory destination, default-32 non-SIB
  `mod=10` signed disp32 EA only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination, default-32
  non-SIB `mod=10` signed disp32 EA only
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination, default-32 non-SIB
  `mod=10` signed disp32 EA only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination, default-32 non-SIB
  `mod=10` signed disp32 EA only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination, default-32
  non-SIB `mod=10` signed disp32 EA only

- `8A /r` `MOV r8, r/m8`, memory source, default-32 non-SIB `mod=01`
  signed disp8 EA only
- `8B /r` `MOV r32, r/m32`, memory source, default-32 non-SIB `mod=01`
  signed disp8 EA only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source, default-32 non-SIB
  `mod=01` signed disp8 EA only
- `88 /r` `MOV r/m8, r8`, memory destination, default-32 non-SIB `mod=01`
  signed disp8 EA only
- `89 /r` `MOV r/m32, r32`, memory destination, default-32 non-SIB
  `mod=01` signed disp8 EA only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination, default-32
  non-SIB `mod=01` signed disp8 EA only
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination, default-32 non-SIB
  `mod=01` signed disp8 EA only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination, default-32 non-SIB
  `mod=01` signed disp8 EA only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination, default-32
  non-SIB `mod=01` signed disp8 EA only

- `8A /r` `MOV r8, r/m8`, memory source, default-32 base-only
  no-displacement EA only
- `8B /r` `MOV r32, r/m32`, memory source, default-32 base-only
  no-displacement EA only
- `0x66` + `8B /r` `MOV r16, r/m16`, memory source, default-32 base-only
  no-displacement EA only
- `88 /r` `MOV r/m8, r8`, memory destination, default-32 base-only
  no-displacement EA only
- `89 /r` `MOV r/m32, r32`, memory destination, default-32 base-only
  no-displacement EA only
- `0x66` + `89 /r` `MOV r/m16, r16`, memory destination, default-32
  base-only no-displacement EA only
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination, default-32 base-only
  no-displacement EA only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination, default-32 base-only
  no-displacement EA only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination, default-32
  base-only no-displacement EA only
- `C6 /0 ib` `MOV r/m8, imm8`, register destination only, `ModRM.mod=11`
  only
- `C7 /0 id` `MOV r/m32, imm32`, register destination only, `ModRM.mod=11`
  only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, register destination only,
  `ModRM.mod=11` only
- `C6 /0 ib` `MOV r/m8, imm8`, memory destination only, direct absolute disp32
  only
- `C7 /0 id` `MOV r/m32, imm32`, memory destination only, direct absolute
  disp32 only
- `0x66` + `C7 /0 iw` `MOV r/m16, imm16`, memory destination only, direct
  absolute disp32 only
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

## Pass 6H-1 Evidence

Date recorded: 2026-05-27 UTC.

Commands run after commit `b3259a0af3ab372024d2580bd2ef966a51ef2c07`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
make rung6-pass6e1-sim
make rung6-pass6e2-sim
make rung6-pass6e3-sim
make rung6-pass6f1-sim
make rung6-pass6f2-sim
make rung6-pass6g1-sim
make rung6-pass6g2-sim
make rung6-pass6h1-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `b3259a0af3ab372024d2580bd2ef966a51ef2c07`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- `make codegen` and `make ucode` did not leave tracked generated drift
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `make rung6-pass6e1-sim` | PASS |
| `make rung6-pass6e2-sim` | PASS |
| `make rung6-pass6e3-sim` | PASS |
| `make rung6-pass6f1-sim` | PASS |
| `make rung6-pass6f2-sim` | PASS |
| `make rung6-pass6g1-sim` | PASS |
| `make rung6-pass6g2-sim` | PASS |
| `make rung6-pass6h1-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing non-fatal Icarus/Iverilog warnings about time units, constant selects,
and ignored `unique` case qualities were present during simulation builds. They
did not fail the commands.

The bounded Rung 6 Pass 6H-1 simulation proves only the authorized `0x67`
direct disp16 effective-address slice:

- `0x67` + `8A /r` byte loads from 16-bit direct disp16 memory source pass for
  the authorized subset
- `0x67` + `8B /r` dword loads from 16-bit direct disp16 memory source pass for
  the authorized subset
- `0x66` + `0x67` + `8B /r` word loads from 16-bit direct disp16 memory source
  pass for the authorized subset
- `0x67` + `88 /r` byte stores to 16-bit direct disp16 memory destination pass
  for the authorized subset
- `0x67` + `89 /r` dword stores to 16-bit direct disp16 memory destination pass
  for the authorized subset
- `0x66` + `0x67` + `89 /r` word stores to 16-bit direct disp16 memory
  destination pass for the authorized subset
- `0x67` + `C6 /0 ib` byte immediate stores to 16-bit direct disp16 memory
  destination pass for the authorized subset
- `0x67` + `C7 /0 id` dword immediate stores to 16-bit direct disp16 memory
  destination pass for the authorized subset
- `0x66` + `0x67` + `C7 /0 iw` word immediate stores to 16-bit direct disp16
  memory destination pass for the authorized subset
- `EA_CALC_16` computes `T2 = zero-extended disp16 offset` for
  `ModRM.mod=00`, `ModRM.r/m=110`, disp16-present forms
- default operand-size forms and bounded `0x66` operand-size forms remain
  limited to authorized MOV forms
- bounded `0x66` + `0x67` forms are proven only for the authorized MOV forms
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` are issued for the authorized
  `C6/C7` immediate-to-memory forms
- default-32 absolute disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 non-SIB base-only no-displacement, `mod=01` signed disp8, and
  `mod=10` signed disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 base-only SIB memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 SIB no-base disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 base-present indexed SIB memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 no-base indexed SIB disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- `ModRM.mod=11` register forms for non-`0x67` forms remain preserved
- `0x67` + `ModRM.mod=11` register forms remain unsupported
- `C6/C7` non-`/0` forms remain unsupported
- standalone `0x67` prefix-byte boundary behavior remains preserved where
  tests intentionally check standalone prefix-only exposure
- unsupported complete `0x67` MOV-shaped forms remain routed as unsupported/null
  rather than claimed
- no new frozen-spec field, opcode class, service ID, commit mask, or
  microinstruction opcode is used
- EFLAGS remain unchanged
- no 16-bit register-based addressing is implemented
- no 16-bit `mod=01` signed disp8 addressing is implemented
- no 16-bit `mod=10` disp16 addressing is implemented
- no BP-based default segment / SS behavior is implemented
- no segment-base addition is implemented
- no protected/page/segment behavior is implemented
- no full `0x67` architecture is implemented
- no broad `0x66` architecture is implemented
- no fault occurs during the authorized bounded Pass 6H-1 MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, Pass 6E-3,
Pass 6F-1, Pass 6F-2, Pass 6G-1, and Pass 6G-2 simulations still prove
preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11`
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11`
- `8A/8B/66+8B` memory-source absolute disp32
- `88/89/66+89` memory-destination absolute disp32
- `C6/C7/66+C7` immediate-to-memory absolute disp32
- `C6/C7/66+C7` immediate-to-register `ModRM.mod=11`
- default-32 non-SIB base-only no-displacement memory addressing
- default-32 non-SIB `mod=01` signed disp8 memory addressing
- default-32 non-SIB `mod=10` signed disp32 memory addressing
- default-32 base-only SIB memory addressing
- default-32 SIB no-base disp32 memory addressing
- default-32 base-present indexed SIB memory addressing
- default-32 no-base indexed SIB disp32 memory addressing

Explicit Pass 6H-1 non-claims:

- this is not full Rung 6 completion
- this does not claim the full Appendix D MOV matrix
- this proves only bounded Pass 6H-1 `0x67` direct disp16 MOV support
- broader 16-bit addressing remains unsupported
- 16-bit register-based addressing remains unsupported
- 16-bit `mod=01` signed disp8 addressing remains unsupported
- 16-bit `mod=10` disp16 addressing remains unsupported
- BP/segment semantics remain unsupported
- segment-base addition remains unsupported
- protected/page/segment behavior remains unsupported
- full `0x67` architecture is not implemented
- broad `0x66` architecture is not implemented
- broader MOV families and the full MOV matrix remain unverified
- final Rung 6 acceptance remains blocked

Remaining Rung 6 blockers include broader 16-bit addressing, 16-bit
register-based addressing, 16-bit `mod=01` signed disp8, 16-bit `mod=10`
disp16, BP/segment semantics, segment-base/protected/page behavior, broader MOV
families, full MOV matrix verification, and final Rung 6 acceptance.

Rung 5 regression still passes at this committed state.
Existing Rung 6 Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, Pass 6E-3,
Pass 6F-1, Pass 6F-2, Pass 6G-1, and Pass 6G-2 simulations still pass.
Rung 7 remains blocked.

## Pass 6G-2 Evidence

Date recorded: 2026-05-27 UTC.

Commands run after commit `f0c43570e7758623842a44d1ba9d14355edcf06a`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
make rung6-pass6e1-sim
make rung6-pass6e2-sim
make rung6-pass6e3-sim
make rung6-pass6f1-sim
make rung6-pass6f2-sim
make rung6-pass6g1-sim
make rung6-pass6g2-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `f0c43570e7758623842a44d1ba9d14355edcf06a`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- `make codegen` and `make ucode` did not leave tracked generated drift
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `make rung6-pass6e1-sim` | PASS |
| `make rung6-pass6e2-sim` | PASS |
| `make rung6-pass6e3-sim` | PASS |
| `make rung6-pass6f1-sim` | PASS |
| `make rung6-pass6f2-sim` | PASS |
| `make rung6-pass6g1-sim` | PASS |
| `make rung6-pass6g2-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing non-fatal Icarus/Iverilog warnings about time units, constant selects,
and ignored `unique` case qualities were present during simulation builds. They
did not fail the commands.

The bounded Rung 6 Pass 6G-2 simulation proves only the authorized default-32
no-base indexed SIB disp32 effective-address slice:

- `8A /r` byte loads from no-base indexed SIB disp32 memory source pass for
  the authorized default-32 SIB subset
- `8B /r` dword loads from no-base indexed SIB disp32 memory source pass for
  the authorized default-32 SIB subset
- `0x66` + `8B /r` word loads from no-base indexed SIB disp32 memory source
  pass for the authorized default-32 SIB subset
- `88 /r` byte stores to no-base indexed SIB disp32 memory destination pass for
  the authorized default-32 SIB subset
- `89 /r` dword stores to no-base indexed SIB disp32 memory destination pass
  for the authorized default-32 SIB subset
- `0x66` + `89 /r` word stores to no-base indexed SIB disp32 memory
  destination pass for the authorized default-32 SIB subset
- `C6 /0 ib` byte immediate stores to no-base indexed SIB disp32 memory
  destination pass for the authorized default-32 SIB subset
- `C7 /0 id` dword immediate stores to no-base indexed SIB disp32 memory
  destination pass for the authorized default-32 SIB subset
- `0x66` + `C7 /0 iw` word immediate stores to no-base indexed SIB disp32
  memory destination pass for the authorized default-32 SIB subset
- `EA_CALC_32` computes `T2 = meta_disp_value + (committed GPR[SIB.index] <<
  SIB.scale)` for `ModRM.mod=00`, `ModRM.r/m=100`, `SIB.base=101`,
  `SIB.index!=100`, disp32-present forms
- the no-base indexed disp32 form does not use a committed base GPR
  contribution
- ESP is not used as an index because `SIB.index=100` means no index
- existing Pass 6G-1 index-read sequencing in `EA_CALC_32` remains reused
- existing `EA_CALC_32` scale arithmetic remains reused
- no second physical committed-GPR read port is added
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` are issued for the authorized
  `C6/C7` immediate-to-memory forms
- direct absolute disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 non-SIB base-only no-displacement, `mod=01` signed disp8, and
  `mod=10` signed disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 base-only SIB memory-source, memory-destination, and
  immediate-to-memory behavior from Pass 6F-1 remains preserved
- default-32 SIB no-base disp32 memory-source, memory-destination, and
  immediate-to-memory behavior from Pass 6F-2 remains preserved
- default-32 base-present indexed SIB memory-source, memory-destination, and
  immediate-to-memory behavior from Pass 6G-1 remains preserved
- `ModRM.mod=11` register forms remain preserved
- no new frozen-spec field, opcode class, service ID, commit mask, or
  microinstruction is used
- EFLAGS remain unchanged
- no `0x67` address-size behavior is implemented
- no `EA_CALC_16` is implemented
- no 16-bit addressing behavior is implemented
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6G-2 MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, Pass 6E-3,
Pass 6F-1, Pass 6F-2, and Pass 6G-1 simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11`
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11`
- `8A/8B/66+8B` memory-source absolute disp32
- `88/89/66+89` memory-destination absolute disp32
- `C6/C7/66+C7` immediate-to-memory absolute disp32
- `C6/C7/66+C7` immediate-to-register `ModRM.mod=11`
- default-32 non-SIB base-only no-displacement memory addressing from
  Pass 6E-1
- default-32 non-SIB `mod=01` signed disp8 memory addressing from Pass 6E-2
- default-32 non-SIB `mod=10` signed disp32 memory addressing from Pass 6E-3
- default-32 base-only SIB memory addressing from Pass 6F-1
- default-32 SIB no-base disp32 memory addressing from Pass 6F-2
- default-32 base-present indexed SIB memory addressing from Pass 6G-1

Explicit Pass 6G-2 non-claims:

- this is not full Rung 6 completion
- this does not claim the full Appendix D MOV matrix
- this proves only bounded Pass 6G-2 default-32 no-base indexed SIB support
- no `0x67` address-size behavior is implemented
- the `0x67` test only proves standalone `0x67` prefix-byte handling at this
  decoder exposure level; it does not claim a full prefixed sequence was
  proven as one unsupported instruction
- no `EA_CALC_16` is implemented
- no 16-bit addressing behavior is implemented
- no protected-mode/page/segment behavior is implemented
- broader MOV families and the full MOV matrix remain unverified
- final Rung 6 acceptance remains blocked

Remaining Rung 6 blockers include `0x67` address-size behavior, `EA_CALC_16`,
16-bit addressing, protected/page/segment behavior, broader MOV families, full
MOV matrix verification, and final Rung 6 acceptance.

Rung 5 regression still passes at this committed state.
Existing Rung 6 Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, Pass 6E-3,
Pass 6F-1, Pass 6F-2, and Pass 6G-1 simulations still pass.
Rung 7 remains blocked.

## Pass 6G-1 Evidence

Date recorded: 2026-05-26 UTC.

Commands run after commit `8428c9abf775c012354c93167ff9b0c617c1f338`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
make rung6-pass6e1-sim
make rung6-pass6e2-sim
make rung6-pass6e3-sim
make rung6-pass6f1-sim
make rung6-pass6f2-sim
make rung6-pass6g1-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `8428c9abf775c012354c93167ff9b0c617c1f338`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- `make codegen` and `make ucode` did not leave tracked generated drift
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `make rung6-pass6e1-sim` | PASS |
| `make rung6-pass6e2-sim` | PASS |
| `make rung6-pass6e3-sim` | PASS |
| `make rung6-pass6f1-sim` | PASS |
| `make rung6-pass6f2-sim` | PASS |
| `make rung6-pass6g1-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing non-fatal Icarus/Iverilog warnings about time units, constant selects,
and ignored `unique` case qualities were present during simulation builds. They
did not fail the commands.

The bounded Rung 6 Pass 6G-1 simulation proves only the authorized default-32
base-present indexed SIB effective-address slice:

- `8A /r` byte loads from base-present indexed SIB memory source pass for the
  authorized default-32 SIB subset
- `8B /r` dword loads from base-present indexed SIB memory source pass for the
  authorized default-32 SIB subset
- `0x66` + `8B /r` word loads from base-present indexed SIB memory source pass
  for the authorized default-32 SIB subset
- `88 /r` byte stores to base-present indexed SIB memory destination pass for
  the authorized default-32 SIB subset
- `89 /r` dword stores to base-present indexed SIB memory destination pass for
  the authorized default-32 SIB subset
- `0x66` + `89 /r` word stores to base-present indexed SIB memory destination
  pass for the authorized default-32 SIB subset
- `C6 /0 ib` byte immediate stores to base-present indexed SIB memory
  destination pass for the authorized default-32 SIB subset
- `C7 /0 id` dword immediate stores to base-present indexed SIB memory
  destination pass for the authorized default-32 SIB subset
- `0x66` + `C7 /0 iw` word immediate stores to base-present indexed SIB memory
  destination pass for the authorized default-32 SIB subset
- `EA_CALC_32` computes `T2` from committed `GPR[SIB.base]`, committed
  `GPR[SIB.index]` shifted left by `SIB.scale`, and optional displacement for
  authorized base-present indexed SIB forms
- `ModRM.mod=00` supports `SIB.index!=100` with `SIB.base!=101`, no
  displacement
- `ModRM.mod=01` supports `SIB.index!=100` with any `SIB.base`, including
  `101` as EBP, plus sign-extended disp8
- `ModRM.mod=10` supports `SIB.index!=100` with any `SIB.base`, including
  `101` as EBP, plus disp32
- ESP is not used as an index because `SIB.index=100` means no index
- no no-base indexed SIB form is implemented
- the existing single committed-GPR read path is reused to sequence base and
  index reads
- no second physical committed-GPR read port is added
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` are issued for the authorized
  `C6/C7` immediate-to-memory forms
- direct absolute disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 non-SIB base-only no-displacement, `mod=01` signed disp8, and
  `mod=10` signed disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 base-only SIB memory-source, memory-destination, and
  immediate-to-memory behavior from Pass 6F-1 remains preserved
- default-32 SIB no-base disp32 memory-source, memory-destination, and
  immediate-to-memory behavior from Pass 6F-2 remains preserved
- `ModRM.mod=11` register forms remain preserved
- no new frozen-spec field, opcode class, service ID, commit mask, or
  microinstruction is used
- EFLAGS remain unchanged
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6G-1 MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, Pass 6E-3,
Pass 6F-1, and Pass 6F-2 simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11`
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11`
- `8A/8B/66+8B` memory-source absolute disp32
- `88/89/66+89` memory-destination absolute disp32
- `C6/C7/66+C7` immediate-to-memory absolute disp32
- `C6/C7/66+C7` immediate-to-register `ModRM.mod=11`
- default-32 non-SIB base-only no-displacement memory addressing from
  Pass 6E-1
- default-32 non-SIB `mod=01` signed disp8 memory addressing from Pass 6E-2
- default-32 non-SIB `mod=10` signed disp32 memory addressing from Pass 6E-3
- default-32 base-only SIB memory addressing from Pass 6F-1
- default-32 SIB no-base disp32 memory addressing from Pass 6F-2

Explicit Pass 6G-1 non-claims:

- this is not full Rung 6 completion
- this does not claim the full Appendix D MOV matrix
- this proves only bounded Pass 6G-1 default-32 base-present indexed SIB
  support
- no-base indexed SIB remains unsupported
- no `0x67` address-size behavior is implemented
- the `0x67` test only proves standalone `0x67` prefix-byte handling at this
  decoder exposure level; it does not claim a full prefixed sequence was
  proven as one unsupported instruction
- no `EA_CALC_16` is implemented
- no 16-bit addressing behavior is implemented
- no protected-mode/page/segment behavior is implemented
- broader MOV families and the full MOV matrix remain unverified
- final Rung 6 acceptance remains blocked

Remaining Rung 6 blockers include no-base indexed SIB, `0x67` address-size
behavior, `EA_CALC_16`, 16-bit addressing, protected/page/segment behavior,
broader MOV families, full MOV matrix verification, and final Rung 6
acceptance.

Rung 5 regression still passes at this committed state.
Existing Rung 6 Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, Pass 6E-3,
Pass 6F-1, and Pass 6F-2 simulations still pass.
Rung 7 remains blocked.

## Pass 6F-2 Evidence

Date recorded: 2026-05-26 UTC.

Commands run after commit `fc181dbd245c284618c21aa0d82480c8234d16ba`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
make rung6-pass6e1-sim
make rung6-pass6e2-sim
make rung6-pass6e3-sim
make rung6-pass6f1-sim
make rung6-pass6f2-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `fc181dbd245c284618c21aa0d82480c8234d16ba`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- `make codegen` and `make ucode` did not leave tracked generated drift
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `make rung6-pass6e1-sim` | PASS |
| `make rung6-pass6e2-sim` | PASS |
| `make rung6-pass6e3-sim` | PASS |
| `make rung6-pass6f1-sim` | PASS |
| `make rung6-pass6f2-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing non-fatal Icarus/Iverilog warnings about time units, constant selects,
and ignored `unique` case qualities were present during simulation builds. They
did not fail the commands.

The bounded Rung 6 Pass 6F-2 simulation proves only the authorized default-32
SIB no-base disp32 effective-address slice:

- `8A /r` byte loads from no-base SIB disp32 memory source pass for the
  authorized default-32 SIB subset
- `8B /r` dword loads from no-base SIB disp32 memory source pass for the
  authorized default-32 SIB subset
- `0x66` + `8B /r` word loads from no-base SIB disp32 memory source pass for
  the authorized default-32 SIB subset
- `88 /r` byte stores to no-base SIB disp32 memory destination pass for the
  authorized default-32 SIB subset
- `89 /r` dword stores to no-base SIB disp32 memory destination pass for the
  authorized default-32 SIB subset
- `0x66` + `89 /r` word stores to no-base SIB disp32 memory destination pass
  for the authorized default-32 SIB subset
- `C6 /0 ib` byte immediate stores to no-base SIB disp32 memory destination
  pass for the authorized default-32 SIB subset
- `C7 /0 id` dword immediate stores to no-base SIB disp32 memory destination
  pass for the authorized default-32 SIB subset
- `0x66` + `C7 /0 iw` word immediate stores to no-base SIB disp32 memory
  destination pass for the authorized default-32 SIB subset
- `EA_CALC_32` computes `T2 = meta_disp_value` for `ModRM.mod=00`,
  `ModRM.r/m=100`, `SIB.index=100`, `SIB.base=101`, disp32-present forms
- the no-base disp32 form does not use a committed base GPR contribution
- no index read path is used
- no scale arithmetic is used
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` are issued for the authorized
  `C6/C7` immediate-to-memory forms
- direct absolute disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 non-SIB base-only no-displacement, `mod=01` signed disp8, and
  `mod=10` signed disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 base-only SIB memory-source, memory-destination, and
  immediate-to-memory behavior from Pass 6F-1 remains preserved
- `ModRM.mod=11` register forms remain preserved
- no new frozen-spec field, opcode class, service ID, commit mask, or
  microinstruction is used
- EFLAGS remain unchanged
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6F-2 MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, Pass 6E-3, and
Pass 6F-1 simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11`
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11`
- `8A/8B/66+8B` memory-source absolute disp32
- `88/89/66+89` memory-destination absolute disp32
- `C6/C7/66+C7` immediate-to-memory absolute disp32
- `C6/C7/66+C7` immediate-to-register `ModRM.mod=11`
- default-32 non-SIB base-only no-displacement memory addressing from
  Pass 6E-1
- default-32 non-SIB `mod=01` signed disp8 memory addressing from Pass 6E-2
- default-32 non-SIB `mod=10` signed disp32 memory addressing from Pass 6E-3
- default-32 base-only SIB memory addressing from Pass 6F-1

Explicit Pass 6F-2 non-claims:

- this is not full Rung 6 completion
- this does not claim the full Appendix D MOV matrix
- this proves only bounded Pass 6F-2 default-32 SIB no-base disp32 support
- `SIB.index!=100` remains unsupported
- index read plumbing remains unsupported
- scale arithmetic remains unsupported
- broader indexed SIB forms remain unsupported
- no `0x67` address-size behavior is implemented
- the `0x67` test only proves standalone `0x67` prefix-byte handling at this
  decoder exposure level; it does not claim a full prefixed sequence was
  proven as one unsupported instruction
- no `EA_CALC_16` is implemented
- no 16-bit addressing behavior is implemented
- no protected-mode/page/segment behavior is implemented
- broader MOV families and the full MOV matrix remain unverified
- final Rung 6 acceptance remains blocked

Remaining Rung 6 blockers include broader SIB, `SIB.index!=100`, index read
plumbing, scale arithmetic, `0x67` address-size behavior, `EA_CALC_16`,
16-bit addressing, protected/page/segment behavior, broader MOV families, full
MOV matrix verification, and final Rung 6 acceptance.

Rung 5 regression still passes at this committed state.
Existing Rung 6 Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, Pass 6E-3, and
Pass 6F-1 simulations still pass.
Rung 7 remains blocked.

## Pass 6F-1 Evidence

Date recorded: 2026-05-26 UTC.

Commands run after commit `f85ddde47bdc15b3ff14fc8cea87b8da48987d73`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
make rung6-pass6e1-sim
make rung6-pass6e2-sim
make rung6-pass6e3-sim
make rung6-pass6f1-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `f85ddde47bdc15b3ff14fc8cea87b8da48987d73`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `make rung6-pass6e1-sim` | PASS |
| `make rung6-pass6e2-sim` | PASS |
| `make rung6-pass6e3-sim` | PASS |
| `make rung6-pass6f1-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing non-fatal Icarus/Iverilog warnings about time units, constant selects,
and ignored `unique` case qualities were present during simulation builds. They
did not fail the commands.

The bounded Rung 6 Pass 6F-1 simulation proves only the authorized default-32
base-only SIB effective-address slice:

- `8A /r` byte loads from base-only SIB memory source pass for the authorized
  default-32 SIB subset
- `8B /r` dword loads from base-only SIB memory source pass for the authorized
  default-32 SIB subset
- `0x66` + `8B /r` word loads from base-only SIB memory source pass for the
  authorized default-32 SIB subset
- `88 /r` byte stores to base-only SIB memory destination pass for the
  authorized default-32 SIB subset
- `89 /r` dword stores to base-only SIB memory destination pass for the
  authorized default-32 SIB subset
- `0x66` + `89 /r` word stores to base-only SIB memory destination pass for
  the authorized default-32 SIB subset
- `C6 /0 ib` byte immediate stores to base-only SIB memory destination pass for
  the authorized default-32 SIB subset
- `C7 /0 id` dword immediate stores to base-only SIB memory destination pass
  for the authorized default-32 SIB subset
- `0x66` + `C7 /0 iw` word immediate stores to base-only SIB memory
  destination pass for the authorized default-32 SIB subset
- `EA_CALC_32` computes `T2` from committed 32-bit `GPR[SIB.base]` for
  authorized base-only SIB forms
- `ModRM.mod=00` supports `SIB.index=100` and `SIB.base!=101`, including ESP
  base through `SIB.base=100`
- `ModRM.mod=01` supports `SIB.index=100` with any `SIB.base`, including
  `101` as EBP, plus sign-extended disp8
- `ModRM.mod=10` supports `SIB.index=100` with any `SIB.base`, including
  `101` as EBP, plus disp32
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` are issued for the authorized
  `C6/C7` immediate-to-memory forms
- direct absolute disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 non-SIB base-only no-displacement, `mod=01` signed disp8, and
  `mod=10` signed disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- `ModRM.mod=11` register forms remain preserved
- no new frozen-spec field, opcode class, service ID, commit mask, or
  microinstruction is used
- EFLAGS remain unchanged
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6F-1 MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, and Pass 6E-3
simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11`
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11`
- `8A/8B/66+8B` memory-source absolute disp32
- `88/89/66+89` memory-destination absolute disp32
- `C6/C7/66+C7` immediate-to-memory absolute disp32
- `C6/C7/66+C7` immediate-to-register `ModRM.mod=11`
- default-32 non-SIB base-only no-displacement memory addressing from
  Pass 6E-1
- default-32 non-SIB `mod=01` signed disp8 memory addressing from Pass 6E-2
- default-32 non-SIB `mod=10` signed disp32 memory addressing from Pass 6E-3

Explicit Pass 6F-1 non-claims:

- this is not full Rung 6 completion
- this does not claim the full Appendix D MOV matrix
- this proves only bounded Pass 6F-1 default-32 base-only SIB
  effective-address support
- `SIB.index!=100` remains unsupported
- index read plumbing remains unsupported
- scale arithmetic remains unsupported
- `SIB.base=101` with `ModRM.mod=00` no-base disp32 remains unsupported
- no `0x67` address-size behavior is implemented
- the `0x67` test only proves standalone `0x67` prefix-byte handling at this
  decoder exposure level; it does not claim a full prefixed sequence was
  proven as one unsupported instruction
- no `EA_CALC_16` is implemented
- no 16-bit addressing behavior is implemented
- no protected-mode/page/segment behavior is implemented
- broader MOV families and the full MOV matrix remain unverified
- final Rung 6 acceptance remains blocked

Remaining Rung 6 blockers include broader SIB, `SIB.index!=100`, index read
plumbing, scale arithmetic, `SIB.base=101` with `ModRM.mod=00` no-base disp32,
`0x67` address-size behavior, `EA_CALC_16`, 16-bit addressing,
protected/page/segment behavior, broader MOV families, full MOV matrix
verification, and final Rung 6 acceptance.

Rung 5 regression still passes at this committed state.
Existing Rung 6 Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, Pass 6E-2, and Pass 6E-3
simulations still pass.
Rung 7 remains blocked.

## Pass 6E-3 Evidence

Date recorded: 2026-05-25 UTC.

Commands run after commit `4f26a58a1821641cf8ff16528c943fa40cb4fe35`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
make rung6-pass6e1-sim
make rung6-pass6e2-sim
make rung6-pass6e3-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `4f26a58a1821641cf8ff16528c943fa40cb4fe35`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `make rung6-pass6e1-sim` | PASS |
| `make rung6-pass6e2-sim` | PASS |
| `make rung6-pass6e3-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing non-fatal Icarus/Iverilog warnings about time units, constant selects,
and ignored `unique` case qualities were present during simulation builds. They
did not fail the commands.

The bounded Rung 6 Pass 6E-3 simulation proves only the authorized default-32
non-SIB `mod=10` signed disp32 effective-address slice:

- `8A /r` byte loads from signed disp32 base memory source pass for the
  authorized default-32 non-SIB `mod=10` subset
- `8B /r` dword loads from signed disp32 base memory source pass for the
  authorized default-32 non-SIB `mod=10` subset
- `0x66` + `8B /r` word loads from signed disp32 base memory source pass for
  the authorized default-32 non-SIB `mod=10` subset
- `88 /r` byte stores to signed disp32 base memory destination pass for the
  authorized default-32 non-SIB `mod=10` subset
- `89 /r` dword stores to signed disp32 base memory destination pass for the
  authorized default-32 non-SIB `mod=10` subset
- `0x66` + `89 /r` word stores to signed disp32 base memory destination pass
  for the authorized default-32 non-SIB `mod=10` subset
- `C6 /0 ib` byte immediate stores to signed disp32 base memory destination
  pass for the authorized default-32 non-SIB `mod=10` subset
- `C7 /0 id` dword immediate stores to signed disp32 base memory destination
  pass for the authorized default-32 non-SIB `mod=10` subset
- `0x66` + `C7 /0 iw` word immediate stores to signed disp32 base memory
  destination pass for the authorized default-32 non-SIB `mod=10` subset
- `EA_CALC_32` computes `T2` from the selected committed 32-bit GPR plus the
  disp32 displacement
- EBP base is allowed through `ModRM.mod=10 r/m=101` with disp32
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` are issued for the authorized
  `C6/C7` immediate-to-memory forms
- direct absolute disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 base-only no-displacement memory-source, memory-destination, and
  immediate-to-memory behavior from Pass 6E-1 remains preserved
- default-32 non-SIB `mod=01` signed disp8 memory-source, memory-destination,
  and immediate-to-memory behavior from Pass 6E-2 remains preserved
- `ModRM.mod=11` register forms remain preserved
- no new frozen-spec field, opcode class, service ID, commit mask, or
  microinstruction is used
- EFLAGS remain unchanged
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6E-3 MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, and Pass 6E-2 simulations still
prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11`
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11`
- `8A/8B/66+8B` memory-source absolute disp32
- `88/89/66+89` memory-destination absolute disp32
- `C6/C7/66+C7` immediate-to-memory absolute disp32
- `C6/C7/66+C7` immediate-to-register `ModRM.mod=11`
- default-32 non-SIB base-only no-displacement memory addressing from
  Pass 6E-1
- default-32 non-SIB `mod=01` signed disp8 memory addressing from Pass 6E-2

Explicit Pass 6E-3 non-claims:

- this is not full Rung 6 completion
- this does not claim the full Appendix D MOV matrix
- this proves only bounded Pass 6E-3 default-32 non-SIB `mod=10` signed disp32
  effective-address support
- SIB remains unsupported
- ESP base remains unsupported because `ModRM.r/m=100` is SIB
- no `0x67` address-size behavior is implemented
- the `0x67` test only proves standalone `0x67` prefix-byte handling at this
  decoder exposure level; it does not claim a full prefixed sequence was
  proven as one unsupported instruction
- no `EA_CALC_16` is implemented
- no 16-bit addressing behavior is implemented
- no protected-mode/page/segment behavior is implemented
- broader MOV families and the full MOV matrix remain unverified
- final Rung 6 acceptance remains blocked

Remaining Rung 6 blockers include SIB/index/scale, ESP-through-SIB, `0x67`
address-size behavior, `EA_CALC_16`, 16-bit addressing, protected/page/segment
behavior, broader MOV families, full MOV matrix verification, and final Rung 6
acceptance.

Rung 5 regression still passes at this committed state.
Existing Rung 6 Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, Pass 6E-1, and Pass 6E-2 simulations still
pass.
Rung 7 remains blocked.

## Pass 6E-2 Evidence

Date recorded: 2026-05-24 UTC.

Commands run after commit `fdcc133cea9ac83bb83d0cf67bed608755f56dd0`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
make rung6-pass6e1-sim
make rung6-pass6e2-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `fdcc133cea9ac83bb83d0cf67bed608755f56dd0`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `make rung6-pass6e1-sim` | PASS |
| `make rung6-pass6e2-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing non-fatal Icarus/Iverilog warnings about time units, constant selects,
and ignored `unique` case qualities were present during simulation builds. They
did not fail the commands.

The bounded Rung 6 Pass 6E-2 simulation proves only the authorized default-32
non-SIB `mod=01` signed disp8 effective-address slice:

- `8A /r` byte loads from signed disp8 base memory source pass for the
  authorized default-32 non-SIB `mod=01` subset
- `8B /r` dword loads from signed disp8 base memory source pass for the
  authorized default-32 non-SIB `mod=01` subset
- `0x66` + `8B /r` word loads from signed disp8 base memory source pass for
  the authorized default-32 non-SIB `mod=01` subset
- `88 /r` byte stores to signed disp8 base memory destination pass for the
  authorized default-32 non-SIB `mod=01` subset
- `89 /r` dword stores to signed disp8 base memory destination pass for the
  authorized default-32 non-SIB `mod=01` subset
- `0x66` + `89 /r` word stores to signed disp8 base memory destination pass
  for the authorized default-32 non-SIB `mod=01` subset
- `C6 /0 ib` byte immediate stores to signed disp8 base memory destination
  pass for the authorized default-32 non-SIB `mod=01` subset
- `C7 /0 id` dword immediate stores to signed disp8 base memory destination
  pass for the authorized default-32 non-SIB `mod=01` subset
- `0x66` + `C7 /0 iw` word immediate stores to signed disp8 base memory
  destination pass for the authorized default-32 non-SIB `mod=01` subset
- `EA_CALC_32` computes `T2` from the selected committed 32-bit GPR plus the
  sign-extended disp8 displacement
- EBP base is allowed only through `ModRM.mod=01 r/m=101` with signed disp8
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` are issued for the authorized
  `C6/C7` immediate-to-memory forms
- direct absolute disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- default-32 base-only no-displacement memory-source, memory-destination, and
  immediate-to-memory behavior from Pass 6E-1 remains preserved
- `ModRM.mod=11` register forms remain preserved
- no new frozen-spec field, opcode class, service ID, commit mask, or
  microinstruction is used
- EFLAGS remain unchanged
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6E-2 MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, and Pass 6E-1 simulations still prove
preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11`
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11`
- `8A/8B/66+8B` memory-source absolute disp32
- `88/89/66+89` memory-destination absolute disp32
- `C6/C7/66+C7` immediate-to-memory absolute disp32
- `C6/C7/66+C7` immediate-to-register `ModRM.mod=11`
- default-32 non-SIB base-only no-displacement memory addressing from
  Pass 6E-1

Explicit Pass 6E-2 non-claims:

- this is not full Rung 6 completion
- this does not claim the full Appendix D MOV matrix
- this proves only bounded Pass 6E-2 default-32 non-SIB `mod=01` signed disp8
  effective-address support
- SIB remains unsupported
- ESP base remains unsupported because `ModRM.r/m=100` is SIB
- `mod=10` remains unsupported
- no `0x67` address-size behavior is implemented
- the `0x67` test only proves standalone `0x67` prefix-byte handling at this
  decoder exposure level; it does not claim a full prefixed sequence was
  proven as one unsupported instruction
- no `EA_CALC_16` is implemented
- no 16-bit addressing behavior is implemented
- no protected-mode/page/segment behavior is implemented
- broader MOV families and the full MOV matrix remain unverified
- final Rung 6 acceptance remains blocked

Rung 5 regression still passes at this committed state.
Existing Rung 6 Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, Pass 6D-1, and Pass 6E-1 simulations still pass.
Rung 7 remains blocked.

## Pass 6E-1 Evidence

Date recorded: 2026-05-22 UTC.

Commands run after commit `98560e78506f3d3e72b60e7b7e85cf0592031c15`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
make rung6-pass6e1-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `98560e78506f3d3e72b60e7b7e85cf0592031c15`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `make rung6-pass6e1-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing Icarus/Iverilog warnings about time units, constant selects, and
ignored `unique` case qualities were present during simulation builds. They did
not fail the commands.

The bounded Rung 6 Pass 6E-1 simulation proves only the authorized default-32
base-only no-displacement effective-address slice:

- `8A /r` byte loads from base-only memory source pass for the authorized
  default-32 no-displacement subset
- `8B /r` dword loads from base-only memory source pass for the authorized
  default-32 no-displacement subset
- `0x66` + `8B /r` word loads from base-only memory source pass for the
  authorized default-32 no-displacement subset
- `88 /r` byte stores to base-only memory destination pass for the authorized
  default-32 no-displacement subset
- `89 /r` dword stores to base-only memory destination pass for the authorized
  default-32 no-displacement subset
- `0x66` + `89 /r` word stores to base-only memory destination pass for the
  authorized default-32 no-displacement subset
- `C6 /0 ib` byte immediate stores to base-only memory destination pass for the
  authorized default-32 no-displacement subset
- `C7 /0 id` dword immediate stores to base-only memory destination pass for
  the authorized default-32 no-displacement subset
- `0x66` + `C7 /0 iw` word immediate stores to base-only memory destination
  pass for the authorized default-32 no-displacement subset
- `EA_CALC_32` computes `T2` from the selected committed 32-bit GPR for
  authorized base-only forms
- `LOAD_RM8`, `LOAD_RM16`, and `LOAD_RM32` are issued for the authorized
  memory-source read widths
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  memory-destination write widths
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` are issued for the authorized
  `C6/C7` immediate-to-memory forms
- direct absolute disp32 memory-source, memory-destination, and
  immediate-to-memory behavior remains preserved
- `ModRM.mod=11` register forms remain preserved
- `C6 [EAX], imm8` is treated as memory, not immediate-to-register
- no new architectural write owner is created by the committed-GPR read
  plumbing for `EA_CALC_32`
- no new frozen-spec field, opcode class, service ID, commit mask, or
  microinstruction is used
- EFLAGS remain unchanged
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6E-1 MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, and Pass 6D-1 simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11`
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11`
- `8A/8B/66+8B` memory-source absolute disp32
- `88/89/66+89` memory-destination absolute disp32
- `C6/C7/66+C7` immediate-to-memory absolute disp32
- `C6/C7/66+C7` immediate-to-register `ModRM.mod=11`

Explicit Pass 6E-1 non-claims:

- this is not full Rung 6 completion
- this does not claim the full Appendix D MOV matrix
- SIB remains unsupported
- ESP base remains unsupported in this pass because `ModRM.r/m=100` is SIB
- EBP base remains unsupported in this pass because `ModRM.mod=00 r/m=101` is
  direct disp32, not EBP
- disp8 / `mod=01` remains unsupported
- `mod=10` remains unsupported
- no `0x67` address-size behavior is implemented
- the `0x67` test only proves standalone `0x67` prefix-byte handling at this
  decoder exposure level; it does not claim the full `67 8B 00` prefixed
  sequence was proven as one unsupported instruction
- no `EA_CALC_16` is implemented
- no 16-bit addressing behavior is implemented
- no protected-mode/page/segment behavior is implemented
- broader MOV families and the full MOV matrix remain unverified
- final Rung 6 acceptance remains blocked

Rung 5 regression still passes at this committed state.
Existing Rung 6 Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, Pass 6C-1, and Pass 6D-1 simulations still pass.
Rung 7 remains blocked.

## Pass 6C-1 Evidence

Date recorded: 2026-05-08 UTC.

Commands run after commit `ba37a22bd4c38e940e385c08c7a087127f2dfd86`:

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
make rung6-pass6c1-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `ba37a22bd4c38e940e385c08c7a087127f2dfd86`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing Icarus/Iverilog warnings about time units, constant selects, and
ignored `unique` case qualities were present during simulation builds. They did
not fail the commands.

The bounded Rung 6 Pass 6C-1 simulation proves only the authorized
immediate-to-memory absolute-disp32 slice:

- `C6 /0 ib` byte immediate stores to absolute disp32 memory destination pass
- `C7 /0 id` dword immediate stores to absolute disp32 memory destination pass
- `0x66` + `C7 /0 iw` word immediate stores to absolute disp32 memory
  destination pass
- `FETCH_IMM8` is issued for the authorized `C6 /0 ib` form
- `FETCH_IMM32` is issued for the authorized `C7 /0 id` form
- `FETCH_IMM16` is issued for the authorized `0x66` + `C7 /0 iw` form
- `EA_CALC_32` is issued once per authorized immediate-to-memory MOV and is
  bounded to direct absolute disp32 only
- `STORE_RM8`, `STORE_RM16`, and `STORE_RM32` are issued for the authorized
  immediate-to-memory write widths only
- `STORE_RM*` completes before `ENDI`
- immediate-to-memory MOV uses `ENDI CM_NOP|CM_EIP`, not `CM_MOV_REG`
- no new memory-store commit mask, frozen-spec field, opcode class, service ID,
  microinstruction, or commit-time memory-store policy is used
- final memory values match the expected byte, word, and dword immediate stores
- EFLAGS remain unchanged
- no unintended GPR changes occur for immediate-to-memory MOV
- final EIP matches fall-through for the bounded Pass 6C-1 instruction sequence
- `C6/C7` register-destination forms with `ModRM.mod=11` remain unsupported
- `C6/C7` non-`/0` extensions remain unsupported
- no SIB, base/index/scale, disp8, `mod=01`, or `mod=10` memory addressing is
  implemented
- no `0x67` or 16-bit addressing behavior is implemented
- no `EA_CALC_16` is implemented
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6C-1 immediate-to-memory
  MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1, and
Pass 6B-1 simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11` only
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11` only
- `8A /r` byte loads from absolute disp32 memory source
- `8B /r` dword loads from absolute disp32 memory source
- `0x66` + `8B /r` word loads from absolute disp32 memory source
- `88 /r` byte stores to absolute disp32 memory destination
- `89 /r` dword stores to absolute disp32 memory destination
- `0x66` + `89 /r` word stores to absolute disp32 memory destination

Rung 5 regression still passes at this committed state.
Rung 7 remains blocked.

## Pass 6D-1 Evidence

Date recorded: 2026-05-09 UTC.

Commands run after commit `3ea9e52c02af79c62b9499d122e1cf7eef0a6e26`:

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
make rung6-pass6c1-sim
make rung6-pass6d1-sim
git diff --check
git status --short
```

Run state:

- tested implementation commit:
  `3ea9e52c02af79c62b9499d122e1cf7eef0a6e26`
- verification was run after that implementation commit
- final `git status --short` from the run was clean
- this documentation update is separate from the tested implementation commit

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
| `make rung6-pass6c1-sim` | PASS |
| `make rung6-pass6d1-sim` | PASS |
| `git diff --check` | PASS |
| `git status --short` | PASS, clean output |

Existing Icarus/Iverilog warnings about time units, constant selects, and
ignored `unique` case qualities were present during simulation builds. They did
not fail the commands.

The bounded Rung 6 Pass 6D-1 simulation proves only the authorized
immediate-to-register `ModRM.mod=11` slice:

- `C6 /0 ib` byte immediate writes to register destination pass
- `C7 /0 id` dword immediate writes to register destination pass
- `0x66` + `C7 /0 iw` word immediate writes to register destination pass
- `FETCH_IMM8` is issued for the authorized `C6 /0 ib` form
- `FETCH_IMM32` is issued for the authorized `C7 /0 id` form
- `FETCH_IMM16` is issued for the authorized `0x66` + `C7 /0 iw` form
- `STAGE_GPR` is issued with `T4`
- `ENDI CM_MOV_REG` is used for architectural GPR visibility
- architectural GPR visibility remains commit-only through `CM_MOV_REG`
- existing byte-register commit behavior is preserved, including high-byte
  registers for `r8`
- existing 16-bit low-word merge behavior is preserved for `0x66` + `C7`
- no new commit mask, frozen-spec field, opcode class, service ID, or
  microinstruction is used
- no `EA_CALC_32`, `LOAD_RM*`, `STORE_RM*`, or memory bus behavior occurs for
  register-destination `C6/C7`
- EFLAGS remain unchanged
- no unintended memory writes occur for immediate-to-register MOV
- final EIP matches fall-through for the bounded Pass 6D-1 instruction sequence
- `C6/C7` non-`/0` extensions remain unsupported
- `C6/C7` memory addressing beyond already verified direct absolute disp32
  remains unsupported
- no SIB, base/index/scale, disp8, `mod=01`, or `mod=10` memory addressing is
  implemented
- no `0x67` or 16-bit addressing behavior is implemented
- no `EA_CALC_16` is implemented
- no protected-mode/page/segment behavior is implemented
- no fault occurs during the authorized bounded Pass 6D-1 immediate-to-register
  MOV sequence

The existing Pass 2, Pass 4A, Pass 4B, Pass 5A, Pass 5B, Pass 6A-1,
Pass 6B-1, and Pass 6C-1 simulations still prove preservation of:

- `B8-BF` `MOV r32, imm32`
- `B0-B7` `MOV r8, imm8`
- `0x66` + `B8-BF` `MOV r16, imm16`
- `88/89/8A/8B` register-register `r8/r32` with `ModRM.mod=11` only
- `0x66` + `89/8B` register-register `r16` with `ModRM.mod=11` only
- `8A /r` byte loads from absolute disp32 memory source
- `8B /r` dword loads from absolute disp32 memory source
- `0x66` + `8B /r` word loads from absolute disp32 memory source
- `88 /r` byte stores to absolute disp32 memory destination
- `89 /r` dword stores to absolute disp32 memory destination
- `0x66` + `89 /r` word stores to absolute disp32 memory destination
- `C6 /0 ib` immediate-to-memory byte stores to absolute disp32 memory
  destination
- `C7 /0 id` immediate-to-memory dword stores to absolute disp32 memory
  destination
- `0x66` + `C7 /0 iw` immediate-to-memory word stores to absolute disp32
  memory destination

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
- full Rung 6 SIB/addressing completion beyond bounded Pass 6G-2
- full Appendix D MOV matrix completion
- full Rung 6 acceptance
- broad `0x66` prefix architecture
- `0x66` support for non-authorized instructions
- `0x67` address-size override behavior
- full prefixed-sequence coverage as one unsupported instruction; the existing
  `0x67` test only proves standalone `0x67` prefix-byte handling at the current
  decoder exposure level
- `88/89` memory-destination addressing beyond direct absolute disp32,
  authorized default-32 base-only no-displacement, non-SIB `mod=01` signed
  disp8, non-SIB `mod=10` signed disp32, base-only SIB forms, and SIB no-base
  disp32 forms, base-present indexed SIB forms, and no-base indexed SIB disp32
  forms
- `8A/8B` memory-source addressing beyond direct absolute disp32, authorized
  default-32 base-only no-displacement, non-SIB `mod=01` signed disp8,
  non-SIB `mod=10` signed disp32 forms, base-only SIB forms, and SIB no-base
  disp32 forms, base-present indexed SIB forms, and no-base indexed SIB disp32
  forms
- `C6/C7` immediate-to-memory addressing beyond direct absolute disp32,
  authorized default-32 base-only no-displacement, non-SIB `mod=01` signed
  disp8, non-SIB `mod=10` signed disp32, base-only SIB forms, and SIB no-base
  disp32 forms, base-present indexed SIB forms, and no-base indexed SIB disp32
  forms
- `C6/C7` register-destination forms beyond `ModRM.mod=11` and `/0`
- `C6/C7` non-`/0` opcode-extension forms
- `C6/C7` behavior without the tested immediate fetch, direct absolute
  disp32, base-only no-displacement, signed disp8, signed disp32, base-only
  SIB, no-base SIB disp32, or base-present indexed SIB `EA_CALC_32`,
  `STORE_RM*`, `STAGE_GPR`, `ENDI CM_NOP|CM_EIP`, or `ENDI CM_MOV_REG`
  sequence
- `EA_CALC_16` support
- `EA_CALC_32` beyond direct absolute disp32 and authorized default-32
  base-only no-displacement, non-SIB `mod=01` signed disp8, and non-SIB
  `mod=10` signed disp32 forms, base-only SIB forms, SIB no-base disp32
  forms, base-present indexed SIB forms, and no-base indexed SIB disp32 forms
- `LOAD_RM*` beyond bounded memory-source reads for direct absolute disp32 and
  authorized default-32 base-only no-displacement, non-SIB `mod=01` signed
  disp8, non-SIB `mod=10` signed disp32, base-only SIB forms, SIB no-base
  disp32 forms, base-present indexed SIB forms, and no-base indexed SIB disp32
  forms
- `STORE_RM*` beyond bounded memory-destination writes for direct absolute
  disp32 MOV, authorized default-32 base-only no-displacement MOV, and
  authorized default-32 non-SIB `mod=01` signed disp8 and non-SIB `mod=10`
  signed disp32 MOV, base-only SIB MOV, SIB no-base disp32 MOV, and
  base-present indexed SIB MOV, and no-base indexed SIB disp32 MOV, including
  bounded immediate-to-memory writes
- general-purpose `LOAD_REG_META` or `STORE_REG_META` completion beyond the
  bounded Pass 5A/5B register-register MOV and Pass 6B-1 memory-destination MOV
  metadata use
- SIB addressing beyond bounded base-only no-index forms, no-base disp32
  no-index forms, base-present indexed forms, and no-base indexed SIB disp32
  forms
- 16-bit addressing behavior
- protected-mode, page, or segment behavior
- final Rung 6 acceptance
- Rung 7 behavior

## Remaining Rung 6 Blockers

Remaining Rung 6 blockers include:

- broader EA/addressing support
- `C6/C7` non-`/0` extensions
- `C6/C7` memory addressing beyond already verified direct absolute disp32,
  default-32 base-only no-displacement, non-SIB `mod=01` signed disp8,
  non-SIB `mod=10` signed disp32 forms, base-only SIB forms, and SIB no-base
  disp32 forms, base-present indexed SIB forms, and no-base indexed SIB disp32
  forms
- `STORE_RM*` beyond bounded memory-destination direct absolute disp32 and
  default-32 base-only no-displacement, non-SIB `mod=01` signed disp8, and
  non-SIB `mod=10` signed disp32 MOV, base-only SIB MOV, and SIB no-base
  disp32 MOV, base-present indexed SIB MOV, and no-base indexed SIB disp32 MOV
- `0x67` address-size override behavior
- `EA_CALC_16`
- 16-bit addressing
- protected-mode/page/segment behavior
- broader MOV families
- general-purpose `LOAD_REG_META` / `STORE_REG_META` beyond bounded
  register-register and Pass 6B-1 memory-destination MOV
- full MOV matrix verification
- full opcode-class dispatch
- final Rung 6 acceptance
