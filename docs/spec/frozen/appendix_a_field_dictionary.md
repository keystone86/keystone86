# Microcoded 486 — Appendix A
# Canonical Field Dictionary
# Version 1.0 — FROZEN
#
# This document is the single source of truth for every symbol, field,
# enum, and encoding used across the design package. All other documents
# defer to this appendix when a name, width, or value is in question.
# If a conflict exists between this appendix and any other document,
# this appendix wins.

---

## SECTION 1 — TEMPORARY REGISTER NAMESPACE

All temporary registers are 32 bits wide unless stated otherwise.
They are held in the reg_file module and are caller/callee managed
per the service ABI rules.

### 1.1 General Temporaries

| Symbol | Reg ID | Width | Role |
|--------|--------|-------|------|
| T0 | 0x0 | 32 | Primary operand / primary result |
| T1 | 0x1 | 32 | Secondary operand / secondary result |
| T2 | 0x2 | 32 | Effective address / linear address / branch target |
| T3 | 0x3 | 32 | Flags helper / width-mode helper (see flags encoding below) |
| T4 | 0x4 | 32 | Immediate / displacement / count / vector |
| T5 | 0x5 | 32 | Segment register index helper (0=ES,1=CS,2=SS,3=DS,4=FS,5=GS) |
| T6 | 0x6 | 32 | Complex-path scratch A / dispatch helper |
| T7 | 0x7 | 32 | Complex-path scratch B |

### 1.2 Selector Temporaries

| Symbol | Reg ID | Width | Role |
|--------|--------|-------|------|
| S0 | 0x8 | 16 (in 32-bit reg) | Primary selector |
| S1 | 0x9 | 16 (in 32-bit reg) | Secondary selector |

### 1.3 Status / Fault Registers

| Symbol | Reg ID | Width | Role |
|--------|--------|-------|------|
| SR | 0xA | 2 | Service result: 0=OK, 1=WAIT, 2=FAULT |
| FC | 0xB | 4 | Fault class (see Section 6) |
| FE | 0xC | 32 | Fault error code (see Section 6) |

### 1.4 Descriptor Latches

Descriptors are 64-bit values. Each is split into two 32-bit register
slots in the reg_file.

| Symbol | Reg ID (lo) | Reg ID (hi) | Role |
|--------|-------------|-------------|------|
| D0 | 0xD | 0xE | Primary descriptor under test/load |
| D1 | 0xF | (extended port) | Secondary descriptor (gate/task/outer) |

D1_HI is accessed through a dedicated extended read/write port on the
reg_file, separate from the standard 4-bit address space. The reg_file
module exposes d1_hi_rd and d1_hi_wr ports for this purpose.

### 1.5 Caller/Callee Save Rules

Caller-saved (microcode must preserve across SVC/SVCW if needed):
    T0, T1, T2, T3, SR, FC, FE

Callee-saved (services must preserve on exit):
    T4, T5, T6, T7, D0, D1, S0, S1

---

## SECTION 2 — METADATA FIELD DICTIONARY

All metadata fields are populated by the decoder before decode_done
is asserted. They are read-only to all modules except the decoder.
They remain stable for the entire duration of instruction execution
(from decode_done until the next decode_done).

### 2.1 Core Decode Fields

| Field | Width | Values / Meaning |
|-------|-------|-----------------|
| M_ENTRY_ID | 8 | ENTRY_* identifier (see Section 4) |
| M_OPSZ | 2 | 0=8-bit, 1=16-bit, 2=32-bit |
| M_ADDRSZ | 1 | 0=16-bit addressing, 1=32-bit addressing |
| M_PREFIX1 | 8 | First prefix byte, 0x00=none |
| M_PREFIX2 | 8 | Second prefix byte, 0x00=none |
| M_MODRM_CLASS | 4 | See Section 2.2 |
| M_IMM_CLASS | 3 | See Section 2.3 |
| M_DISP_CLASS | 3 | See Section 2.4 |
| M_OPCODE_CLASS | 8 | See Section 2.5 |
| M_NEXT_EIP | 32 | EIP of byte immediately following this instruction |

M_NEXT_EIP is set by the decoder after consuming all instruction bytes
(prefix + opcode + ModRM + SIB + displacement + immediate). It equals
the EIP at which the following instruction begins.

### 2.2 M_MODRM_CLASS Encoding

