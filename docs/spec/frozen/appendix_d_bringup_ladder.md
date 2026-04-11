# Microcoded 486 — Appendix D
# Phase-1 Bring-Up Ladder and Exception Delivery Checklist
# Version 1.0 — FROZEN

---

## PART 1 — FROZEN BRING-UP LADDER

This is the mandatory implementation order for phase-1.
Each rung must pass its verification criteria before the next begins.
No rung may be skipped or re-ordered without a documented justification.

---

### RUNG 0: Reset Path and Fetch/Decode Loop

**Build:**
- cpu_top skeleton (no logic)
- prefetch_queue (basic byte buffering, flush)
- decoder stub (outputs ENTRY_NULL for every opcode, asserts decode_done)
- microsequencer (dispatch table lookup, uPC management, EXECUTE state only)
- microcode_rom (loaded from ucode.hex)
- commit_engine (holds reset state, accepts ENDI, applies EIP commit only)
- bus_interface (basic rd/wr/ready cycle)
- Minimal microcode ROM: ENTRY_NULL → RAISE FC_UD → ENDI CM_FAULT_END
- ENTRY_RESET → ENDI CM_NOP (no-op commit, return to fetch/decode)

**Verify:**
- Reset vector: CPU asserts first bus read at physical 0xFFFFFFF0
- decode_done asserted for first byte fetched
- Microsequencer dispatches to ENTRY_NULL
- ENDI executes without crash
- Microsequencer returns to FETCH_DECODE state
- Prefetch queue refills after ENDI

**Gate criterion:** CPU can reset, run one NOP-equivalent cycle,
and return to fetch/decode without hanging.

---

### RUNG 1: NOP and Dispatch Sanity

**Build:**
- Decoder able to recognize opcode 0x90 → ENTRY_NOP_XCHG_AX
- Decoder able to recognize opcode 0xF1-0xF7 prefix group → ENTRY_PREFIX_ONLY
- ENTRY_NOP_XCHG_AX microcode: ENDI CM_NOP
- ENTRY_PREFIX_ONLY microcode: ENDI CM_NOP
- Dispatch table populated for these two entries

**Verify:**
- NOP (0x90) executes: EIP advances by 1, no register change
- EIP commit works: EIP = M_NEXT_EIP after NOP
- Multiple consecutive NOPs execute correctly
- Prefetch queue refill and decode pipeline stable over 100+ NOPs

**Gate criterion:** 100 consecutive NOPs execute with correct EIP
advancement and zero spurious faults.

---

### RUNG 2: Near JMP

**Build:**
- Decoder: recognize E9/EB → ENTRY_JMP_NEAR with M_OPCODE_CLASS=OC_JMP_REL
- Decoder: recognize FF /4 → ENTRY_JMP_NEAR with M_OPCODE_CLASS=OC_JMP_IND
- fetch_engine: FETCH_DISP8, FETCH_DISP32 (minimum needed)
- flow_control: COMPUTE_REL_TARGET, VALIDATE_NEAR_TRANSFER
- commit_engine: EIP commit + prefetch flush
- ENTRY_JMP_NEAR microcode complete

**Verify:**
- JMP SHORT +0 (EB FE): infinite loop, CPU runs without faults
- JMP SHORT +5 (EB 05): EIP advances by 7 (2 for instruction + 5 displacement)
- JMP NEAR forward: EIP set to correct target
- JMP NEAR backward: EIP set to correct target (prefetch flush verified)
- Prefetch queue correctly flushed after JMP

**Gate criterion:** JMP SHORT to self (infinite loop) runs for 1000
cycles without fault. Forward and backward JMP produce correct EIP.

---

### RUNG 3: Near CALL and RET

**Build:**
- Decoder: E8 → ENTRY_CALL_NEAR, FF /2 → ENTRY_CALL_NEAR (indirect)
- Decoder: C3/C2 → ENTRY_RET_NEAR
- stack_engine: PUSH32/PUSH16, POP32/POP16 (minimum needed)
- commit_engine: STACK commit
- ENTRY_CALL_NEAR microcode complete
- ENTRY_RET_NEAR microcode complete

**Verify:**
- CALL + RET pair: EIP and ESP restored exactly
- Return address on stack is correct (M_NEXT_EIP of CALL)
- ESP decremented by 4 (32-bit) or 2 (16-bit) on CALL
- ESP incremented on RET
- RET imm16 (C2): ESP adjusted by immediate after pop
- Nested CALL/RET (depth 4): all frames correct

**Gate criterion:** CALL/RET pair executes correctly. Nested calls
to depth 4 all return to correct addresses with correct ESP.

---

### RUNG 4: Jcc

**Build:**
- Decoder: 70-7F → ENTRY_JCC with M_COND_CODE = opcode & 0x0F
- flow_control: CONDITION_EVAL
- ENTRY_JCC microcode complete

**Verify:**
- Each of 16 conditions tested: taken case and not-taken case
- JZ: taken when ZF=1, not taken when ZF=0
- JNZ: taken when ZF=0, not taken when ZF=1
- (all 16 pairs)
- Branch range: short ±127 byte range (DISP8 only in phase-1)
- EIP correct in both taken and not-taken cases

