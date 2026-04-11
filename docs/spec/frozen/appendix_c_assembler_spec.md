# Microcoded 486 — Appendix C
# Microcode Assembly Specification and Tool Flow
# Version 1.0 — FROZEN

---

## 1. Purpose

This document defines the microcode source language, assembler rules,
ROM image generation, and dispatch table generation. It bridges the
symbolic microcode listings in Companion Document 1 to the numeric
encodings defined in Appendix A Section 7.

A microcode assembler (uasm) must implement these rules exactly.
Any symbolic listing that conforms to this document can be assembled
to a binary ROM image without ambiguity.

---

## 2. Source File Format

Microcode source files use the extension .uasm.
Encoding is ASCII. Line endings are LF or CRLF.
Comments begin with ; and extend to end of line.
Blank lines are permitted anywhere.

### 2.1 Statement Forms

    LABEL:                      ; label definition
    LABEL: INSTRUCTION          ; label + instruction on same line
    INSTRUCTION                 ; instruction without label
    .DIRECTIVE argument         ; assembler directive

### 2.2 Label Rules

Labels are alphanumeric plus underscore. Case-sensitive.
Labels beginning with a period (.) are local to the enclosing
named routine (between two non-local labels). Local labels
are resolved relative to their enclosing routine.

Examples:
    ENTRY_JMP_NEAR:             ; global label
    .jmp_rel:                   ; local label (scoped to ENTRY_JMP_NEAR)
    SUB_FAULT_HANDLER:          ; global subroutine label

---

## 3. Assembler Directives

    .include "filename.uasm"    ; include another source file
    .org N                      ; set current assembly address to N
    .align N                    ; advance to next multiple of N
    .entry NAME, ID             ; declare entry point: NAME gets ID in dispatch table
    .end                        ; end of source

### 3.1 .entry Directive

Every top-level entry routine must be declared with .entry before
any instructions in that routine:

    .entry ENTRY_MOV, 0x01
    ENTRY_MOV:
        ...

This registers ENTRY_MOV in the dispatch table at ID 0x01, pointing
to the address of the ENTRY_MOV label.

Shared subroutines (SUB_*) do not use .entry — they are reachable
only via CALL from microcode.

---

## 4. Instruction Syntax

Each instruction assembles to one 32-bit primary word, optionally
followed by one or two 32-bit extension words.

### 4.1 NOP

    NOP
    ; Encodes: UOP_CLASS=0x0, all other fields zero

### 4.2 CALL

    CALL target
    ; target: a label name
    ; If target is within ±31 words of current uPC: encodes as UOP_CLASS=0x1,
    ;   TARGET[5:0] = relative offset (6-bit signed)
    ; If target is beyond that range: encodes with extension word
    ;   Primary: UOP_CLASS=0xF, IMM10=0x000 (EXT_JUMP32)
    ;   Extension: 32-bit absolute target address

### 4.3 RET

    RET
    ; Encodes: UOP_CLASS=0x2, all other fields zero

### 4.4 JMP

    JMP target
    ; Always encodes as CALL with no push (assembler uses UOP_CLASS=0x3)
    ; Same distance rules as CALL apply for extension word usage

### 4.5 BR

    BR condition, target
    ; condition: a condition symbol from Appendix A Section 7.3
    ; target: a label (must be within ±31 words — long conditional branches
    ;         must use JMP after a reversed condition test)
    ; Encodes: UOP_CLASS=0x4, COND=condition value, IMM10=signed offset

    ; Example: BR C_FAULT, SUB_FAULT_HANDLER
    ; If SUB_FAULT_HANDLER is out of ±31 range:
    ;   BR C_OK, .skip
    ;   JMP SUB_FAULT_HANDLER
    ; .skip:

### 4.6 MOV

    MOV dst, src
    ; dst, src: register symbols (T0-T7, S0-S1, SR, FC, FE, D0, D1)
    ; Encodes: UOP_CLASS=0x5, DST=reg_id(dst), SRC=reg_id(src)

### 4.7 LOADI

    LOADI dst, immediate
    ; dst: register symbol
    ; immediate: decimal or 0x-prefixed hex integer, range -512 to +511 (10-bit signed)
    ; For larger immediates: assembler auto-emits extension word
    ;   Primary: UOP_CLASS=0xF, IMM10=0x001 (EXT_IMM32)
    ;   Extension: 32-bit value
    ; Encodes: UOP_CLASS=0x6, DST=reg_id(dst), IMM10=sign_extend(imm)