| Value | Symbol | Meaning |
|-------|--------|---------|
| 0x0 | MRM_REG | Register form (mod=11) — no memory access |
| 0x1 | MRM_MEM_NO_DISP | Memory, no displacement (mod=00, r/m≠101 in 32-bit) |
| 0x2 | MRM_MEM_DISP8 | Memory, 8-bit displacement (mod=01) |
| 0x3 | MRM_MEM_DISP32 | Memory, 32-bit displacement (mod=10) |
| 0x4 | MRM_MEM_DISP16 | Memory, 16-bit displacement (16-bit addressing, mod=10) |
| 0x5 | MRM_SIB | 32-bit SIB, no displacement (mod=00, r/m=100) |
| 0x6 | MRM_SIB_DISP8 | 32-bit SIB with disp8 (mod=01, r/m=100) |
| 0x7 | MRM_SIB_DISP32 | 32-bit SIB with disp32 (mod=10, r/m=100) |
| 0x8 | MRM_DIRECT16 | 16-bit direct address (mod=00, r/m=110 in 16-bit mode) |
| 0xF | MRM_NONE | No ModRM present |

### 2.3 M_IMM_CLASS Encoding

| Value | Symbol | Meaning |
|-------|--------|---------|
| 0x0 | IMM_NONE | No immediate |
| 0x1 | IMM_8 | 8-bit immediate, zero-extended to 32 bits |
| 0x2 | IMM_8SX | 8-bit immediate, sign-extended to 32 bits |
| 0x3 | IMM_16 | 16-bit immediate |
| 0x4 | IMM_32 | 32-bit immediate |

### 2.4 M_DISP_CLASS Encoding

| Value | Symbol | Meaning |
|-------|--------|---------|
| 0x0 | DISP_NONE | No displacement |
| 0x1 | DISP_8 | 8-bit displacement, sign-extended |
| 0x2 | DISP_16 | 16-bit displacement |
| 0x3 | DISP_32 | 32-bit displacement |

### 2.5 M_OPCODE_CLASS Encoding

This field provides sub-classification within an entry family.

| Value | Symbol | Used By | Meaning |
|-------|--------|---------|---------|
| 0x00 | OC_MOV_RM_R | ENTRY_MOV | MOV r/m, r (88/89) |
| 0x01 | OC_MOV_R_RM | ENTRY_MOV | MOV r, r/m (8A/8B) |
| 0x02 | OC_MOV_R_IMM | ENTRY_MOV | MOV r, imm (B0-BF) |
| 0x03 | OC_MOV_RM_IMM | ENTRY_MOV | MOV r/m, imm (C6/C7) |
| 0x04 | OC_PUSH_REG | ENTRY_PUSH | PUSH r (50-57) |
| 0x05 | OC_PUSH_RM | ENTRY_PUSH | PUSH r/m (FF /6) |
| 0x06 | OC_POP_REG | ENTRY_POP | POP r (58-5F) |
| 0x07 | OC_POP_RM | ENTRY_POP | POP r/m (8F /0) |
| 0x08 | OC_JMP_REL | ENTRY_JMP_NEAR | JMP rel8/16/32 (E9/EB) |
| 0x09 | OC_JMP_IND | ENTRY_JMP_NEAR | JMP r/m (FF /4) |
| 0x0A | OC_CALL_REL | ENTRY_CALL_NEAR | CALL rel (E8) |
| 0x0B | OC_CALL_IND | ENTRY_CALL_NEAR | CALL r/m (FF /2) |
| 0x0C | OC_RET_NO_IMM | ENTRY_RET_NEAR | RET (C3) |
| 0x0D | OC_RET_IMM | ENTRY_RET_NEAR | RET imm16 (C2) |
| 0x0E | OC_TEST_RM_R | ENTRY_TEST | TEST r/m, r (84/85) |
| 0x0F | OC_TEST_ACC_IMM | ENTRY_TEST | TEST acc, imm (A8/A9) |
| 0x10 | OC_INC_REG | ENTRY_INC_DEC_REG | INC r (40-47) |
| 0x11 | OC_DEC_REG | ENTRY_INC_DEC_REG | DEC r (48-4F) |
| 0x12 | OC_FLAGS_CLC | ENTRY_FLAGS_SIMPLE | CLC (F8) |
| 0x13 | OC_FLAGS_STC | ENTRY_FLAGS_SIMPLE | STC (F9) |
| 0x14 | OC_FLAGS_CLI | ENTRY_FLAGS_SIMPLE | CLI (FA) |
| 0x15 | OC_FLAGS_STI | ENTRY_FLAGS_SIMPLE | STI (FB) |
| 0x16 | OC_FLAGS_CLD | ENTRY_FLAGS_SIMPLE | CLD (FC) |
| 0x17 | OC_FLAGS_STD | ENTRY_FLAGS_SIMPLE | STD (FD) |
| 0x18 | OC_NOP | ENTRY_NOP_XCHG_AX | NOP (90) |
| 0x19 | OC_INT_IMM8 | ENTRY_INT | INT imm8 (CD) |
| 0x1A | OC_IRET | ENTRY_IRET | IRET (CF) |
| 0x1B | OC_LEA | ENTRY_LEA | LEA r, m (8D) |