**Gate criterion:** All 16 Jcc conditions pass taken and not-taken
verification against reference model.

---

### RUNG 5: INT and IRET

**Build:**
- Decoder: CD → ENTRY_INT, CF → ENTRY_IRET
- fetch_engine: FETCH_IMM8
- interrupt_engine: INT_ENTER, IRET_FLOW
- ENTRY_INT and ENTRY_IRET microcode complete
- SUB_FAULT_HANDLER microcode complete (uses INT_ENTER for fault delivery)

**Verify:**
- INT imm8: IVT lookup, FLAGS/CS/IP pushed in correct order, IF cleared
- IRET: IP/CS/FLAGS popped in correct order, IF restored
- INT 0x21 round-trip with trivial handler (just IRET): state restored
- Fault delivery via SUB_FAULT_HANDLER: #UD raised for unknown opcode

**Gate criterion:** INT/IRET round-trip fully restores architectural
state. #UD delivered correctly for unknown opcodes.

---

### RUNG 6: MOV

**Build:**
- Decoder: 88/89/8A/8B/C6/C7/B0-BF → ENTRY_MOV with correct M_OPCODE_CLASS
- fetch_engine: all FETCH_IMM* and FETCH_DISP* variants
- ea_calc: EA_CALC_16 and EA_CALC_32
- load_store: LOAD_RM8/16/32, STORE_RM8/16/32, LOAD_REG_META, STORE_REG_META
- reg_file: full 8-register file
- ENTRY_MOV microcode complete

**Verify:**
- MOV reg, reg: all 8 register combinations, all 3 widths
- MOV reg, imm: all registers, all widths
- MOV reg, [mem]: memory read, all widths, all addressing modes
- MOV [mem], reg: memory write, all widths, all addressing modes
- MOV [mem], imm: immediate to memory
- Flags: verify EFLAGS unchanged by MOV

**Gate criterion:** Full MOV test matrix passes against reference model.

---

### RUNG 7: ALU Operations

**Build:**
- Decoder: all ALU opcode families → correct ENTRY_ALU_* with M_ALU_OP
- alu: ALU_ADD*/SUB*/LOGIC*/CMP* hardware block
- ENTRY_ALU_RM_R, ENTRY_ALU_R_RM, ENTRY_ALU_RM_IMM microcode complete
- COMMIT_EFLAGS service complete
- FLAGS_FROM_T3 service complete

**Verify:**
- ADD/SUB/AND/OR/XOR/CMP: reg/reg, reg/mem, mem/reg, reg/imm forms
- All flag behaviors: CF, OF, ZF, SF, PF, AF
- CMP: destination not modified
- Accumulator short forms (04/05/0C etc.)
- 8086 test vectors for all ALU opcodes pass

**Gate criterion:** ALU instruction families pass all applicable
8086 test vectors (100% pass rate on all applicable opcode tests).

---

### RUNG 8: PUSH, POP, INC, DEC, TEST, LEA, Flags

**Build:**
- Decoder: all remaining phase-1 opcodes
- ENTRY_PUSH, ENTRY_POP, ENTRY_INC_DEC_REG, ENTRY_TEST, ENTRY_LEA,
  ENTRY_FLAGS_SIMPLE microcode complete

**Verify:**
- PUSH/POP: all register forms, r/m forms
- INC/DEC: CF not modified, all other flags correct
- TEST: destination unchanged, flags as if AND performed
- LEA: EA computed, no memory access, flags unchanged
- CLC/STC/CLI/STI/CLD/STD: only specified flag changes

**Gate criterion:** All remaining phase-1 instructions pass
instruction-level tests against reference model.

---

### RUNG 9: Full Phase-1 Compliance

**Run:**
- Full 8086/8088 test vector suite against all applicable opcodes
- Integration test suite (arithmetic sequence, stack nesting, interrupt round-trip)
- System test: minimal real-mode program boots and runs correctly

**Gate criterion:** 100% pass rate on all applicable test vectors.
System test completes without fault.

---

## PART 2 — FAULT ORDERING CHECKLIST (PHASE-1)

For each phase-1 instruction family, the following table defines
what can fault and in what order. Faults higher in the list take
priority over faults lower in the list.

The order is enforced by microcode sequencing: earlier service calls
that can fault are called before later ones. If an earlier service
faults, microcode branches to SUB_FAULT_HANDLER before calling
subsequent services.

### MOV (all forms)

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | Instruction fetch | FC_GP | (phase 2+: page fault; phase 1: none) |
| 2 | FETCH_DISP* | FC_GP | (phase 1: queue underrun — handled as WAIT, not fault) |
| 3 | EA_CALC_* | FC_GP | (phase 1: none; phase 2: segment override invalid) |
| 4 | LOAD_RM* | FC_GP | (phase 1: none; phase 2: limit violation) |
| 5 | STORE_RM* | FC_GP | (phase 1: none; phase 2: limit violation or read-only) |

**Phase-1 result:** MOV cannot fault in phase-1. All fault paths
in the MOV microcode are present but will never be taken.

