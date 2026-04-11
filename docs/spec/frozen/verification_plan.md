# Microcoded 486 — Companion Document 3
# Verification Plan
## Version 1.0

---

## 1. Verification Philosophy

Verification follows the same philosophy as the design itself:
correctness first, phase by phase, with each phase fully verified
before the next begins.

The primary ground truth for behavioral correctness is ao486's proven
compatibility record. Where ao486 passes a test vector, our design must
match its architectural output exactly. Where ao486 and the Intel 486
specification differ, the Intel specification is the authority.

Secondary ground truth is the 8088/8086 test vector suite (used by z8086),
which covers the integer subset. These vectors are valid for the real-mode
phase-1 instruction set.

### Verification Layers

    L1  Unit test — individual service modules in isolation
    L2  Microcode test — individual entry routines, instruction by instruction
    L3  Integration test — full CPU against pre-recorded instruction streams
    L4  Compliance test — against published x86 test vector suites
    L5  System test — boot real software in simulation

Each layer builds on the previous. A defect found at L3 should be
reproducible at L1 or L2 before it is considered fixed.

---

## 2. Testbench Architecture

### 2.1 Top-Level Testbench (tb_cpu_top)

    tb_cpu_top
    ├── dut: cpu_top
    ├── mem_model: flat 4MB behavioral memory
    ├── stimulus_gen: loads test programs, drives reset/interrupts
    ├── checker: monitors architectural state at each ENDI boundary
    ├── reference_model: software 486 emulator for expected-state generation
    └── coverage_collector: tracks instruction/path coverage

The testbench monitors all commit_engine outputs. At each endi_done
assertion, it snapshots the full architectural state:
    - all 8 GPRs
    - EIP
    - EFLAGS
    - all 6 segment selectors and caches
    - ESP (from GPR[4])

This snapshot is compared against the reference model's expected state
for the same instruction.

### 2.2 Reference Model Interface

The reference model is a software 486 emulator (Bochs or a custom
lightweight model) running the same instruction stream. At each
instruction boundary, the reference model exports:
    - expected register state
    - expected EFLAGS
    - expected memory writes (address, data, byte-enables)

The checker compares DUT state against reference model state and
reports mismatches with full context.

### 2.3 Memory Model

A flat behavioral memory (SystemVerilog associative array or Verilog
$readmemh-loaded array) provides:
    - configurable latency (0, 1, or random cycles)
    - read/write monitoring (all accesses logged)
    - alignment checking (detects if DUT issues unaligned accesses
      to the external bus — should never happen)
    - self-checking: verifies bus_interface byteen signals

---

## 3. Phase-1 Verification Plan

### 3.1 L1 — Service Unit Tests

Each service module has its own unit testbench.

---

**tb_alu**

Test cases:
- ADD8/16/32: all combinations of zero, positive, negative, max operands
- SUB8/16/32: same
- AND/OR/XOR: bit patterns (all-zero, all-one, alternating, random)
- CMP: verify T0 unchanged, T3 flags correct
- ADC/SBB: carry-in = 0 and carry-in = 1

Flag checks per operation:
- CF: carry/borrow out
- OF: signed overflow
- ZF: result is zero
- SF: sign bit of result
- PF: parity of low byte
- AF: auxiliary carry (bit 3 carry for ADD/SUB/ADC/SBB)

Width masking checks:
- 8-bit: result[31:8] must be zero
- 16-bit: result[31:16] must be zero

Corner cases:
- ADD: 0xFF + 0x01 (byte wrap, CF=1)
- ADD: 0x7F + 0x01 (signed overflow, OF=1)
- SUB: 0 - 1 (borrow, CF=1)
- SUB: 0x80 - 1 (signed underflow, OF=1)
- AND: 0xFFFFFFFF & 0 = 0 (ZF=1)
- XOR: x ^ x = 0 (ZF=1)

Expected pass criterion: all 486 flag behaviors match Intel
Architecture Software Developer's Manual Volume 2 flag tables.

---

**tb_ea_calc**

Test cases for 16-bit modes:
- All 8 ModRM.r/m combinations with mod=00 (no disp)
- All 8 with mod=01 (disp8)
- All 8 with mod=10 (disp16)
- Special case: mod=00, r/m=110 → direct address (disp16 only)
- BP-relative forms → seg_hint = SS

Test cases for 32-bit modes:
- Direct register (mod=11 handled by load_store, not ea_calc)
- Base-only (mod=00, no SIB)
- Base + disp8 (mod=01)
- Base + disp32 (mod=10)
- SIB forms: all scale factors (×1/×2/×4/×8), all index registers
- SIB with no base (base=101, mod=00): disp32 only
- SIB with EBP base: verify SS segment hint
- EIP-relative addressing: not in phase-1