### 2.6 ALU-Specific Metadata Fields

| Field | Width | Values / Meaning |
|-------|-------|-----------------|
| M_ALU_OP | 4 | ALU operation (see below) |
| M_IS_CMP | 1 | 1=CMP or TEST — no result writeback |

M_ALU_OP encoding:

| Value | Symbol | Operation |
|-------|--------|-----------|
| 0x0 | ALU_ADD | Add |
| 0x1 | ALU_OR | Bitwise OR |
| 0x2 | ALU_ADC | Add with carry |
| 0x3 | ALU_SBB | Subtract with borrow |
| 0x4 | ALU_AND | Bitwise AND |
| 0x5 | ALU_SUB | Subtract |
| 0x6 | ALU_XOR | Bitwise XOR |
| 0x7 | ALU_CMP | Compare (SUB without writeback) |
| 0x8 | ALU_TEST | AND without writeback |

Note: values 0x0-0x7 match the standard x86 ALU opcode group encoding
from the 80/81/83 immediate group, enabling direct hardware decoding.

### 2.7 Register Index Metadata Fields

| Field | Width | Meaning |
|-------|-------|---------|
| M_REG_DST | 3 | Destination register index (0=EAX/AX/AL .. 7=EDI/DI/BH) |
| M_REG_SRC | 3 | Source register index (ModRM.reg field) |
| M_REG_RM | 3 | r/m register index (ModRM.r/m field, used in reg form) |
| M_SIB_SCALE | 2 | SIB scale field (0=×1, 1=×2, 2=×4, 3=×8) |
| M_SIB_INDEX | 3 | SIB index register (4=none/ESP) |
| M_SIB_BASE | 3 | SIB base register |

### 2.8 Flags-Instruction Metadata Fields

Used exclusively by ENTRY_FLAGS_SIMPLE.

| Field | Width | Meaning |
|-------|-------|---------|
| M_FLAG_BIT | 5 | EFLAGS bit position to modify |
| M_FLAG_VAL | 1 | Target value for that bit (0=clear, 1=set) |

EFLAGS bit positions:
    CF=0, PF=2, AF=4, ZF=6, SF=7, TF=8, IF=9, DF=10, OF=11

### 2.9 Condition Code Metadata

| Field | Width | Meaning |
|-------|-------|---------|
| M_COND_CODE | 4 | Jcc condition (0=O/overflow .. 15=NLE) |

M_COND_CODE is the low nibble of the Jcc opcode (opcode & 0x0F).
Values 0x0-0xF map directly to the 16 Jcc conditions.

---

## SECTION 3 — PENDING COMMIT RECORD FIELDS

These fields are staged by services into the commit_engine.
They become architecturally visible only at ENDI.

### 3.1 GPR Commit

| Field | Width | Meaning |
|-------|-------|---------|
| PC_GPR_EN | 1 | Enable GPR commit |
| PC_GPR_IDX | 3 | Destination register index |
| PC_GPR_VAL | 32 | New register value |

### 3.2 EIP Commit

| Field | Width | Meaning |
|-------|-------|---------|
| PC_EIP_EN | 1 | Enable EIP commit |
| PC_EIP_VAL | 32 | New EIP value |

### 3.3 EFLAGS Commit

| Field | Width | Meaning |
|-------|-------|---------|
| PC_EFLAGS_EN | 1 | Enable EFLAGS commit |
| PC_EFLAGS_MASK | 32 | Bitmask of EFLAGS bits to update |
| PC_EFLAGS_VAL | 32 | New values for masked bits |

Applied as: EFLAGS ← (EFLAGS & ~mask) | (val & mask)

### 3.4 Segment Commit

| Field | Width | Meaning |
|-------|-------|---------|
| PC_SEG_EN | 1 | Enable segment commit |
| PC_SEG_IDX | 3 | Segment register (0=ES,1=CS,2=SS,3=DS,4=FS,5=GS) |
| PC_SEG_SEL | 16 | New visible selector |
| PC_SEG_BASE | 32 | New hidden base |
| PC_SEG_LIMIT | 32 | New hidden limit |
| PC_SEG_ATTR | 8 | New hidden attributes (type, DPL, P, D/B, G) |

### 3.5 Stack Commit

| Field | Width | Meaning |
|-------|-------|---------|
| PC_STACK_EN | 1 | Enable ESP/SP commit |
| PC_STACK_VAL | 32 | New ESP value |
| PC_STACK_ADJ | 32 | Signed adjustment to add to PC_STACK_VAL (for RET imm16) |

PC_STACK_ADJ is applied before commit: final_val = PC_STACK_VAL + PC_STACK_ADJ.
PC_STACK_ADJ defaults to zero at instruction start.