---

### ALU (ADD/SUB/AND/OR/XOR/CMP, all forms)

Same fault order as MOV. No additional fault sources.
**Phase-1 result:** ALU cannot fault in phase-1.

---

### PUSH

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | LOAD_RM* (for PUSH r/m form) | FC_GP | (phase 1: none) |
| 2 | PUSH16/PUSH32 | FC_SS | (phase 1: none; phase 2: SS limit) |

**Phase-1 result:** PUSH cannot fault in phase-1.

---

### POP

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | POP16/POP32 | FC_SS | (phase 1: none; phase 2: SS limit) |
| 2 | STORE_RM* (for POP r/m form) | FC_GP | (phase 1: none) |
| 3 | EA_CALC (for POP r/m) | FC_GP | (phase 1: none) |

**Phase-1 result:** POP cannot fault in phase-1.

---

### JMP near

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | VALIDATE_NEAR_TRANSFER | FC_GP | Target > 0xFFFF in 16-bit mode |
| 2 | LOAD_RM* (indirect form) | FC_GP | (phase 1: none) |

**Phase-1 result:** JMP can fault with #GP if indirect target or
computed target exceeds segment limit (0xFFFF in 16-bit real mode).

---

### CALL near

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | PUSH16/PUSH32 | FC_SS | (phase 1: none) |
| 2 | VALIDATE_NEAR_TRANSFER | FC_GP | Target > 0xFFFF |
| 3 | LOAD_RM* (indirect) | FC_GP | (phase 1: none) |

**Phase-1 result:** CALL can fault with #GP on out-of-range target.

---

### RET near

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | POP16/POP32 | FC_SS | (phase 1: none) |
| 2 | VALIDATE_NEAR_TRANSFER | FC_GP | Return address > 0xFFFF |

**Phase-1 result:** RET can fault with #GP if return address is
out of range (malformed stack).

---

### Jcc

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | VALIDATE_NEAR_TRANSFER | FC_GP | Target > 0xFFFF (taken path only) |

**Phase-1 result:** Jcc can fault on taken path if computed target
is out of range.

---

### INT

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | FETCH_IMM8 | (wait, not fault) | queue empty |
| 2 | INT_ENTER IVT read | FC_GP | IVT read fault (phase 1: none unless bus error) |
| 3 | INT_ENTER stack push | FC_SS | (phase 1: none) |

**Phase-1 result:** INT can theoretically fault, but in phase-1
real mode all paths succeed assuming valid memory.

---

### IRET

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | IRET_FLOW stack reads | FC_SS | (phase 1: none) |
| 2 | VALIDATE result CS | FC_GP | (phase 1: minimal check only) |

**Phase-1 result:** IRET minimal validation in real mode. If CS is
non-zero it is loaded without further checks. Full validation is phase-2.

---

### INC / DEC

No fault possible in phase-1.

---

### TEST / LEA

No fault possible in phase-1.

---

### Flags (CLC/STC/CLI/STI/CLD/STD)

No fault possible in phase-1 real mode.

---

### Unrecognized opcode (ENTRY_NULL)

| Order | Fault Source | Fault Class | Condition |
|-------|-------------|-------------|-----------|
| 1 | ENTRY_NULL: RAISE FC_UD | FC_UD | Always |

Delivery: RAISE → SUB_FAULT_HANDLER → INT_ENTER with vector 0x06.

---

## PART 3 — IMPLEMENTATION NOTES

### On fault paths in phase-1

Every entry routine contains BR C_FAULT, SUB_FAULT_HANDLER after
every SVCW call. In phase-1, most of these paths will never be taken.
They must still be present because:

1. They are required for correctness in phase-2 and phase-3
2. Removing them would mean phase-2 bring-up has to add fault paths
   to already-verified routines, creating regression risk
3. They cost at most one microinstruction per service call (not taken)

### On SUB_FAULT_HANDLER in phase-1

Phase-1 SUB_FAULT_HANDLER uses INT_ENTER to deliver the exception via
the real-mode interrupt vector table. This is architecturally correct
for real mode. The handler does not return — it ends with ENDI.

When the fault vector is taken, the ENDI at the end of SUB_FAULT_HANDLER
must use CM_FAULT_END (which clears T0-T3 but does NOT clear fault state,
because the fault drives the INT_ENTER behavior). After ENDI, fault state
is cleared by commit_engine as part of normal ENDI processing with
INT_ENTER's staged values committed.

### On M_NEXT_EIP availability during CALL

ENTRY_CALL_NEAR uses M_NEXT_EIP as the return address to push on the
stack. This value must be valid when CALL begins executing. The decoder
must have already consumed all instruction bytes (including the
displacement) before asserting decode_done. M_NEXT_EIP is the EIP of
the byte immediately following the last consumed byte — exactly the
return address CALL must push.

This is why the decoder cannot assert decode_done before consuming all
instruction bytes. The microsequencer must not begin executing until
M_NEXT_EIP is valid and stable.

---

*End of Appendix D — Phase-1 Bring-Up Ladder and Exception Delivery Checklist*