Corner cases:
- Displacement sign extension: disp8 = 0x80 → -128
- Wrap-around in 16-bit mode: base + disp > 0xFFFF

---

**tb_load_store**

Register form tests:
- LOAD_RM8: all 8 registers, verify zero-extension
- LOAD_RM16: all 8 registers, verify zero-extension
- LOAD_RM32: all 8 registers
- STORE_RM8/16/32: write then read-back

Memory form tests:
- Aligned byte/word/dword reads and writes
- Memory latency: 0 cycles (immediate ready)
- Memory latency: 1 cycle (ready deferred)
- Memory latency: random (stress test)
- Verify byteen signals: LOAD_RM8→0001, LOAD_RM16→0011, LOAD_RM32→1111
  (for aligned addresses)

Unaligned (handled by bus_interface, not load_store, but verify
the bus_interface splits are correct via this testbench):
- 16-bit at odd address → two byte reads
- 32-bit at non-dword address → multiple reads

---

**tb_stack_engine**

PUSH tests:
- PUSH16: verify ESP decremented by 2, word written at new ESP
- PUSH32: verify ESP decremented by 4, dword written at new ESP
- Stack wraps at 0 (16-bit mode: wraps at 0xFFFF→0xFFFD)
- pc_stack_val staged correctly

POP tests:
- POP16: verify word read at ESP, ESP incremented by 2
- POP32: verify dword read at ESP, ESP incremented by 4
- Correct value returned in pop_val

Wait behavior:
- Assert req, deassert bus_ready → verify done not asserted
- Assert bus_ready → verify done asserted, correct value

---

**tb_flow_control**

COMPUTE_REL_TARGET:
- Forward branch: next_eip=0x1000, disp=+32 → target=0x1020
- Backward branch: next_eip=0x1000, disp=-10 → target=0x0FF6
- Zero displacement → target = next_eip
- Boundary: wrap at 0xFFFF in 16-bit mode

VALIDATE_NEAR_TRANSFER (real mode):
- target = 0x0000: OK
- target = 0xFFFF: OK (16-bit limit)
- target = 0x10000: FAULT(GP)
- target = 0x0001 (odd): OK (no alignment requirement for code)

CONDITION_EVAL — all 16 Jcc conditions:
- Each condition tested with flags set such that condition IS true
- Each condition tested with flags set such that condition IS NOT true
- Boundary cases: ZF+CF combinations for JBE/JNBE

---

**tb_fetch_engine**

FETCH_IMM8: consume 1 byte, zero-extension
FETCH_IMM8SX: consume 1 byte, sign-extension (0x80→0xFFFFFF80)
FETCH_IMM16: consume 2 bytes, little-endian
FETCH_IMM32: consume 4 bytes, little-endian
FETCH_DISP8: consume 1 byte, sign-extend
FETCH_DISP16/32: consume 2/4 bytes

Wait behavior: queue empty → WAIT → queue fills → done

---

**tb_commit_engine**

STAGE tests:
- Stage GPR: verify pc_gpr_en set, pc_gpr_idx correct, pc_gpr_val correct
- Stage EIP: verify pc_eip_en set
- Stage EFLAGS with mask: verify only masked bits affected on commit
- Stage SEG: verify all segment fields captured
- Stage STACK: verify pc_stack_val set
- Last-write-wins: STAGE same field twice → second value wins

ENDI tests:
- All commit mask combinations
- GPR commit: gpr[idx] updated
- EIP commit: eip updated, flush asserted
- EFLAGS masked commit: only specified bits changed
- STACK commit: gpr[4] (ESP) updated
- Temp clear bits: T0-T3 cleared when bit 6 set
- CLRF bit: fault state cleared
- FLUSHQ: flush_req asserted with correct flush_addr

Fault suppression:
- Stage GPR + EIP, then raise fault before ENDI
- Verify: ENDI with fault pending suppresses both commits
- Verify: fault state preserved after ENDI

Ordering:
- Commit with both GPR and EIP staged → verify GPR applied before EIP
- Commit with SEG and EIP → verify SEG before EIP

---

**tb_interrupt_engine**

INT_ENTER (real mode):
- Vector 0: read IVT[0:3], push FLAGS/CS/IP, load new CS:IP
- Vector 0x21 (DOS): read IVT[0x84:0x87], full sequence
- Verify: IF cleared in staged EFLAGS
- Verify: TF cleared in staged EFLAGS
- Verify: stack has correct FLAGS/CS/IP in correct order
- Verify: pc_seg and pc_eip staged to new CS:IP values