### 3.6 Misc Commit

| Field | Width | Meaning |
|-------|-------|---------|
| PC_MISC_EN | 1 | Enable miscellaneous commit |
| PC_MISC_CLASS | 4 | 0=CR0_PE (protected mode enable) [phase 2+] |
| PC_MISC_VAL | 32 | Value for misc operation |

### 3.7 Stage Field Selector Encoding

Used in STAGE microinstruction to select which PC_* field to write.

| Value | Symbol | Target Fields |
|-------|--------|---------------|
| 0x00 | STAGE_GPR | PC_GPR_EN=1, PC_GPR_IDX=metadata, PC_GPR_VAL=src |
| 0x01 | STAGE_EIP | PC_EIP_EN=1, PC_EIP_VAL=src |
| 0x02 | STAGE_EFLAGS | PC_EFLAGS_EN=1, PC_EFLAGS_MASK=mask, PC_EFLAGS_VAL=src |
| 0x03 | STAGE_SEG | PC_SEG_EN=1, all SEG fields from D0/S0 |
| 0x04 | STAGE_STACK | PC_STACK_EN=1, PC_STACK_VAL=src |
| 0x05 | STAGE_MISC | PC_MISC_EN=1, PC_MISC_CLASS=subop, PC_MISC_VAL=src |
| 0x06 | STAGE_STACK_ADJ | PC_STACK_ADJ=src |
| 0x07 | STAGE_EFLAGS_MASK | PC_EFLAGS_MASK=src only (for INC/DEC CF preservation) |

### 3.8 Commit Mask Bit Encoding (ENDI mask, 10-bit)

| Bit | Symbol | Effect at ENDI |
|-----|--------|----------------|
| 0 | CM_GPR | Apply PC_GPR_* to register file |
| 1 | CM_EIP | Apply PC_EIP_* to EIP |
| 2 | CM_EFLAGS | Apply PC_EFLAGS_* to EFLAGS |
| 3 | CM_SEG | Apply PC_SEG_* to segment register |
| 4 | CM_STACK | Apply PC_STACK_* to ESP |
| 5 | CM_MISC | Apply PC_MISC_* |
| 6 | CM_CLR03 | Clear T0, T1, T2, T3 |
| 7 | CM_CLR47 | Clear T4, T5, T6, T7 |
| 8 | CM_CLRF | Clear fault state (FC, FE, fault_pending) |
| 9 | CM_FLUSHQ | Flush prefetch queue (implied by CM_EIP, but can be set alone) |

### 3.9 Standard Commit Mask Combinations

| Name | Mask (binary) | Used By |
|------|---------------|---------|
| CM_ALU_REG | 0b000011000101 | ALU to register (GPR+EFLAGS+CLR03+CLR47+CLRF) |
| CM_MOV_REG | 0b000011000001 | MOV to register (GPR+CLR03+CLR47+CLRF) |
| CM_JMP | 0b000011000010 | JMP (EIP+CLR03+CLR47+CLRF+FLUSHQ) → bit9 set too |
| CM_CALL | 0b000011010010 | CALL (STACK+EIP+CLR03+CLR47+CLRF+FLUSHQ) |
| CM_RET | 0b000011010010 | RET (same as CALL) |
| CM_INT | 0b000011011110 | INT (SEG+STACK+EFLAGS+EIP+CLR03+CLR47+CLRF+FLUSHQ) |
| CM_IRET | 0b000011011110 | IRET (same as INT) |
| CM_FLAGS | 0b000011000100 | Flag-only (EFLAGS+CLR03+CLR47+CLRF) |
| CM_NOP | 0b000011000000 | NOP (CLR03+CLR47+CLRF only) |
| CM_FAULT_END | 0b000001000000 | Fault ENDI (CLR03 only, no CLRF — fault survives) |
| CM_STACK_ONLY | 0b000011010000 | Stack pointer update only |

---

## SECTION 4 — ENTRY IDENTIFIER ENCODING

