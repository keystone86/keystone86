# Microcoded 486 — Appendix B
# Module Ownership Matrix
# Version 1.0 — FROZEN
#
# This document defines, for every architectural concern, exactly which
# module owns it and which modules are explicitly forbidden from owning it.
# When implementation drift occurs, this matrix is the arbiter.
# If a module is doing something not listed under its "owns" column,
# that is a drift violation and must be corrected.

---

## PRIMARY OWNERSHIP TABLE

| Concern | Owned By | Forbidden To |
|---------|----------|--------------|
| Instruction meaning and semantics | microcode ROM (entry routines) | decoder, all services, all hardware blocks |
| Instruction sequencing and control flow | microsequencer | decoder, all services, all hardware blocks |
| Opcode classification and entry selection | decoder | microsequencer, all services, all hardware blocks |
| Metadata population (M_* fields) | decoder | microsequencer, all services, all hardware blocks |
| Architectural state visibility | commit_engine (via ENDI only) | decoder, microsequencer, all services, all hardware blocks |
| Pending commit record | commit_engine | all others (read-only via service staging interface) |
| Fault ordering and exception priority | microcode (entry routines + SUB_FAULT_HANDLER) | all services, all hardware blocks, commit_engine |
| Fault detection (per-service) | the service responsible for that check | microsequencer, decoder, commit_engine |
| Fault vectoring and delivery | microcode (SUB_FAULT_HANDLER) | all services, commit_engine, microsequencer |
| GPR values (architectural) | commit_engine (applies); microcode (stages) | decoder, all services directly |
| EIP (architectural) | commit_engine (applies); microcode (stages) | decoder, all services directly |
| EFLAGS (architectural) | commit_engine (applies); microcode (stages) | decoder, all services directly |
| Segment registers and caches | commit_engine (applies); microcode (stages) | decoder, all services directly |
| ESP/SP (architectural) | commit_engine (applies); stack_engine (stages) | decoder, load_store, fetch_engine directly |
| Prefetch queue content | prefetch_queue | all other modules |
| Prefetch queue flush | commit_engine (initiates); prefetch_queue (executes) | all other modules |
| Temporary registers T0-T7 | microsequencer (writes); services (writes per ABI) | commit_engine, decoder, bus_interface |
| Service dispatch routing | service_dispatch | microsequencer (requests only), all hardware blocks |
| External bus transactions | bus_interface | all other modules |
| Unaligned access splitting | bus_interface | load_store, stack_engine, prefetch_queue |
| Effective address calculation | ea_calc | load_store, stack_engine, flow_control |
| Register file indexing (architectural) | commit_engine (applies); LOAD_REG_META/STORE_REG_META (reads/stages) | decoder, microsequencer directly |
| Mode (real/protected) detection | commit_engine (provides); decoder (reads) | all services directly — services receive mode as metadata |
| Privilege level (CPL) | commit_engine (tracks); decoder (reads) | all hardware services directly |
| Descriptor loading from memory | load_descriptor service | microcode may call, but not implement inline |
| Page table walks | paging_engine (phase 3) | load_store, bus_interface directly |

---

## MODULE-BY-MODULE OWNERSHIP STATEMENT

### decoder

**Owns:**
- Opcode family recognition
- Entry ID selection (dispatch table lookup)
- Operand size and address size determination
- Prefix accumulation (up to 2 prefixes)
- ModRM class determination
- SIB field parsing
- Displacement class determination
- Immediate class determination
- Population of all M_* metadata fields
- Population of M_NEXT_EIP
- decode_done assertion timing
- Byte consumption from prefetch queue

**Must not:**
- Implement any instruction semantics
- Read from or write to the register file
- Access memory
- Modify any architectural register
- Generate faults (unrecognized opcode → ENTRY_NULL; fault is raised by microcode)
- Know the current value of any GPR, EIP, or EFLAGS
- Decide what an instruction means — only which entry handles it

---

### microsequencer

**Owns:**
- micro-PC management
- Return stack management
- Entry dispatch (entry ID → micro-PC via dispatch table)
- Microinstruction fetch and decode
- Service invocation (SVC/SVCW)
- Stall management on WAIT
- Fault state transitions (EXECUTE → FAULT_HOLD → EXECUTE)
- NMI pending check after ENDI
- STAGE request issuance
- ENDI request issuance to commit_engine
- RAISE and CLEAR_FAULT issuance
- Temporary register read/write via reg_file

**Must not:**
- Implement instruction semantics (it executes microcode, not x86 semantics)
- Access memory directly
- Modify architectural state directly
- Know anything about x86 instruction encoding
- Make instruction-level decisions — only microcode program decisions

---

### microcode ROM (entry routines + shared subroutines)

**Owns:**
- Instruction meaning
- Instruction sequencing
- Privilege and protection flow
- Exception ordering (which faults take priority in which instruction)
- Decision to retry, vector, or continue after fault
- Service call ordering
- Commit staging decisions (what gets committed and when)
- Architectural commit authority (via ENDI mask)

**Must not:**
- Be bypassed for any instruction — all instructions must go through entry routines
- Have instruction policy implemented in hardware instead
- Have exception ordering decided anywhere else