### 4.8 EXTRACT

    EXTRACT dst, field_name
    ; field_name: a metadata field symbol from Appendix A Section 7.6
    ; Assembler looks up IMM10 value from Section 7.6 table
    ; Encodes: UOP_CLASS=0x7, DST=reg_id(dst), IMM10=field_index

### 4.9 SVC

    SVC service_name
    ; service_name: a service symbol from Appendix A Section 5
    ; Assembler looks up 8-bit service ID
    ; Encodes: UOP_CLASS=0x8, TARGET[5:0]=service_id[5:0]
    ; Note: if service_id > 63, uses extension encoding via EXT word

### 4.10 SVCW

    SVCW service_name
    ; Same as SVC but UOP_CLASS=0x9
    ; Used for wait-capable services (may_wait: true in catalog)
    ; Assembler enforces: if service is not wait-capable, emit warning

### 4.11 STAGE

    STAGE field_symbol, src_reg
    STAGE field_symbol, src_reg, mask_reg
    ; field_symbol: a stage field symbol from Appendix A Section 3.7
    ; Assembler looks up IMM10[5:0] = stage field selector
    ; Encodes: UOP_CLASS=0xA, DST=reg_id(mask_reg) or 0xF if no mask,
    ;          SRC=reg_id(src_reg), IMM10[5:0]=field_selector

### 4.12 COMMIT

    COMMIT mask_expression
    ; mask_expression: OR of commit mask symbols from Appendix A Section 3.8
    ; Assembler evaluates mask_expression to 10-bit value
    ; Encodes: UOP_CLASS=0xB, IMM10=mask_value

    ; Examples:
    ;   COMMIT CM_GPR|CM_CLR03|CM_CLR47|CM_CLRF
    ;   COMMIT CM_NOP
    ;   COMMIT 0                                  ; explicit zero (harmless)

### 4.13 RAISE

    RAISE fault_class_symbol, src_reg
    ; fault_class_symbol: FC_* symbol from Appendix A Section 6.1
    ; src_reg: register holding error code (FE), or ZERO for zero error code
    ; Assembler looks up fault class value → TARGET[3:0]
    ; Encodes: UOP_CLASS=0xC, TARGET[3:0]=fc_value, SRC=reg_id(src_reg)

    ; Example:
    ;   LOADI T0, 0         ; zero error code
    ;   RAISE FC_UD, T0     ; raise #UD with FE=0

    ; Shorthand for common case (zero error code):
    ;   RAISE FC_UD         ; assembler implicitly uses zero

### 4.14 CLEAR_FAULT

    CLEAR_FAULT
    ; Encodes: UOP_CLASS=0xD, all other fields zero

### 4.15 ENDI

    ENDI mask_expression
    ; Same mask_expression rules as COMMIT
    ; Encodes: UOP_CLASS=0xE, IMM10=mask_value

    ; Examples:
    ;   ENDI CM_MOV_REG
    ;   ENDI CM_JMP
    ;   ENDI CM_INT

---

## 5. Pseudo-Instructions (Assembler Macros)

These expand to sequences of real instructions.

### 5.1 SWAP dst, src
Swaps two registers. Expands to:

    MOV T_SCRATCH, dst      ; uses T6 as scratch
    MOV dst, src
    MOV src, T_SCRATCH

T6 must be free when SWAP is used. Assembler emits a warning if T6
is known to be in use (tracked via register liveness hints).

### 5.2 WIDTH_DISPATCH svc8, svc16, svc32
Expands to:

    BR C_W8,  .w8_N
    BR C_W16, .w16_N
    SVCW svc32
    JMP .wd_done_N
  .w8_N:
    SVCW svc8
    JMP .wd_done_N
  .w16_N:
    SVCW svc16
  .wd_done_N:

Where N is a unique local label suffix generated by the assembler.

### 5.3 ADDR_DISPATCH svc16, svc32
Expands to:

    BR C_ADDR16, .a16_N
    SVCW svc32
    JMP .ad_done_N
  .a16_N:
    SVCW svc16
  .ad_done_N:

### 5.4 CHECK_FAULT target
Expands to:

    BR C_FAULT, target

This is simply an alias for readability.

---

## 6. Assembler Enforcement Rules

The assembler must enforce:

1. Every service invoked with SVCW must be declared may_wait: true
   in the service catalog. If not, the assembler must emit an error.

2. Every service invoked with SVC must be declared may_wait: false
   in the service catalog. If not, the assembler must emit a warning.