| Value | Symbol | Phase | Category |
|-------|--------|-------|----------|
| 0x00 | ENTRY_NULL | 0 | Utility — unrecognized opcode → #UD |
| 0x01 | ENTRY_MOV | 1 | Data movement |
| 0x02 | ENTRY_ALU_RM_R | 1 | Integer ALU (dest=r/m, src=reg) |
| 0x03 | ENTRY_ALU_R_RM | 1 | Integer ALU (dest=reg, src=r/m) |
| 0x04 | ENTRY_ALU_RM_IMM | 1 | Integer ALU (dest=r/m, src=imm) |
| 0x05 | ENTRY_PUSH | 1 | Stack push |
| 0x06 | ENTRY_POP | 1 | Stack pop |
| 0x07 | ENTRY_JMP_NEAR | 1 | Near jump |
| 0x08 | ENTRY_JMP_FAR | 2 | Far jump |
| 0x09 | ENTRY_CALL_NEAR | 1 | Near call |
| 0x0A | ENTRY_CALL_FAR | 2 | Far call |
| 0x0B | ENTRY_RET_NEAR | 1 | Near return |
| 0x0C | ENTRY_RET_FAR | 2 | Far return |
| 0x0D | ENTRY_JCC | 1 | Conditional branch |
| 0x0E | ENTRY_INT | 1 | Software interrupt |
| 0x0F | ENTRY_IRET | 1 | Interrupt return |
| 0x10 | ENTRY_SEG_LOAD | 2 | Segment register load |
| 0x11 | ENTRY_MISC_SYSTEM | 2 | System instructions |
| 0x12 | ENTRY_PREFIX_ONLY | 1 | Prefix-only (harmless NOP in phase 1) |
| 0x13 | ENTRY_NOP_XCHG_AX | 1 | NOP / XCHG AX,AX |
| 0x14 | ENTRY_INC_DEC_REG | 1 | INC/DEC register |
| 0x15 | ENTRY_TEST | 1 | TEST |
| 0x16 | ENTRY_LEA | 1 | Load effective address |
| 0x17 | ENTRY_FLAGS_SIMPLE | 1 | CLC/STC/CLI/STI/CLD/STD |
| 0x18 | ENTRY_STRING_BASIC | 3 | String instructions |
| 0x19-0xFE | (reserved) | — | Reserved for future phases |
| 0xFF | ENTRY_RESET | startup | Reset entry (not in dispatch table) |

---

## SECTION 5 — SERVICE IDENTIFIER ENCODING

| ID | Symbol | Group | Phase |
|----|--------|-------|-------|
| 0x00 | SVC_NULL | utility | 0 |
| 0x01 | FETCH_IMM8 | fetch | 1 |
| 0x02 | FETCH_IMM16 | fetch | 1 |
| 0x03 | FETCH_IMM32 | fetch | 1 |
| 0x04 | FETCH_DISP8 | fetch | 1 |
| 0x05 | FETCH_DISP16 | fetch | 1 |
| 0x06 | FETCH_DISP32 | fetch | 1 |
| 0x07 | DECODE_MODRM_CLASS | decode | 1 |
| 0x10 | EA_CALC_16 | address | 1 |
| 0x11 | EA_CALC_32 | address | 1 |
| 0x12 | SEG_DEFAULT_SELECT | address | 2 |
| 0x13 | LINEARIZE_OFFSET | address | 2 |
| 0x20 | LOAD_RM8 | operand | 1 |
| 0x21 | LOAD_RM16 | operand | 1 |
| 0x22 | LOAD_RM32 | operand | 1 |
| 0x23 | STORE_RM8 | operand | 1 |
| 0x24 | STORE_RM16 | operand | 1 |
| 0x25 | STORE_RM32 | operand | 1 |
| 0x26 | LOAD_REG_META | operand | 1 |
| 0x27 | STORE_REG_META | operand | 1 |
| 0x30 | ALU_ADD8 | alu | 1 |
| 0x31 | ALU_ADD16 | alu | 1 |
| 0x32 | ALU_ADD32 | alu | 1 |
| 0x33 | ALU_SUB8 | alu | 1 |
| 0x34 | ALU_SUB16 | alu | 1 |
| 0x35 | ALU_SUB32 | alu | 1 |
| 0x36 | ALU_LOGIC8 | alu | 1 |
| 0x37 | ALU_LOGIC16 | alu | 1 |
| 0x38 | ALU_LOGIC32 | alu | 1 |
| 0x39 | ALU_CMP8 | alu | 1 |
| 0x3A | ALU_CMP16 | alu | 1 |
| 0x3B | ALU_CMP32 | alu | 1 |
| 0x3C | SHIFT_ROT | alu | 2 |
| 0x3D | MUL_IMUL | alu | 2 |
| 0x3E | DIV_IDIV | alu | 2 |
| 0x3F | FLAGS_FROM_T3 | alu | 1 |
| 0x40 | PUSH16 | stack | 1 |
| 0x41 | PUSH32 | stack | 1 |
| 0x42 | POP16 | stack | 1 |
| 0x43 | POP32 | stack | 1 |
| 0x44 | VALIDATE_NEAR_TRANSFER | flow | 1 |
| 0x45 | VALIDATE_FAR_TRANSFER | flow | 2 |
| 0x46 | COMPUTE_REL_TARGET | flow | 1 |
| 0x47 | CONDITION_EVAL | flow | 1 |
| 0x50 | LOAD_DESCRIPTOR | descriptor | 2 |
| 0x51 | CHECK_SEG_ACCESS | descriptor | 2 |
| 0x52 | CHECK_DESCRIPTOR_PRESENT | descriptor | 2 |
| 0x53 | CHECK_CODE_SEG_TRANSFER | descriptor | 2 |
| 0x54 | CHECK_STACK_SEG_TRANSFER | descriptor | 2 |
| 0x55 | LOAD_SEG_VISIBLE | descriptor | 2 |
| 0x56 | LOAD_SEG_HIDDEN | descriptor | 2 |
| 0x57 | COMMIT_SEG_CACHE | descriptor | 2 |
| 0x60 | PREPARE_CALL_GATE | interrupt | 3 |
| 0x61 | PREPARE_TASK_SWITCH | interrupt | 3 |
| 0x62 | INT_ENTER | interrupt | 1 |
| 0x63 | IRET_FLOW | interrupt | 1 |
| 0x64 | FAR_RETURN_VALIDATE | interrupt | 2 |
| 0x65 | FAR_RETURN_OUTER_VALIDATE | interrupt | 3 |
| 0x70 | PAGE_XLATE_FETCH | memory | 3 |
| 0x71 | PAGE_XLATE_READ | memory | 3 |
| 0x72 | PAGE_XLATE_WRITE | memory | 3 |
| 0x73 | MEM_READ8 | memory | 2 |
| 0x74 | MEM_READ16 | memory | 2 |
| 0x75 | MEM_READ32 | memory | 2 |
| 0x76 | MEM_WRITE8 | memory | 2 |
| 0x77 | MEM_WRITE16 | memory | 2 |
| 0x78 | MEM_WRITE32 | memory | 2 |
| 0x80 | COMMIT_GPR | commit | 1 |
| 0x81 | COMMIT_EIP | commit | 1 |
| 0x82 | COMMIT_EFLAGS | commit | 1 |
| 0x83 | COMMIT_SEG | commit | 2 |
| 0x84 | COMMIT_STACK | commit | 1 |
| 0x85 | END_INSTRUCTION | commit | 1 |
| 0x86-0x9F | (reserved) | string | — |
| 0xA0-0xBF | (reserved) | system | — |
| 0xC0-0xFF | (reserved) | — | — |