IRET_FLOW (real mode):
- Pop IP/CS/FLAGS from stack in correct order
- Verify: staged EIP = popped IP
- Verify: staged CS = popped CS
- Verify: staged EFLAGS = popped FLAGS (all bits including IF)

Nested: INT then IRET → architectural state restored exactly

---

### 3.2 L2 — Instruction-Level Tests

One test per instruction form. Each test:
1. Loads a single instruction into memory
2. Sets initial architectural state (registers, flags, memory)
3. Runs the CPU until endi_done
4. Compares final state against expected

Expected state is pre-computed using the reference model.

---

**MOV tests**

    MOV EAX, EBX         ; reg-to-reg 32-bit
    MOV AX, BX           ; reg-to-reg 16-bit
    MOV AL, BL           ; reg-to-reg 8-bit
    MOV EAX, [EBX]       ; memory-to-reg, no disp
    MOV EAX, [EBX+4]     ; memory-to-reg, disp8
    MOV EAX, [EBX+0x100] ; memory-to-reg, disp32
    MOV [EBX], EAX       ; reg-to-memory
    MOV [EBX+4], EAX     ; reg-to-memory, disp8
    MOV EAX, 0x12345678  ; imm32 to reg
    MOV AX,  0x1234      ; imm16 to reg
    MOV AL,  0x12        ; imm8 to reg
    MOV [EBX], 0x42      ; imm8 to memory (byte)
    MOV [EBX], dword 0x12345678  ; imm32 to memory

Verify for each:
- Correct destination updated
- All other registers unchanged
- EFLAGS unchanged (MOV does not affect flags)
- Correct memory write (for store forms)

---

**ALU tests (ADD, SUB, AND, OR, XOR, CMP)**

For each operation, test:
    op reg32, reg32      ; all flags
    op reg32, [mem]      ; memory source
    op [mem], reg32      ; memory destination
    op reg32, imm32      ; immediate
    op reg32, imm8sx     ; sign-extended immediate (83 opcode)
    op AL, imm8          ; accumulator short form

For each variant:
- Result correct
- CF correct
- OF correct  
- ZF correct (test with equal operands for CMP/SUB)
- SF correct
- PF correct
- AF correct

CMP-specific: verify destination unchanged after CMP

---

**PUSH/POP tests**

    PUSH EAX             ; register push 32-bit
    PUSH AX              ; register push 16-bit
    PUSH [mem]           ; memory push
    POP EAX              ; register pop 32-bit
    POP AX               ; register pop 16-bit
    POP [mem]            ; memory pop

Verify:
- Stack pointer decremented/incremented by correct amount (2 or 4)
- Correct value at top of stack after PUSH
- Correct register value after POP
- Correct memory write for POP [mem]

---

**Control flow tests**

    JMP SHORT target     ; EB rel8, forward and backward
    JMP NEAR target      ; E9 rel32, forward and backward
    JMP [mem]            ; FF /4, indirect
    CALL target          ; E8 rel32
    CALL [mem]           ; FF /2, indirect
    RET                  ; C3
    RET imm16            ; C2 nn nn

Jcc — all 16 conditions:
    JO  / JNO
    JB  / JNB   (also JC/JNC, JNAE/JAE)
    JZ  / JNZ   (also JE/JNE)
    JBE / JNBE  (also JNA/JA)
    JS  / JNS
    JP  / JNP   (also JPE/JPO)
    JL  / JNL   (also JNGE/JGE)
    JLE / JNLE  (also JNG/JG)

For each Jcc: test taken case AND not-taken case.

CALL/RET pair:
- Verify return address pushed correctly
- Verify EIP restored after RET
- Verify ESP restored after RET
- RET imm16: verify ESP adjusted by immediate

---

**INT/IRET tests**

    INT 0x00     ; divide-by-zero vector
    INT 0x21     ; DOS interrupt vector
    INT 0xFF     ; high vector number

For each INT:
- Verify IVT read at correct address (vector*4)
- Verify FLAGS pushed to stack at correct SP
- Verify CS pushed at SP-2
- Verify IP pushed at SP-4
- Verify new CS:IP loaded from IVT
- Verify IF=0 in new EFLAGS
- Verify TF=0 in new EFLAGS

IRET after INT:
- Verify IP/CS/FLAGS popped in correct order
- Verify architectural state fully restored
- Verify IF restored to pre-INT value
- Verify SP restored

---

**Flags tests**

    CLC          ; CF=0
    STC          ; CF=1
    CLI          ; IF=0
    STI          ; IF=1
    CLD          ; DF=0
    STD          ; DF=1
    NOP          ; no flag change