3. Every ENTRY_* label must be declared with .entry and must appear
   in the service/entry ID tables in Appendix A.

4. No label may be defined twice in the same scope.

5. All branch targets must be defined (no forward references to
   undefined labels at end of assembly).

6. RAISE used without an error code register auto-inserts a
   LOADI T0, 0 immediately before the RAISE instruction.

7. The assembler tracks the maximum return stack depth per entry routine
   (counting CALL depth). If depth exceeds 8, it must emit an error.

---

## 7. Output Files

The assembler produces three output files:

### 7.1 ucode.hex

ROM image in standard hex format (one 32-bit word per line, big-endian).
Total size: 4096 lines (12-bit address space).
Unused addresses are filled with the NOP encoding (0x00000000).

    Example first few lines:
    00000000    ; address 0x000: NOP (padding before first entry)
    ...
    00400000    ; address 0x010: start of ENTRY_NULL (RAISE FC_UD)
    ...

### 7.2 dispatch.hex

Dispatch table image: 256 entries × 12-bit addresses.
One entry per line in hex.

    Example:
    000    ; ENTRY_NULL (0x00) → uPC 0x000
    010    ; ENTRY_MOV (0x01) → uPC 0x010
    040    ; ENTRY_ALU_RM_R (0x02) → uPC 0x040
    ...

### 7.3 ucode.lst (listing file)

Human-readable listing showing:

    address   encoding   source line
    0x010     0xC600...  ENTRY_NULL: RAISE FC_UD
    0x011     0xEA000100 ENDI CM_FAULT_END
    0x040     ...        ENTRY_MOV: EXTRACT T6, M_OPCODE_CLASS
    ...

This listing is the primary debug tool for tracing microcode execution.
The simulation testbench loads ucode.lst to annotate trace output with
symbolic instruction names.

---

## 8. Microcode Source File Structure

The phase-1 microcode source is organized as a single top-level file
that includes sub-files:

    ; ucode_main.uasm — top-level microcode source
    .include "shared/sub_fault_handler.uasm"
    .include "shared/sub_ea_and_fetch_src.uasm"
    .include "shared/sub_store_dst.uasm"
    .include "shared/sub_fetch_disp.uasm"
    .include "shared/sub_fetch_imm.uasm"
    .include "shared/sub_alu_dispatch.uasm"
    .include "shared/sub_fetch_disp_to_ea.uasm"
    .include "entries/entry_null.uasm"
    .include "entries/entry_mov.uasm"
    .include "entries/entry_alu_rm_r.uasm"
    .include "entries/entry_alu_r_rm.uasm"
    .include "entries/entry_alu_rm_imm.uasm"
    .include "entries/entry_push.uasm"
    .include "entries/entry_pop.uasm"
    .include "entries/entry_jmp_near.uasm"
    .include "entries/entry_call_near.uasm"
    .include "entries/entry_ret_near.uasm"
    .include "entries/entry_jcc.uasm"
    .include "entries/entry_int.uasm"
    .include "entries/entry_iret.uasm"
    .include "entries/entry_prefix_only.uasm"
    .include "entries/entry_nop_xchg_ax.uasm"
    .include "entries/entry_inc_dec_reg.uasm"
    .include "entries/entry_test.uasm"
    .include "entries/entry_lea.uasm"
    .include "entries/entry_flags_simple.uasm"
    .end

Shared subroutines are placed before entry routines so they are at
lower ROM addresses and within reach of 6-bit relative CALL targets
from most entry routines.

---

## 9. Bring-Up Build Order

### Phase 1, Step 1: Minimal core

Build and assemble only:
    sub_fault_handler.uasm
    entry_null.uasm
    entry_nop_xchg_ax.uasm
    entry_prefix_only.uasm

This gives a minimal ROM image that can reset, recognize NOP,
and raise #UD for everything else. Used for initial bring-up testing.

### Phase 1, Step 2: Add control flow

Add:
    sub_ea_and_fetch_src.uasm
    sub_fetch_disp.uasm
    sub_fetch_imm.uasm
    sub_fetch_disp_to_ea.uasm
    entry_jmp_near.uasm
    entry_call_near.uasm
    entry_ret_near.uasm
    entry_jcc.uasm

This enables the first five targeted proof entries.

### Phase 1, Step 3: Add INT/IRET

Add:
    entry_int.uasm
    entry_iret.uasm

### Phase 1, Step 4: Add MOV and ALU

Add all remaining shared subroutines and entry routines.

---

*End of Appendix C — Microcode Assembly Specification and Tool Flow*