---

## SECTION 6 — FAULT CLASS AND CONDITION ENCODING

### 6.1 Fault Class (FC) Values

| Value | Symbol | x86 Exception | Vector |
|-------|--------|---------------|--------|
| 0x0 | FC_NONE | No fault | — |
| 0x1 | FC_GP | #GP General Protection | 0x0D |
| 0x2 | FC_SS | #SS Stack Segment | 0x0C |
| 0x3 | FC_NP | #NP Not Present | 0x0B |
| 0x4 | FC_PF | #PF Page Fault | 0x0E |
| 0x5 | FC_TS | #TS Invalid TSS | 0x0A |
| 0x6 | FC_UD | #UD Invalid Opcode | 0x06 |
| 0x7 | FC_DE | #DE Divide Error | 0x00 |
| 0x8 | FC_NM | #NM Device Not Available | 0x07 |
| 0x9 | FC_AC | #AC Alignment Check | 0x11 |
| 0xA | FC_INT | Internal microcode fault | (uses INT_ENTER path) |
| 0xB | FC_DF | #DF Double Fault | 0x08 |
| 0xC | FC_BR | #BR BOUND Range Exceeded | 0x05 |
| 0xD | FC_OF | #OF Overflow (INT 4) | 0x04 |
| 0xE-0xF | (reserved) | — | — |

### 6.2 Service Return Code (SR) Values

| Value | Symbol | Meaning |
|-------|--------|---------|
| 0x0 | SR_OK | Service completed successfully |
| 0x1 | SR_WAIT | Service pending, microsequencer stalls |
| 0x2 | SR_FAULT | Service detected a fault; FC and FE valid |

### 6.3 FE (Fault Error Code) Construction

| Fault | FE Contents |
|-------|-------------|
| #GP, #SS, #NP, #TS | Selector error code: bits[15:3]=selector index, bit[2]=TI, bit[1]=1 if IDT, bit[0]=EXT |
| #PF | Page fault error: bit[0]=P, bit[1]=W/R, bit[2]=U/S, bit[3]=RSVD, bit[4]=I/D |
| #DF | Always zero |
| All others | Zero |

---

## SECTION 7 — MICROINSTRUCTION ENCODING

### 7.1 Primary Word (32-bit)

```
 31      28 27    22 21   18 17  14 13  10 9         0
 +--------+-------+-------+------+------+-----------+
 |UOP_CLASS| TARGET|  COND |  DST |  SRC |IMM10/SUBOP|
 +--------+-------+-------+------+------+-----------+
    4 bits   6 bits  4 bits  4 bits 4 bits   10 bits
```