Verify for each: only the specified flag changes, all others unchanged.

---

**INC/DEC tests**

    INC EAX      ; 32-bit
    INC AX       ; 16-bit
    DEC EAX      ; 32-bit
    DEC AX       ; 16-bit

Verify:
- Result correct
- OF, SF, ZF, AF, PF updated correctly
- CF NOT modified (critical)

INC wrapping: verify INC 0xFFFFFFFF = 0x00000000 with ZF=1, OF=1

---

**TEST/LEA tests**

    TEST EAX, EBX    ; AND but discard result
    TEST EAX, imm32
    TEST AL, imm8

For TEST: verify destination unchanged, flags set as if AND performed.

    LEA EAX, [EBX+ECX*4+8]   ; 32-bit SIB form
    LEA AX, [BX+SI+4]         ; 16-bit form
    LEA EAX, [EBX]            ; simple base

For LEA: verify EA value stored in register, no memory access performed,
flags unchanged.

---

### 3.3 L3 — Integration Tests

Short programs that exercise instruction sequences, including
cross-instruction interactions (flag carry-through, stack integrity,
call/return nesting).

---

**Arithmetic sequence test**

    xor  eax, eax
    mov  ecx, 10
  loop:
    add  eax, ecx
    dec  ecx           ; note: DEC does not affect CF
    jnz  loop
    ; result: EAX = 10+9+8+...+1 = 55

Verify: EAX=55, ECX=0, ZF=1, CF unchanged throughout.

---

**Stack nesting test**

    mov  eax, 0xDEAD
    push eax
    mov  ebx, 0xBEEF
    push ebx
    call sub1
    ; sub1:
    ;   push ecx
    ;   mov  ecx, 0x1234
    ;   pop  ecx
    ;   ret
    pop  ebx
    pop  eax

Verify: EAX=0xDEAD, EBX=0xBEEF, ECX unchanged, ESP restored.

---

**Interrupt round-trip test**

    Set up IVT[0x30] = test_handler
    INT 0x30
    ; (falls into test_handler which does IRET)
    ; Verify architectural state fully restored after IRET

---

**Memory read-modify-write test**

    mov  [mem], dword 0x100
    add  [mem], dword 0x200
    ; verify [mem] = 0x300

---

**Conditional branch stress test**

A sequence of Jcc instructions with varying flag states, testing
the boundary between taken and not-taken for each condition code.

---

### 3.4 L4 — Compliance Tests

Use published x86 test vector suites.

**8088/8088 test vectors (from z8086 / ProcessorTests project)**

These cover the full 8086/8088 instruction set, which is a subset
of the 486 real-mode instruction set. All phase-1 instructions
appear in this suite.

Test format: JSON files with:
    - initial state (registers, flags, memory contents)
    - final state after one instruction

Run all vectors for phase-1 opcodes:
    - 0x00-0x3F (ADD/SUB/AND/OR family)
    - 0x40-0x5F (INC/DEC/PUSH/POP reg)
    - 0x70-0x7F (Jcc)
    - 0x80-0x8F (ALU imm, MOV, LEA, POP r/m)
    - 0x88-0x8D (MOV forms)
    - 0x90 (NOP)
    - 0xA8-0xA9 (TEST acc,imm)
    - 0xB0-0xBF (MOV reg,imm)
    - 0xC2-0xC3 (RET)
    - 0xC6-0xC7 (MOV r/m,imm)
    - 0xCD (INT)
    - 0xCF (IRET)
    - 0xE8-0xE9 (CALL/JMP rel)
    - 0xEB (JMP short)
    - 0xF8-0xFD (flag ops)
    - 0xFF (CALL/JMP/PUSH indirect)

Pass criterion: 100% of applicable test vectors pass.
This is the same criterion z8086 uses (16,150/16,150 pass rate).

**ao486 test suite (from ao486 sim)**

The ao486 simulation includes instruction-level test infrastructure.
Run the ao486 sim against the same instruction sequences used in L2,
compare outputs.

---

### 3.5 L5 — System Tests

Boot real software in simulation.

**Phase-1 system test: DOS bootstrap stub**

A minimal real-mode program that:
1. Sets up a simple IVT (real handlers for INT 0x10 text output)
2. Clears and fills a text buffer in memory
3. Exercises a loop with all phase-1 instructions
4. Issues a halt (HLT — phase-1 excluded, so ends with infinite loop)

Expected: program runs to infinite loop, memory contents match expected.

**Phase-2 system test: protected mode entry**