---

### service_dispatch

**Owns:**
- Routing service requests from microsequencer to correct hardware module
- Muxing done and sr_out back to microsequencer
- No policy of its own — pure routing

**Must not:**
- Make decisions about instruction meaning
- Modify any state directly
- Hold any persistent state beyond mux selection

---

### alu

**Owns:**
- 8/16/32-bit arithmetic and logic computation
- Flag computation (CF, OF, ZF, SF, PF, AF) → T3 encoding
- done signal (always 1 — combinational)

**Must not:**
- Know which instruction is executing
- Read current EFLAGS (except carry_in for ADC/SBB, passed explicitly)
- Write to any register directly — result returned via service interface
- Make decisions about which operation to perform — op selected by microcode via subop

---

### ea_calc

**Owns:**
- 16-bit and 32-bit effective address computation
- SIB byte handling
- Default segment hint computation (→ T5)

**Must not:**
- Add segment base to the offset (that is LINEARIZE_OFFSET, phase 2)
- Access memory
- Know which instruction is executing

---

### load_store

**Owns:**
- Register-form operand reads (reading GPR via reg_file)
- Memory-form reads and writes via bus_interface
- Zero-extension of sub-word reads to 32 bits
- Width selection per service ID

**Must not:**
- Compute effective addresses (ea_calc owns that)
- Linearize addresses through segments (LINEARIZE_OFFSET owns that)
- Implement instruction semantics
- Modify architectural state directly

---

### stack_engine

**Owns:**
- Stack push (SP decrement + write)
- Stack pop (SP increment + read)
- PC_STACK_* staging
- Stack memory access via bus_interface

**Must not:**
- Compute segment-relative addresses (uses SS_BASE from commit_engine)
- Check segment limits in phase 1
- Know which instruction is executing

---

### flow_control

**Owns:**
- Relative branch target computation (COMPUTE_REL_TARGET)
- Near transfer validation (VALIDATE_NEAR_TRANSFER)
- Jcc condition evaluation (CONDITION_EVAL)

**Must not:**
- Stage EIP — that is COMMIT_EIP in microcode
- Know which instruction is executing (pure functional block)

---

### fetch_engine

**Owns:**
- Consuming bytes from prefetch queue for FETCH_IMM*/FETCH_DISP*
- Width-appropriate byte assembly (little-endian)
- Sign-extension for displacement/signed immediate forms
- WAIT return when queue is empty

**Must not:**
- Classify instruction bytes (that is the decoder)
- Know which instruction is executing

---

### commit_engine

**Owns:**
- Architectural register file (all 8 GPRs)
- EIP register
- EFLAGS register
- All 6 segment registers (selector + hidden cache)
- CR0, CR2, CR3 (phase 3)
- GDTR, IDTR, LDTR, TR (phase 2)
- Pending commit record (all PC_* fields)
- ENDI execution (applying staged fields in order)
- Fault suppression on ENDI when fault is pending
- Prefetch queue flush initiation
- Mode (real/protected) reporting to decoder
- CS.D bit reporting to decoder
- CPL reporting to decoder

**Must not:**
- Know what any instruction means
- Make instruction-policy decisions
- Decide which fields to commit — that is microcode's ENDI mask
- Raise faults — it may detect invariant violations at commit time
  (reported as a special ENDI fault return) but does not own fault ordering

---

### bus_interface

**Owns:**
- External bus signal generation (addr, dout, rd, wr, byteen, io)
- Bus request arbitration (EU over prefetch queue)
- Unaligned access splitting into aligned transactions
- Ready handshake with external memory
- Interrupt acknowledge (INTA) cycling

**Must not:**
- Know what the CPU is doing
- Make decisions based on instruction type
- Access the register file
- Modify any architectural state

---

### prefetch_queue

**Owns:**
- Instruction byte buffering
- Speculative fetch ahead of decoder
- Queue flush on control flow change (initiated by commit_engine)
- Byte valid signaling to decoder

**Must not:**
- Classify bytes (that is the decoder)
- Know instruction boundaries beyond the first unconsumed byte
- Initiate flushes on its own — only on flush_req from commit_engine

---

## ANTI-DRIFT CHECKLIST

The following are prohibited regardless of performance motivation:

1. A hardware service that internally sequences through multiple x86
   instruction steps without microcode control.

2. A decoder that computes operand values, reads registers, or
   prepares data beyond metadata classification.

3. Any module writing to EIP, EFLAGS, GPRs, or segment caches
   except through the commit_engine staging interface.

4. A service that checks mc_cmd or any instruction identity token
   to decide what to do (services must be instruction-agnostic).

5. A service that calls another service internally (services are
   leaf functions; only microcode calls services).

6. Exception priority being decided by hardware comparison logic
   rather than microcode sequencing.

7. Partial commits becoming architecturally visible before ENDI.

8. Prefetch queue flushed by any module other than commit_engine.

If any of these appear during implementation, they must be refactored
before the affected phase is considered complete.

---

*End of Appendix B — Module Ownership Matrix*