### 7.2 UOP_CLASS Encoding

| Value | Class | Description |
|-------|-------|-------------|
| 0x0 | NOP | No operation |
| 0x1 | CALL | Push uPC+1, jump to TARGET |
| 0x2 | RET | Pop return stack |
| 0x3 | JMP | Unconditional jump to TARGET |
| 0x4 | BR | Conditional branch: if COND then uPC += sign_extend(IMM10) |
| 0x5 | MOV | reg_file[DST] ← reg_file[SRC] |
| 0x6 | LOADI | reg_file[DST] ← sign_extend(IMM10) |
| 0x7 | EXTRACT | reg_file[DST] ← metadata_field[IMM10] |
| 0x8 | SVC | Request service TARGET, non-waiting |
| 0x9 | SVCW | Request service TARGET, wait-capable |
| 0xA | STAGE | stage_engine: field=IMM10[5:0], val=reg_file[SRC], mask=reg_file[DST] |
| 0xB | COMMIT | Apply commit mask IMM10 to pending commit record |
| 0xC | RAISE | FC ← TARGET[3:0], FE ← reg_file[SRC] |
| 0xD | CLEAR_FAULT | Clear FC, FE, fault_pending |
| 0xE | ENDI | End instruction, commit mask in IMM10 |
| 0xF | EXT | Extension word follows — see below |

### 7.3 COND Field Encoding

| Value | Symbol | Condition |
|-------|--------|-----------|
| 0x0 | ALWAYS | Always true (unconditional) |
| 0x1 | C_OK | SR == SR_OK |
| 0x2 | C_WAIT | SR == SR_WAIT |
| 0x3 | C_FAULT | SR == SR_FAULT |
| 0x4 | C_T0Z | T0 == 0 |
| 0x5 | C_T0NZ | T0 != 0 |
| 0x6 | C_W16 | M_OPSZ == 1 (16-bit operand) |
| 0x7 | C_W32 | M_OPSZ == 2 (32-bit operand) |
| 0x8 | C_REAL | mode_prot == 0 |
| 0x9 | C_PROT | mode_prot == 1 |
| 0xA | C_REP | REP prefix active |
| 0xB | C_W8 | M_OPSZ == 0 (8-bit operand) |
| 0xC | C_T3Z | T3 == 0 (condition eval false) |
| 0xD | C_T3NZ | T3 != 0 (condition eval true) |
| 0xE | C_ADDR16 | M_ADDRSZ == 0 (16-bit addressing) |
| 0xF | C_ADDR32 | M_ADDRSZ == 1 (32-bit addressing) |

Note: C_W16/C_W32/C_W8 test M_OPSZ. C_ADDR16/C_ADDR32 test M_ADDRSZ.
These are distinct fields and distinct conditions.

### 7.4 Register (DST/SRC) Field Encoding

Matches Section 1 exactly:

| Value | Register |
|-------|----------|
| 0x0 | T0 |
| 0x1 | T1 |
| 0x2 | T2 |
| 0x3 | T3 |
| 0x4 | T4 |
| 0x5 | T5 |
| 0x6 | T6 |
| 0x7 | T7 |
| 0x8 | S0 |
| 0x9 | S1 |
| 0xA | SR |
| 0xB | FC |
| 0xC | FE |
| 0xD | D0 (lo word) |
| 0xE | D0 (hi word) |
| 0xF | special / zero / immediate select |

### 7.5 Extension Word

When UOP_CLASS == 0xF:
The primary word's IMM10 field specifies the extension type.

| IMM10 | Extension type |
|-------|----------------|
| 0x000 | 32-bit jump/call target follows in next word |
| 0x001 | 32-bit immediate literal follows |
| 0x002 | 64-bit descriptor literal follows (two words) |

### 7.6 EXTRACT Metadata Field Index (IMM10)

Used by EXTRACT microinstruction to read M_* fields into a temp register.

| IMM10 | Field | Width in T_DST |
|-------|-------|----------------|
| 0x00 | M_ENTRY_ID | 8 |
| 0x01 | M_OPSZ | 2 |
| 0x02 | M_ADDRSZ | 1 |
| 0x03 | M_MODRM_CLASS | 4 |
| 0x04 | M_IMM_CLASS | 3 |
| 0x05 | M_DISP_CLASS | 3 |
| 0x06 | M_OPCODE_CLASS | 8 |
| 0x07 | M_ALU_OP | 4 |
| 0x08 | M_IS_CMP | 1 |
| 0x09 | M_REG_DST | 3 |
| 0x0A | M_REG_SRC | 3 |
| 0x0B | M_REG_RM | 3 |
| 0x0C | M_SIB_SCALE | 2 |
| 0x0D | M_SIB_INDEX | 3 |
| 0x0E | M_SIB_BASE | 3 |
| 0x0F | M_COND_CODE | 4 |
| 0x10 | M_FLAG_BIT | 5 |
| 0x11 | M_FLAG_VAL | 1 |
| 0x12 | M_NEXT_EIP | 32 |
| 0x13 | FC_TO_VECTOR | 8 (hardware maps FC→x86 vector number) |
| 0x14 | M_PREFIX1 | 8 |
| 0x15 | M_PREFIX2 | 8 |