Set up GDT, load CS/DS descriptors, switch to protected mode via
CR0.PE, execute flat-model code in protected mode.

**Phase-3 system test: boot DOS**

Full ao486 boot test: run the design against the ao486 DOS boot image
in simulation. Pass criterion: DOS prompt reached.
This is the ultimate compatibility validation.

---

## 4. Regression Strategy

### 4.1 Test Hierarchy for Regression

On any RTL change:
1. Run all L1 unit tests for affected modules (< 1 minute each)
2. Run L2 for any affected instruction families (< 5 minutes total)
3. Run L4 compliance vectors for affected opcodes (< 10 minutes)
4. If all pass: run full L2 + L4 suite (< 30 minutes)
5. Run L3 integration tests (< 10 minutes)
6. Run L5 system test (minutes to hours depending on simulation speed)

### 4.2 Coverage Goals

Instruction coverage:
- Every phase-1 opcode executed at least once: required before tapeout
- Every phase-1 opcode executed with memory operands: required
- Every Jcc taken and not-taken: required

Microcode coverage:
- Every microcode address executed at least once: tracked by testbench
- Every branch taken and not-taken at each BR instruction: tracked
- SUB_FAULT_HANDLER triggered by at least one fault per fault class: required

Service coverage:
- Every service called at least once: required
- WAIT return path exercised for every wait-capable service: required

Flag coverage:
- CF=0/CF=1 after each flag-setting instruction: required
- OF=0/OF=1 after ADD/SUB: required
- ZF=0/ZF=1 after each flag-setting instruction: required

### 4.3 Performance Monitoring

During simulation, the testbench counts:

    - Total clocks elapsed
    - Total instructions retired
    - Average clocks per instruction (CPI)
    - Stall cycles due to memory wait
    - Stall cycles due to prefetch queue empty

These metrics are reported per-test and tracked over time to detect
regressions in performance behavior.

---

## 5. Debug Infrastructure

### 5.1 Microcode Execution Trace

The testbench can enable a microcode trace mode that prints, per clock:

    [cycle N] uPC=0x0A2 microinst=0x32100015 SVC(0x22=LOAD_RM32) SR=OK
    [cycle N] uPC=0x0A3 microinst=0x04200013 MOV T1,T0
    [cycle N] uPC=0x0A4 microinst=0x32100010 SVC(0x80=COMMIT_GPR) SR=OK
    [cycle N] uPC=0x0A5 ENDI mask=0x1C7

This trace is invaluable for debugging incorrect behavior at the
microcode level.

### 5.2 Architectural State Dump

At each ENDI, dump:

    EIP=0x00001234 EFLAGS=0x00000202
    EAX=0x00000000 EBX=0x00001000 ECX=0x0000000A EDX=0x00000000
    ESP=0x0000FFFC EBP=0x00000000 ESI=0x00000000 EDI=0x00000000
    CS=0000 DS=0000 ES=0000 SS=0000 FS=0000 GS=0000

### 5.3 Memory Access Log

All bus_interface transactions logged:

    [cycle 45] MEM_READ  addr=0x0000IVT4 data=0xF000:0x0100 byteen=1111
    [cycle 52] MEM_WRITE addr=0x0000FFFA data=0x0202 byteen=0011 (FLAGS)
    [cycle 55] MEM_WRITE addr=0x0000FFF8 data=0x0000 byteen=0011 (CS)
    [cycle 58] MEM_WRITE addr=0x0000FFF6 data=0x1236 byteen=0011 (IP)

### 5.4 Fault Injection

The testbench can assert fault conditions at controlled points:

    - Inject memory error during load
    - Inject memory error during store
    - Force queue-empty during instruction fetch

Used to verify the fault handler path for faults that cannot be
easily triggered by software in real mode.

---

## 6. Known Phase-1 Limitations (Documented Exclusions)

The following behaviors are NOT tested in phase-1 and are not
expected to work:

- Protected mode of any kind (all access is real mode)
- Paging (no CR3, no TLB)
- Segment limit checking (SS/DS limits not enforced)
- Privilege level transitions (CPL always 0)
- Far JMP/CALL/RET (not implemented)
- Task switching (not implemented)
- String instructions (not implemented)
- Shift/rotate instructions (not implemented)
- MUL/IMUL/DIV/IDIV (not implemented)
- FPU (not implemented)
- SMM (system management mode) (not implemented)
- Cycle-accurate timing (not a goal)
- LOCK prefix (not implemented)
- IO privilege (always permitted in real mode)

These exclusions are tracked as open issues to be addressed in
phase-2 and phase-3.

---

*End of Companion Document 3 — Verification Plan*