### 7.7 ALU Logic Subop Encoding (IMM10 field for ALU_LOGIC*)

| Value | Operation |
|-------|-----------|
| 0 | AND |
| 1 | OR |
| 2 | XOR |
| 3 | NOT (T1 unused) |

---

## SECTION 8 — DECODER CONTRACT

### 8.1 Implementation Model — OFFICIAL DECISION

The decoder is a sequential byte-consuming FSM that reads from the
prefetch queue. It has registered metadata outputs.

This resolves the ambiguity between the two descriptions in earlier
documents. The decoder is NOT purely combinational because it must:

- Consume a variable number of bytes (1 to 15)
- Determine whether ModRM/SIB/displacement/immediate bytes are present
- Track how many bytes have been consumed for M_NEXT_EIP

The decoder is organized as a sequential state machine, but its
classification logic (opcode → entry ID, ModRM → addressing class)
IS combinational within each state. The sequential aspect is the
byte-consumption control, not the classification logic.

### 8.2 Decoder States

| State | Meaning |
|-------|---------|
| DEC_IDLE | Waiting — decode_done not yet cleared by microsequencer |
| DEC_PREFIX | Consuming prefix bytes (up to 2) |
| DEC_OPCODE | Consuming opcode byte (and 0x0F escape if needed) |
| DEC_MODRM | Consuming ModRM byte |
| DEC_SIB | Consuming SIB byte (if present) |
| DEC_DISP | Consuming displacement bytes (1, 2, or 4) |
| DEC_IMM | Consuming immediate bytes (1, 2, or 4) |
| DEC_DONE | All bytes consumed, metadata valid, asserting decode_done |

### 8.3 decode_done Handshake

decode_done is asserted (high) in state DEC_DONE.
It remains asserted until the microsequencer asserts dec_ack.
On dec_ack, decoder returns to DEC_IDLE and begins the next instruction.
dec_ack is asserted by the microsequencer in the same cycle it begins
dispatching to the new entry routine.

### 8.4 M_NEXT_EIP

M_NEXT_EIP is updated by the decoder's byte-consumption counter.
It equals the value of the fetch EIP after the last byte of the current
instruction has been consumed from the prefetch queue.

### 8.5 Decoder Ownership Rules

The decoder may:
- Classify opcodes into families
- Determine operand/address size
- Consume prefix, opcode, ModRM, SIB, displacement, and immediate bytes
- Populate all M_* metadata fields
- Assert decode_done with a valid ENTRY_ID

The decoder must not:
- Implement any instruction semantics
- Access the register file
- Access memory
- Modify any architectural state
- Generate fault conditions directly (unrecognized opcodes → ENTRY_NULL)

---

## SECTION 9 — T3 FLAGS HELPER ENCODING

T3 carries computed flag values from ALU services to COMMIT_EFLAGS.
This encoding is internal — it is not the same as EFLAGS bit positions.

| Bit | Flag | Meaning |
|-----|------|---------|
| 0 | CF | Carry flag |
| 1 | PF | Parity flag (parity of result[7:0]) |
| 2 | AF | Auxiliary carry (carry from bit 3 to bit 4) |
| 3 | ZF | Zero flag |
| 4 | SF | Sign flag (= result MSB per width) |
| 5 | OF | Overflow flag |
| 31:6 | — | Reserved, zero |

COMMIT_EFLAGS translates T3 to EFLAGS using the following map:

| T3 bit | EFLAGS bit | Name |
|--------|------------|------|
| 0 | 0 | CF |
| 1 | 2 | PF |
| 2 | 4 | AF |
| 3 | 6 | ZF |
| 4 | 7 | SF |
| 5 | 11 | OF |

EFLAGS bits 1 (reserved=1), 3 (reserved=0), 5 (reserved=0), and 8-10
(TF, IF, DF) are never written by COMMIT_EFLAGS unless the PC_EFLAGS_MASK
explicitly includes them (used by INT_ENTER/IRET_FLOW for IF/TF).

INC/DEC EFLAGS mask:
When INC or DEC is committed, PC_EFLAGS_MASK must have bit 0 (CF) = 0.
All other flag bits are updated normally.

---

*End of Appendix A — Canonical Field Dictionary*
