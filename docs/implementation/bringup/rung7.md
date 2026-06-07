# Keystone86 / Aegis - Rung 7 ALU Operations Directive

## Purpose

Rung 7 is the frozen-spec ALU Operations bring-up rung after the accepted
Rung 6 MOV matrix.

Rung 7 proves the bounded ALU operation slice end to end through the intended
Keystone86 staged microcoded architecture. It is not merely an ALU unit test,
opcode recognition exercise, donor-material import, or future-framework pass.

Rung 7 must prove that the required ALU instruction set can move through the
full path:

1. `decoder` recognizes only the frozen in-scope ALU forms and emits
   decode-owned metadata.
2. instruction bytes, ModRM, immediates, displacements, addressing metadata,
   operand width, `M_ALU_OP`, `M_IS_CMP`, and `M_NEXT_EIP` are consumed and
   produced in a bounded, observable way.
3. `microsequencer` dispatches to explicit `ENTRY_ALU_*` microcode.
4. microcode owns instruction meaning, sequencing, service ordering, fault
   ordering, staging intent, CMP destination suppression, and commit intent.
5. operand, immediate, effective-address, load/store, register metadata, ALU,
   flag, and commit helper paths perform bounded reusable mechanisms only.
6. ALU result and candidate flags are produced for the active operation and
   width.
7. non-CMP register-destination forms stage a pending GPR write and pending
   EFLAGS update.
8. non-CMP memory-destination forms perform read-modify-write under microcode
   sequencing and stage/commit flags according to the selected Rung 7 path.
9. CMP updates flags but suppresses destination writeback.
10. architectural GPR and EFLAGS effects become visible only through the
    intended commit boundary.
11. memory effects occur only through the intended load/store and bus path
    under microcode sequencing.
12. final EIP equals `M_NEXT_EIP`.
13. accepted Rung 5 and Rung 6 behavior remains intact.

Rung 7 is intentionally bounded to the frozen ALU Operations slice:

```text
ADD
SUB
AND
OR
XOR
CMP
```

It is not an ADC/SBB rung, TEST rung, INC/DEC rung, shift/rotate rung,
multiply/divide rung, flags-instruction rung, protected-mode rung, ao486 RTL
import, z8086 clone, cleanup pass, performance pass, or broad ALU framework.

The intended Rung 7 implementation style is microcode-dominant:

- microcode owns instruction sequencing and instruction meaning.
- RTL provides bounded reusable mechanisms and services.
- RTL must not become hidden per-instruction execution logic.
- decoder remains metadata/classification only.
- services remain leaf mechanisms under microcode control.
- commit remains the architectural visibility boundary for register and flags
  state.
- memory writes remain on the intended load/store/bus path.
- registered handoffs, bubbles, and `SR_WAIT` holds remain valid design tools.

---

## Rung 7 Intent

Rung 7 is the first flags-production and data-transform rung after MOV.

It builds directly on:

- Rung 5 commit/fault/interrupt discipline, including ENDI-controlled
  architectural visibility.
- Rung 6 MOV metadata, addressing, immediate, register-file, load/store, and
  register writeback infrastructure.

Rung 7 must use those accepted baselines without turning them into broad,
future-facing machinery.

The rung must remain microcode-dominant. The Rung 7 ALU helper may compute a
bounded result and candidate arithmetic flags, but the helper does not own
instruction meaning or architectural visibility. Microcode decides what the
operation means and which architectural effects are staged and committed.

No partial implementation slice is Rung 7 complete.

Rung 7 is complete only when the frozen Appendix D ALU Operations gate is
implemented, verified, documented from actual runs, semantically aligned
against the approved donor corpus or explicitly approved replacement
reference, and explicitly accepted.

---

## Status

Rung 7 is in planning/directive stage only.

Rung 6 is accepted, merged into `main`, and tagged. The accepted Rung 6 tag is:

```text
rung6-accepted -> 8126bd4
```

The `main` merge checkpoint is:

```text
b9c7d22 merge: accept rung6 final MOV matrix
```

No Rung 7 implementation is accepted yet. This document does not authorize RTL,
microcode, tests, Makefile, generated-artifact, frozen-spec, or other
protected-document edits by itself.

---

## Required Reading and Precedence

Future agents must read `AGENTS.md` first and follow it exactly.

Before classifying, planning, testing, or implementing any Rung 7 behavior,
future agents must read:

1. `AGENTS.md`
2. relevant frozen specifications under `docs/spec/frozen/`, especially:
   - `docs/spec/frozen/appendix_d_bringup_ladder.md`
   - `docs/spec/frozen/appendix_a_field_dictionary.md`
   - `docs/spec/frozen/appendix_b_ownership_matrix.md`
   - `docs/spec/frozen/appendix_c_assembler_spec.md`
   - `docs/spec/frozen/verification_plan.md`
3. this active rung file: `docs/implementation/bringup/rung7.md`
4. `docs/implementation/coding_rules/source_of_truth.md`
5. `docs/process/rung_execution_and_acceptance.md`
6. `docs/process/codex_workflow.md`
7. `docs/implementation/rung6_acceptance.md`
8. `docs/implementation/rung6_verification.md`
9. `third_party/ao486_notes/IMPORT_MANIFEST.md`
10. `third_party/ao486_notes/commands/CMD_Arith.txt`
11. the specific RTL, microcode, script, Makefile, generated, test, or
    documentation files proposed for read-only inspection or authorized change

Precedence on conflict:

1. frozen specs under `docs/spec/frozen/`
2. `AGENTS.md`
3. active rung file: `docs/implementation/bringup/rung7.md`
4. source-of-truth and coding-rule documents
5. process and acceptance documents
6. verification records
7. user task prompt
8. reviewer comments, correction briefs, prior chat context, implementation
   notes, donor notes, and summaries

This file is a bounded bring-up directive. It does not replace the documents
above it.

If this file conflicts with the frozen Appendix D Rung 7 gate, Appendix D wins.

Do not infer intent from prior conversations, summaries, analogies, external
project knowledge, donor material, stale constants, future-facing constants, or
agent memory when a frozen or process authority document answers the question.

---

## Authority and Usage

This is a bring-up directive document.

It is:

- a bounded implementation-intent note for Rung 7
- subordinate to the required reading chain above
- the baseline alignment document for future Rung 7 implementation and review
- a guardrail against hidden RTL instruction execution
- a guardrail against broad unreviewed ALU expansion
- a guardrail against narrowing the frozen Appendix D ALU Operations gate
- a guardrail against widening Rung 7 because Appendix A contains ADC, SBB,
  TEST, or future-facing constants
- a guardrail against treating ao486 `CMD_Arith` as an RTL or pipeline source
- a guardrail against treating z8086 or 8086 vectors as the target
  architecture
- a guardrail against turning missing microinstruction support into hidden ALU
  RTL behavior
- a guardrail against premature TEST, INC/DEC, flags-instruction, protected
  mode, or future-rung work

It is not:

- implementation authorization
- test-change authorization
- the final verification record
- the final acceptance record
- the sole authority for implementation
- permission to narrow the frozen Rung 7 gate
- permission to widen scope beyond Appendix D
- permission to alter frozen specifications
- permission to edit protected authority files outside this exact path
- permission to commit or push
- permission to redesign decode, service, microcode, commit, register-file,
  memory, exception, or flag architecture
- permission to implement Rung 8 or later behavior
- permission to use inferred intent as design authority
- permission to treat known implementation gaps as optional

Verification results do not belong in this file. Record actual future Rung 7
run results in:

- `docs/implementation/rung7_verification.md`

Acceptance does not belong in this file. Record explicit future project-owner
acceptance separately in:

- `docs/implementation/rung7_acceptance.md`

Those future files must be created or updated only when authorized and only
from actual run evidence.

---

## Protected-File Rule

This file is a protected authority file under `AGENTS.md`.

Do not edit, rewrite, rename, delete, move, reformat, or commit changes to this
file unless the user explicitly authorizes this exact file and exact intended
change.

The same protected-file rule applies to:

```text
docs/spec/frozen/**
docs/implementation/coding_rules/**
docs/process/**
docs/implementation/bringup/rung*.md
AGENTS.md
```

If a protected file appears to need changes during Rung 7 work, stop and
report:

1. the protected file path
2. the exact change that appears necessary
3. why the change appears necessary
4. whether the issue is a conflict, typo, stale acceptance record, scope
   question, generated-source synchronization issue, or live-source
   implementation blocker

Do not bypass protected-file checks, Git hooks, CI checks, branch protections,
or repository guardrails.

---

## Exact Scope Source

For exact rung gate criteria and the frozen bring-up ladder, use:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

Appendix D defines Rung 7 as ALU Operations.

This file describes intent, pass structure, known blockers, candidate
resolutions, required decision points, and boundaries for Rung 7 implementation.
It does not replace Appendix D.

This file must not be used to infer additional instruction coverage beyond
what Appendix D and this file explicitly assign to Rung 7.

This file must also not be used to reduce the final Rung 7 acceptance scope
below the frozen Appendix D ALU Operations gate.

---

## z8086 and ao486 Usage Rule

The two frozen-spec project inspirations are:

```text
z8086 = structural template / architectural inspiration
ao486 = semantic corpus / instruction-behavior donor
```

Use both only as the frozen specifications define them.

### z8086 Structural-Template Rule

`z8086` and 8086/8088 material are supplemental overlap context only for
Rung 7.

They may help identify real-mode ALU vector expectations that overlap the
active Rung 7 slice, but they do not widen or narrow Rung 7.

Do not copy `z8086` blindly as an implementation source.

Do not treat 8086 vectors as the target architecture. Keystone86 remains the
target, with frozen Appendix D defining the active rung gate.

Do not import `z8086` behavior unless frozen specs or this active rung file
explicitly require that behavior.

### ao486 Semantic-Corpus Rule

`ao486` is the primary semantic donor corpus for Rung 7 instruction meaning.

The primary Rung 7 donor file is:

- `third_party/ao486_notes/commands/CMD_Arith.txt`

Allowed `ao486` donor use:

```text
ao486 CMD_Arith.txt <decode>
  -> Keystone86 dispatch metadata fields, ENTRY_ALU_* selection, M_ALU_OP,
     M_IS_CMP, operand width, immediate/displacement facts, and M_NEXT_EIP

ao486 CMD_Arith.txt <read>
  -> Keystone86 operand fetch, FETCH_*, FETCH_DISP_*, EA_CALC_*,
     LOAD_RM*, LOAD_REG_META, and WAIT sequencing intent

ao486 CMD_Arith.txt <execute>
  -> Keystone86 bounded ALU operation choice, result intent, CMP
     writeback-suppression intent, and flag intent

ao486 CMD_Arith.txt <write>
  -> Keystone86 STAGE, STORE_REG_META, STORE_RM*, FLAGS_FROM_T3,
     COMMIT_EFLAGS, CM_ALU_REG, CM_FLAGS, and ENDI intent where required
```

Forbidden `ao486` donor use:

```text
Do not import ao486 Verilog RTL.
Do not import ao486's pipeline as Keystone86 architecture.
Do not preserve ao486 read/execute/write stages as Keystone86 programming model.
Do not import ao486 token passing.
Do not import ao486 mutex/hazard network.
Do not import ao486 AutogenGenerator-style distributed combinational control.
Do not move instruction policy into decoder, services, service_dispatch,
microsequencer RTL, or commit_engine.
Do not copy broad arithmetic-family behavior beyond the frozen Rung 7 slice.
Do not use ao486 as permission to implement ADC, SBB, TEST, INC/DEC, shifts,
rotates, MUL/IMUL, DIV/IDIV, XADD, CMPXCHG, bit-test, string, system, control,
or debug behavior.
```

Do not infer additional architectural rules from either `z8086` or `ao486`.

---

## Microcode-Dominant Implementation Rule

Rung 7 is expected to be microcode-dominant.

Instruction sequencing belongs in:

```text
microcode entry routines
microsequencer control flow
explicit service calls
explicit WAIT handling
explicit fault-order handling
explicit staging decisions
explicit ENDI commit points
```

RTL may be added only as bounded reusable mechanisms required by Appendix D.

Acceptable Rung 7 RTL, when implementation is authorized:

```text
decoder classification and ALU metadata capture
bounded immediate/displacement fetch support reused from Rung 6
bounded EA_CALC_16 / EA_CALC_32 reuse for ALU memory operands
bounded LOAD_RM8/16/32 and STORE_RM8/16/32 reuse for ALU operands
bounded LOAD_REG_META and STORE_REG_META reuse for ALU operands
bounded ALU result and flag helper for ADD/SUB/AND/OR/XOR/CMP
bounded EFLAGS staging and commit support required by Rung 7
bounded GPR writeback staging for non-CMP register destinations
bounded memory RMW store path for non-CMP memory destinations
generic Appendix C microinstruction support required by Rung 7
testbench observability needed to prove boundaries
```

Unacceptable Rung 7 RTL:

```text
hidden per-opcode ALU execution in decoder
hidden per-opcode ALU execution in service_dispatch
hidden per-opcode ALU execution in microsequencer
hidden ALU instruction policy in load_store
hidden ALU instruction policy in commit_engine
services becoming hidden ALU instruction engines
commit_engine becoming a hidden ALU instruction executor
decoder computing operands, ALU results, flags, or architectural effects
services deciding CMP policy or opcode-family policy
architectural GPR or EFLAGS visibility before ENDI
future-rung arithmetic, flag, or protected-mode behavior hidden inside Rung 7
```

Microcode owns instruction sequencing and ALU instruction meaning.

The microsequencer executes generic Appendix C microinstructions. It must not
become an x86 ALU semantic engine.

---

## In Scope

The final Rung 7 scope is the full ALU Operations scope required by:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

The active operation slice is:

```text
ADD
SUB
AND
OR
XOR
CMP
```

Required opcode families include:

```text
ADD: 00 /r, 01 /r, 02 /r, 03 /r, 04, 05, 80 /0, 81 /0, 83 /0
OR:  08 /r, 09 /r, 0A /r, 0B /r, 0C, 0D, 80 /1, 81 /1, 83 /1
AND: 20 /r, 21 /r, 22 /r, 23 /r, 24, 25, 80 /4, 81 /4, 83 /4
SUB: 28 /r, 29 /r, 2A /r, 2B /r, 2C, 2D, 80 /5, 81 /5, 83 /5
XOR: 30 /r, 31 /r, 32 /r, 33 /r, 34, 35, 80 /6, 81 /6, 83 /6
CMP: 38 /r, 39 /r, 3A /r, 3B /r, 3C, 3D, 80 /7, 81 /7, 83 /7
```

Required form coverage includes:

```text
reg/reg
reg/mem
mem/reg
reg/imm
accumulator short forms
memory-destination read-modify-write for non-CMP forms
CMP register and memory forms as flags-only operations
```

Required operand-size coverage includes the Rung 7 applicable 8-bit, 16-bit,
and 32-bit forms where the Appendix D ALU opcode families define those forms.

Required flag coverage:

```text
CF
OF
ZF
SF
PF
AF
```

Rung 7 includes only the narrowly scoped support genuinely required to make
the frozen ALU Operations slice function correctly end to end:

- decode recognition for the required ALU forms
- bounded opcode, ModRM, immediate, and displacement handling
- decode-owned ALU metadata, byte-consumption facts, operand/address-size
  facts, `M_ALU_OP`, `M_IS_CMP`, and `M_NEXT_EIP`
- source and destination register metadata capture
- register/memory operand metadata capture
- immediate assembly, including `83` sign-extended `imm8` behavior where
  required by the active ALU forms
- displacement assembly for memory operands
- effective-address calculation reuse required by ALU memory operands
- register metadata load/store support required by ALU forms
- memory load/store support required by ALU forms
- ALU result computation for ADD/SUB/AND/OR/XOR/CMP
- flag generation for CF/OF/ZF/SF/PF/AF
- logical operation flag behavior required by x86 for AND/OR/XOR
- pending GPR writeback staging for non-CMP register destinations
- CMP destination writeback suppression
- pending EFLAGS staging and commit
- memory RMW behavior for non-CMP memory destinations
- memory-source read-only behavior
- CMP memory read-only and flags-only behavior
- `M_NEXT_EIP` / final EIP advance
- phase-1 ALU fault-path structure required by Appendix D, with no phase-1
  ALU faults taken
- generic Appendix C microinstruction support required to execute Rung 7
  `ENTRY_ALU_*`
- observability required by Rung 7 testbenches
- future Make targets required to run the Rung 7 proof, only when authorized
- regression wiring proving Rung 5 and Rung 6 remain passing, only when
  authorized

Implementation must be staged. Earlier passes may prove smaller slices, but
those slices are not Rung 7 completion.

---

## Out of Scope

Unless explicitly authorized in a future active rung or protected-file pass,
Rung 7 does not include:

- ADC
- SBB
- TEST
- INC
- DEC
- NEG
- NOT
- shifts
- rotates
- MUL
- IMUL
- DIV
- IDIV
- XADD
- CMPXCHG
- bit-test families
- string behavior
- system behavior
- control behavior
- debug behavior
- broad flags instruction behavior
- CLC/STC/CLI/STI/CLD/STD
- LAHF/SAHF/PUSHF/POPF
- protected-mode behavior
- page behavior
- descriptor behavior
- privilege behavior
- segment-base addition
- generalized exception handling
- broad ALU framework beyond Rung 7 need
- future-rung preparation
- unrelated cleanup
- performance optimization
- broad Makefile cleanup
- broad microcode-generation refactor
- generated-artifact manual edits
- README or overview modernization before implementation facts exist

ADC and SBB appear in ao486 `CMD_Arith` and Appendix A `M_ALU_OP` encodings.
That presence is adjacent/background donor material only. It does not widen
Rung 7 unless a future active rung explicitly includes ADC/SBB.

Stale or future-facing constants do not widen scope and are not blockers by
themselves.

---

## Architectural Constraints

Rung 7 must preserve frozen ownership boundaries.

In particular:

- decoder remains classification and byte/metadata collection logic.
- decoder may identify required ALU entry points and collect bounded opcode,
  ModRM, immediate, displacement, register, width, addressing, `M_ALU_OP`,
  `M_IS_CMP`, byte-consumption, and `M_NEXT_EIP` metadata.
- decoder must not compute operand values.
- decoder must not compute ALU results or flags.
- decoder must not directly update architectural GPR, EIP, ESP/SP, EFLAGS,
  segment, stack, or memory state.
- microsequencer remains sequencing owner for generic microinstructions.
- microsequencer must not know x86 encoding beyond the decode payload and
  dispatch entry.
- microsequencer must not implement x86 ALU semantics directly.
- microcode must explicitly sequence required ALU behavior.
- ALU service computes bounded result and candidate flags only.
- ALU service must not know which instruction is executing.
- ALU service must not write architectural state directly.
- load_store performs operand access only under microcode sequencing.
- load_store must not decide ALU policy, CMP policy, or writeback policy.
- service_dispatch remains routing/muxing only.
- commit path publishes architectural register and flags state only at ENDI.
- memory writes remain on the intended load/store/bus path.
- unsupported forms must continue to use the existing bounded unsupported / #UD
  path where applicable.
- Rung 5 INT/IRET/#UD behavior and Rung 6 MOV behavior must remain intact.

Do not bypass architecture just to make a Rung 7 test pass.

If an apparent fix requires architectural boundary smearing, stop and surface
that explicitly.

---

## ALU and Flag-State Guardrail

ALU flag production is in scope only for the bounded Rung 7 operations:

```text
ADD
SUB
AND
OR
XOR
CMP
```

Required flag ownership:

- ALU helper may compute candidate flags for CF, OF, ZF, SF, PF, and AF.
- candidate flags may be carried in the existing `T3` / `FLAGS_FROM_T3`
  mechanism or another explicitly authorized Appendix A/B/C-consistent path.
- microcode controls when candidate flags are staged.
- commit controls when architectural EFLAGS become visible.

ALU operations must not modify IF, TF, DF, or unrelated control flags.

Logical operations must perform only architecturally required arithmetic-flag
updates. For AND/OR/XOR, CF and OF are cleared as architecturally required,
ZF/SF/PF are set from the result, and AF must follow the selected authoritative
oracle. If the exact AF behavior source is not confirmed, stop and raise it as
a Rung 7 blocker before claiming completion.

CMP computes flags as SUB but suppresses destination writeback.

Rung 7 does not authorize broad flag-instruction behavior.

---

## Register-Writeback Guardrail

Non-CMP register-destination ALU forms stage:

```text
pending GPR write
pending EFLAGS update
```

Architectural GPR and EFLAGS visibility occurs only through commit.

No early GPR or EFLAGS visibility is allowed.

CMP register-destination forms commit EFLAGS only. The destination register
must remain unchanged.

Acceptable bounded behavior:

- compute destination register index from the selected opcode or ModRM field
- compute source register index from the selected opcode or ModRM field
- load register operands through the selected metadata/service path
- compute a bounded ALU result
- stage pending GPR writeback for non-CMP register destinations
- stage pending EFLAGS update for all in-scope ALU/CMP forms
- commit GPR and EFLAGS together for non-CMP register destinations through
  the intended commit mask
- commit EFLAGS only for CMP

Bad hidden RTL behavior:

- decoder directly writes the architectural register file.
- ALU helper writes architectural state.
- load_store writes architectural state except through the accepted commit or
  memory-store model.
- commit_engine computes ALU results or decides opcode policy.
- register state or EFLAGS becomes visible before the intended commit boundary.

---

## Memory-ALU Guardrail

Non-CMP memory destinations are read-modify-write operations under microcode
sequencing.

The intended high-level sequence is:

```text
EA_CALC_*
LOAD_RM*
ALU_*
FLAGS_FROM_T3 / EFLAGS staging
STORE_RM*
ENDI with selected commit/cleanup mask
```

Memory source forms are read-only.

CMP memory forms are read-only and flags-only.

Do not let `load_store` decide ALU policy.

Do not make memory writes visible outside the intended selected memory-store
visibility model.

Reuse Rung 6 addressing and load/store support only within Rung 7 scope.

Do not use Rung 7 as permission to generalize memory instruction execution.

If memory RMW visibility or ordering cannot be reconciled with Appendix B,
Appendix D, the accepted Rung 6 memory-store model, and the live load/store/bus
architecture, stop and report.

---

## Fault-Ordering Guardrail

Rung 7 ALU phase-1 fault behavior follows Appendix D.

For ALU operations, Appendix D states:

```text
Same fault order as MOV. No additional fault sources.
Phase-1 result: ALU cannot fault in phase-1.
```

The MOV-like ordering is:

```text
1. Instruction fetch
2. FETCH_DISP*
3. EA_CALC_*
4. LOAD_RM*
5. STORE_RM*
```

The ordering is enforced by microcode sequencing.

Fault path structure may exist, but it must not create new phase-1 ALU faults.

Do not create hardware fault-priority logic for ALU.

Do not let services decide exception priority.

Do not add protected-mode exception expansion as part of Rung 7.

---

## Pipeline and Stage-Boundary Expectations

Rung 7 must preserve clear stage boundaries.

Where a signal represents a real stage handoff, preserved metadata item,
operand data, immediate payload, displacement payload, effective address, ALU
result, flags payload, pending writeback, memory store intent, commit-visible
decision, or architectural update, it must remain explicitly latched or
registered at the boundary unless controlling documents clearly define a
different behavior.

Preserve registered stage handoffs.

Preserve `SR_WAIT` as hold, not completion.

Preserve explicit handoffs for:

- fetch / decoder byte visibility
- decoder-owned ALU metadata
- operand width metadata
- source and destination register metadata
- immediate and displacement payloads
- `M_ALU_OP`
- `M_IS_CMP`
- `M_NEXT_EIP`
- effective-address metadata
- operand load data
- ALU result
- candidate flags
- pending GPR writeback
- pending EFLAGS update
- memory store intent
- commit-time architectural register publication
- commit-time architectural EFLAGS publication
- debug/testbench observability for pre-commit versus post-commit state

Do not replace clear stage handoff points with broad combinational reach-through
paths just to make the active ALU slice work.

Correctness, ownership clarity, Fmax discipline, and reviewable handoff
behavior take priority over zero-bubble execution.

---

## ALU Path Handoff Examples

The intended Rung 7 handoff model for register-register ALU forms is:

```text
fetch / predecode
  -> decoder consumes opcode/ModRM and emits ENTRY_ALU_* metadata
  -> microsequencer dispatches ENTRY_ALU_*
  -> microcode loads selected register operands
  -> ALU helper computes result and candidate flags
  -> microcode stages pending GPR writeback and EFLAGS for non-CMP
  -> commit_engine commits selected GPR/EFLAGS state at ENDI
  -> fetch/decode advance to M_NEXT_EIP
```

The intended model for register-memory ALU forms is:

```text
fetch / predecode
  -> decoder consumes opcode/ModRM/displacement and emits ENTRY_ALU_* metadata
  -> microcode sequences EA_CALC_* and LOAD_RM*
  -> ALU helper computes register destination result and candidate flags
  -> microcode stages pending GPR writeback and EFLAGS for non-CMP
  -> commit_engine commits selected GPR/EFLAGS state at ENDI
  -> fetch/decode advance to M_NEXT_EIP
```

The intended model for memory-register ALU forms is:

```text
fetch / predecode
  -> decoder consumes opcode/ModRM/displacement and emits ENTRY_ALU_* metadata
  -> microcode sequences EA_CALC_* and LOAD_RM* for the memory destination
  -> microcode loads the register source
  -> ALU helper computes memory destination result and candidate flags
  -> microcode stages EFLAGS and issues STORE_RM* for non-CMP
  -> instruction completes through ENDI discipline
  -> fetch/decode advance to M_NEXT_EIP
```

The intended model for register-immediate ALU forms is:

```text
fetch / predecode
  -> decoder consumes opcode/ModRM/immediate and emits ENTRY_ALU_* metadata
  -> microcode fetches/uses the selected immediate
  -> microcode loads destination register operand
  -> ALU helper computes result and candidate flags
  -> microcode stages pending GPR writeback and EFLAGS for non-CMP
  -> commit_engine commits selected GPR/EFLAGS state at ENDI
  -> fetch/decode advance to M_NEXT_EIP
```

The intended model for accumulator short-form ALU is:

```text
fetch / predecode
  -> decoder consumes accumulator opcode and immediate
  -> decoder emits ENTRY_ALU_RM_IMM metadata for accumulator destination
  -> microcode loads AL/AX/EAX according to width
  -> ALU helper computes result and candidate flags
  -> microcode stages accumulator writeback and EFLAGS for non-CMP
  -> commit_engine commits selected GPR/EFLAGS state at ENDI
  -> fetch/decode advance to M_NEXT_EIP
```

The intended model for CMP register forms is:

```text
fetch / predecode
  -> decoder emits CMP metadata with M_IS_CMP asserted
  -> microcode loads both operands
  -> ALU helper computes SUB-style candidate result and flags
  -> microcode stages EFLAGS only
  -> commit_engine commits EFLAGS only at ENDI
  -> destination register remains unchanged
```

The intended model for CMP memory forms is:

```text
fetch / predecode
  -> decoder emits CMP metadata with M_IS_CMP asserted
  -> microcode sequences EA_CALC_* and LOAD_RM* as needed
  -> ALU helper computes SUB-style candidate result and flags
  -> microcode stages EFLAGS only
  -> no STORE_RM* occurs for CMP
  -> destination memory remains unchanged
```

The intended model for memory-destination RMW ALU is:

```text
fetch / predecode
  -> decoder emits non-CMP memory-destination ALU metadata
  -> microcode sequences EA_CALC_* before LOAD_RM*
  -> LOAD_RM* captures the original memory operand
  -> ALU helper computes result and candidate flags
  -> microcode stages EFLAGS
  -> STORE_RM* writes the selected result through the intended memory path
  -> instruction completes through normal ENDI discipline
```

---

## Required Implementation Shape

Rung 7 implementation should be developed in small passes.

These subsections describe required ownership shape. They do not authorize
implementation by themselves.

### Decoder

Decoder must:

- classify only exact Rung 7 forms required by Appendix D and this file
- select `ENTRY_ALU_RM_R`, `ENTRY_ALU_R_RM`, or `ENTRY_ALU_RM_IMM`
- populate `M_ALU_OP`
- populate `M_IS_CMP`
- populate operand width and address-size metadata
- populate register metadata required by the selected form
- populate ModRM, SIB, immediate, displacement, and class metadata where
  required
- populate stable `M_NEXT_EIP`
- route unsupported or out-of-scope forms to the bounded unsupported/#UD path

Decoder must not:

- read registers
- access memory
- compute ALU results
- compute flags
- suppress CMP destination writes by directly changing architectural state
- commit GPR, EIP, EFLAGS, stack, segment, or memory state

### Operand and Immediate Path

Rung 7 may reuse Rung 6 fetch, immediate, displacement, addressing, and
load/store support only as required by the active ALU forms.

The operand/immediate path must:

- fetch immediate widths required by the selected ALU form
- support `83` sign-extended `imm8` where required
- preserve little-endian immediate assembly
- preserve displacement fetch behavior required for memory forms
- preserve `SR_WAIT` as a hold condition
- avoid treating temporary queue-empty behavior as architectural fault in
  phase 1

### ALU Service / Result Path

The ALU path must:

- compute bounded ADD/SUB/AND/OR/XOR/CMP results for 8/16/32-bit forms
- compute CF/OF/ZF/SF/PF/AF candidate flags according to the selected
  authoritative oracle
- mask results to the selected operand width
- return result and candidate flags through explicit handoff
- avoid instruction identity checks except for bounded operation selection
  driven by microcode/metadata
- avoid architectural state writes

### EFLAGS Staging / Commit

The EFLAGS path must:

- stage only the arithmetic flags required by Rung 7
- keep IF, TF, DF, and unrelated control flags unchanged
- use `COMMIT_EFLAGS`, `FLAGS_FROM_T3`, `STAGE_EFLAGS`, `CM_ALU_REG`,
  `CM_FLAGS`, or another explicitly confirmed Appendix A/B/C-consistent path
- make architectural EFLAGS visible only at ENDI

### Register Writeback

Register writeback must:

- stage pending GPR writeback for non-CMP register destinations
- suppress GPR writeback for CMP
- preserve byte, word, and dword merge behavior required by existing register
  file rules
- publish architectural GPR state only through commit
- preserve no-early-visibility observability in tests

### Memory RMW Path

Memory RMW must:

- use `EA_CALC_*` before memory access
- use `LOAD_RM*` to read the original memory destination
- compute the ALU result after the read completes
- use `STORE_RM*` for non-CMP memory-destination writes
- avoid `STORE_RM*` for CMP
- keep memory writes on the intended load/store/bus path
- preserve the selected memory-store visibility model

### Microsequencer and Microcode

Microsequencer and microcode must:

- dispatch `ENTRY_ALU_RM_R`
- dispatch `ENTRY_ALU_R_RM`
- dispatch `ENTRY_ALU_RM_IMM`
- sequence required services explicitly
- branch or dispatch on metadata only through Appendix C / live-builder
  supported mechanisms
- wait correctly on `SR_WAIT`
- preserve active instruction handoff until ENDI completes
- stage GPR and EFLAGS effects explicitly
- suppress CMP destination writeback through microcode-controlled staging
- return control to fetch/decode only after the active path is complete

Microcode must remain the semantic path owner.

Do not move ALU instruction sequencing into decoder, services, commit, or
microsequencer RTL.

### Commit Engine

`commit_engine` must:

- publish staged GPR writes at ENDI only when the selected commit mask requests
  GPR commit
- publish staged EFLAGS writes at ENDI only when the selected commit mask
  requests EFLAGS commit
- preserve IF, TF, DF, and unrelated flags when the EFLAGS mask excludes them
- preserve fault suppression and cleanup behavior required by prior rungs
- preserve accepted Rung 5 and Rung 6 commit behavior

`commit_engine` must not:

- classify ALU instructions
- compute ALU results
- compute flags
- decide CMP policy
- contain hidden per-opcode ALU execution semantics

### Service Dispatch

`service_dispatch` must:

- route Rung 7 service requests to the correct bounded service
- mux completion/status/results back to the microsequencer according to the
  existing service ABI
- remain routing/muxing only

`service_dispatch` must not:

- make decisions about instruction meaning
- implement ALU policy
- suppress CMP writeback
- modify state directly
- hide missing service routing behind successful completion

---

## Concerns That Must Be Raised, Not Guessed

The following Rung 7 concerns must be resolved through read-only alignment,
owner decision, frozen/source-of-truth authority, or live-source inspection
before implementation depends on them.

### Concern 1 - `FLAGS_FROM_T3` / `COMMIT_EFLAGS` Live Path

Appendix A defines `FLAGS_FROM_T3`, `COMMIT_EFLAGS`, EFLAGS pending commit
fields, `STAGE_EFLAGS`, `CM_ALU_REG`, and `CM_FLAGS`. The live implementation
path must be confirmed before Rung 7 implementation depends on it.

Do not assume a defined service or commit mask is live.

### Concern 2 - Exact Flag Formula / Oracle

The exact formula/source for CF, OF, ZF, SF, PF, and AF must be confirmed.

This is especially important for AF on logical operations and for width masking
of 8/16/32-bit results.

Do not claim Rung 7 completion without a project-owned flag oracle or explicitly
approved semantic reference.

### Concern 3 - CMP Writeback Suppression

The mechanism that suppresses destination writeback for CMP must be explicit.

`M_IS_CMP`, `ALU_CMP`, `CM_FLAGS`, or another named path must be confirmed
against Appendix A/B/C and live source.

Do not rely on an unnamed equivalent mechanism.

### Concern 4 - Memory RMW Visibility and Ordering

Non-CMP memory destinations require read-modify-write behavior.

Pass 1 must confirm whether the accepted Rung 6 memory-store visibility model
remains valid for Rung 7 RMW, and how EFLAGS commit is ordered relative to
`STORE_RM*`.

If this cannot be reconciled with Appendix B, Appendix D, and live
load_store/bus behavior, stop and report.

### Concern 5 - ALU Service Routing and MOV-Gated Load/Store

Pass 1 must confirm:

- whether an active ALU service exists
- whether `service_dispatch` routes it
- whether `load_store` is currently MOV-gated
- whether `LOAD_RM*` / `STORE_RM*` can be reused for ALU operands without
  adding instruction policy to `load_store`

Do not silently route Rung 7 services to default/no-engine behavior.

### Concern 6 - `ENTRY_ALU_*` Dispatch Mechanics

Do not invent new microinstruction forms, condition codes, or direct
branch-on-opcode-class mechanisms.

`ENTRY_ALU_*` dispatch must use only:

- microinstruction forms defined by Appendix C
- constructs representable in the live `scripts/ucode_build.py`
- field names and numerical values consistent with Appendix A

### Concern 7 - `.uasm` Versus `ucode_build.py` Dual Source

The `.uasm` files are required for source organization and review.

The current live ROM build path must be confirmed. If `scripts/ucode_build.py`
still builds ROM content directly, `.uasm` changes alone do not prove the ROM
changed.

Do not let `.uasm` and `ucode_build.py` diverge.

### Concern 8 - `M_` Versus `MF_` Naming Layers

Appendix A and Appendix C use `M_` field names in frozen microcode/source
notation.

The live codegen JSON and Python ROM builder may use `MF_` names for the same
numerical extract-field values.

Confirm the naming convention used in each layer before ENTRY_ALU work begins.

Do not mix `M_` and `MF_` conventions within the same layer.

### Concern 9 - Appendix C Pseudo-Instruction Support

Appendix C pseudo-instructions such as `WIDTH_DISPATCH` and `ADDR_DISPATCH`
are assembler concepts.

Do not assume matching Python helpers exist in `ucode_build.py`.

### Concern 10 - Generated Package Exposure

Pass 1 must confirm whether the current generated package exposes:

```text
M_ALU_OP
M_IS_CMP
FLAGS_FROM_T3
COMMIT_EFLAGS
CM_ALU_REG
CM_FLAGS
ENTRY_ALU_RM_R
ENTRY_ALU_R_RM
ENTRY_ALU_RM_IMM
ALU_ADD
ALU_OR
ALU_AND
ALU_SUB
ALU_XOR
ALU_CMP
```

If Appendix A defines a value but the generated package lacks it, treat that as
codegen synchronization until proven otherwise. Do not manually edit generated
artifacts.

### Concern 11 - First-Slice Selection

The preferred first implementation slice is a candidate only.

Simple register-register ADD/CMP or accumulator ADD/CMP may be a reasonable
first slice, depending on live-source constraints. The first slice must be
confirmed before implementation.

No partial slice is Rung 7 complete.

### Concern 12 - Test Oracle and Vector Ownership

Applicable 8086 vectors may be supplemental overlap validation.

Project-owned Keystone86 Rung 7 tests are required for acceptance. Do not
outsource the acceptance oracle entirely to external vectors.

---

## Known Implementation Gaps and Required Resolution

This section records known pre-implementation gaps that must be handled
explicitly during Rung 7. These are not completion claims.

Each item must be confirmed against live source in Pass 1 before implementation
depends on it:

- no active ALU service/routing confirmed yet
- `COMMIT_EFLAGS` / `FLAGS_FROM_T3` path not confirmed live
- `ENTRY_ALU_*.uasm` not confirmed live
- `ucode_build.py` `ENTRY_ALU_*` ROM path not confirmed live
- decoder ALU metadata not confirmed live
- load_store generalization for ALU memory operands not confirmed live
- Rung 7 Make/test targets absent
- project-owned ALU vector matrix absent
- exact flag oracle implementation not confirmed
- Rung 5 regression preservation required
- Rung 6 regression preservation required

Required resolution:

```text
Pass 1 must classify each gap as:
  - required blocker for the first authorized implementation pass
  - required blocker for a later Rung 7 pass
  - already resolved in live source
  - out of scope for Rung 7
```

If a gap appears to require a new frozen-spec field, new opcode class, new
commit ownership rule, generated-artifact manual edit, or broad architecture
redesign, stop and report.

---

## Implementation Slice Policy

Rung 7 should be implemented in small bounded passes.

The first implementation slice should be intentionally smaller than the final
gate.

Candidate first slices include:

```text
register-register ADD/CMP
accumulator ADD/CMP
```

The actual first slice must be selected only after Pass 1 confirms live-source
constraints, available metadata, service routing, microcode builder support,
flag path availability, and test oracle strategy.

The staged implementation order does not redefine the final Rung 7 gate.

Do not mistake a pass-level proof for Rung 7 completion.

Do not narrow Appendix D to make an early pass easier.

Do not widen Appendix D because z8086, ao486, review comments, stale constants,
or chat context suggest additional useful behavior.

---

## Execution-Order Summary

This summary is a bounded planning order, not implementation authorization and
not a substitute for Appendix D.

```text
Pass 1:
  Read-only live-source alignment and blocker confirmation.
  Confirm Rung 6 accepted baseline and current branch/status.
  Confirm ALU metadata, service, microcode, commit, flag, load/store, test,
  generated package, .uasm, and ucode_build.py status.
  Confirm ao486 CMD_Arith donor usage boundaries.
  Confirm first-slice candidate or report why blocked.
  Make no edits unless the session explicitly authorizes docs-only edits.

Pass 2:
  Tests/vector plan and first non-invasive test skeleton if authorized.
  Define project-owned oracle strategy for result, flags, CMP suppression,
  memory RMW, and EIP advance.

Pass 3:
  Minimal ALU service/flag helper path if authorized.
  Prove bounded result and candidate flags without architectural writeback.

Pass 4:
  Register-register ALU.
  Prove ADD/SUB/AND/OR/XOR/CMP register forms, CMP suppression, EFLAGS commit,
  and no early GPR/EFLAGS visibility.

Pass 5:
  Immediate and accumulator forms.
  Prove immediate widths, `83` sign-extension, accumulator short forms, flags,
  and EIP advance.

Pass 6:
  Memory-source and memory-destination RMW forms.
  Prove EA/load/store reuse, memory read-only CMP, memory RMW for non-CMP,
  memory visibility model, and flags.

Pass 7:
  Full Rung 7 matrix, Rung 5/Rung 6 regression, generated-artifact status,
  verification record, and owner acceptance readiness.
```

No pass claims Rung 7 completion. Only full Appendix D Rung 7 coverage with
actual passing verification may lead to a completion claim.

---

## Behavioral Contract

Rung 7 must prove the following observable behavior for required ALU forms:

- reset and initial state are known
- instruction fetch begins from the expected address
- opcode bytes are consumed
- ModRM byte is consumed where required
- immediate bytes are consumed where required
- displacement bytes are consumed where required
- `M_ALU_OP` is correct
- `M_IS_CMP` is correct
- operands are selected correctly
- operand width is correct
- immediate sign-extension for `83` forms is correct
- effective address is calculated correctly for memory forms
- memory source data is loaded correctly
- memory destination original data is loaded before RMW
- ALU result is correct
- CF is correct
- OF is correct
- ZF is correct
- SF is correct
- PF is correct
- AF is correct
- logical operation flag behavior is correct
- CMP destination remains unchanged
- non-CMP destination is updated
- non-CMP memory RMW writes correct address, byte-enable, and data
- CMP memory forms do not write memory
- architectural GPR state does not change before commit
- architectural EFLAGS state does not change before commit
- architectural GPR/EFLAGS state changes only at commit
- final EIP equals `M_NEXT_EIP`
- unsupported adjacent forms do not partially execute
- Rung 5 INT/IRET/#UD behavior remains passing
- Rung 6 MOV behavior remains passing

Rung 7 must not claim broader ISA coverage beyond the frozen ALU Operations
gate.

---

## Unsupported-Form Expectations

Adjacent arithmetic forms must not partially execute.

Unsupported or out-of-scope forms must not update GPR, EFLAGS, memory, stack,
segment state, or control flow except through bounded unsupported/#UD behavior.

Examples of unsupported or out-of-scope forms include:

```text
ADC
SBB
TEST
INC
DEC
NEG
NOT
shifts/rotates
MUL/IMUL
DIV/IDIV
XADD
CMPXCHG
bit-test families
protected-mode-only behavior
string/system/control/debug behavior
```

If unsupported-form testing reveals that an adjacent encoding falls through
into incorrect execution, fix only the bounded classification/rejection path
needed for Rung 7. Do not implement the broader instruction.

---

## Validation Expectations

Minimum validation before claiming Rung 7 complete:

```text
make codegen
make ucode
make rung5-regress
make rung6-regress
make rung7-regress
git diff --check
```

If `make rung7-regress` does not exist yet, it must be added only in a future
authorized test/implementation session and cannot be faked.

`make rung7-regress` must include or otherwise prove:

```text
make rung5-regress
make rung6-regress
Rung 7 project-owned ALU matrix tests
```

Target names may differ, but regression coverage must prove the full Appendix D
ALU Operations matrix before Rung 7 completion is claimed.

The verification record must be created only after actual runs and must include:

- exact commit under test
- working tree status before and after the run
- exact commands run
- actual pass/fail results
- testbench names
- instruction forms proven
- opcode families proven
- operand widths proven
- addressing modes proven
- immediate forms proven
- accumulator forms proven
- CMP suppression result
- memory RMW result
- CF/OF/ZF/SF/PF/AF result
- `M_ALU_OP` result
- `M_IS_CMP` result
- `M_NEXT_EIP` result
- ALU service/result path used
- EFLAGS staging/commit path used
- CMP suppression path used
- memory RMW path used
- `.uasm` / `ucode_build.py` consistency result
- `M_` / `MF_` naming-layer mapping if touched
- Appendix C pseudo-instruction support status if touched
- generated-artifact status
- semantic donor material used
- explicit non-scope
- known limitations
- confirmation that Rung 5 and Rung 6 regressions passed

A completion claim is invalid unless based on actual command results from the
committed candidate state.

---

## Testbench Expectations

Rung 7 testbenches should directly observe the frozen ALU Operations slice.

For register-register ALU, the testbench should observe:

- opcode and ModRM byte consumption
- correct source and destination register selection
- all required register combinations
- all required widths
- result correctness
- CF/OF/ZF/SF/PF/AF correctness
- staged GPR and EFLAGS updates for non-CMP
- EFLAGS-only commit for CMP
- no early architectural visibility
- final EIP equals `M_NEXT_EIP`

For register-memory ALU, the testbench should observe:

- ModRM/displacement byte consumption where applicable
- effective-address calculation
- memory read request and data capture
- register destination selection
- result and flags
- staged GPR/EFLAGS updates
- final register/EFLAGS/EIP state

For memory-register ALU, the testbench should observe:

- effective-address calculation
- memory read before ALU execution
- selected source register
- result and flags
- memory write request for non-CMP
- memory write address, byte-enable, and data for non-CMP
- no memory write for CMP
- final EFLAGS and EIP state

For register-immediate ALU, the testbench should observe:

- immediate byte consumption
- immediate assembly
- `83` sign-extended `imm8` behavior
- destination register selection
- result and flags
- CMP destination unchanged
- final EIP equals `M_NEXT_EIP`

For accumulator short forms, the testbench should observe:

- accumulator register selection for AL/AX/EAX
- immediate assembly
- result and flags
- CMP accumulator unchanged
- final EIP equals `M_NEXT_EIP`

For memory RMW, the testbench should observe:

- original memory read
- ALU result generation from original memory value
- EFLAGS staging
- memory write only for non-CMP
- selected memory-store visibility path

All Rung 7 testbenches must prove Rung 5 and Rung 6 non-regression through the
required aggregate regression commands before completion is claimed.

Testbenches must not claim broader ISA coverage than the exact Appendix D
Rung 7 forms tested.

---

## Documentation Expectations

Do not update broad docs preemptively.

Do not update README, process docs, source-of-truth docs, overview docs, or
verification docs with claims that exceed implemented and verified behavior.

Future Rung 7 verification results belong in:

- `docs/implementation/rung7_verification.md`

That file should be created or updated only after actual runs and when
authorized.

Future Rung 7 acceptance belongs in:

- `docs/implementation/rung7_acceptance.md`

That file should be created or updated only after owner acceptance and when
authorized.

Do not alter frozen specs unless a separate protected-file review explicitly
authorizes a specific change.

If any protected documentation appears stale or conflicting, stop and report
the exact issue before editing.

---

## Code Comment Expectations

Future Rung 7 code changes should be understandable to a human maintainer.

Add concise comments where behavior is non-obvious, especially around:

- ALU opcode classification
- `M_ALU_OP`
- `M_IS_CMP`
- `M_NEXT_EIP`
- immediate assembly and `83` sign extension
- ModRM interpretation
- source and destination register metadata
- effective-address reuse
- ALU result and width masking
- flag formula/source for CF/OF/ZF/SF/PF/AF
- `FLAGS_FROM_T3` or selected flag payload path
- `COMMIT_EFLAGS` or selected EFLAGS staging path
- CMP destination suppression
- memory RMW sequencing
- selected memory-store visibility path
- no early GPR/EFLAGS visibility
- service_dispatch routing for Rung 7 services
- `.uasm` / `ucode_build.py` consistency
- `M_` / `MF_` naming-layer mapping where relevant
- unsupported adjacent ALU rejection
- testbench-only observability

Comments should explain ownership and intent. They should not claim broader
architectural coverage than implemented.

Do not use comments to justify scope creep. If behavior is not required by
frozen specs or this active rung file, classify it as out of scope instead of
implementing and commenting it.

---

## Stop Conditions

Stop and report before proceeding if Rung 7 work appears to require:

- hidden ALU execution in decoder
- hidden ALU execution in microsequencer RTL
- hidden ALU execution in service_dispatch
- hidden ALU execution in commit_engine
- services becoming hidden ALU instruction engines
- flag updates outside the intended EFLAGS commit path
- GPR updates outside the intended GPR commit path
- CMP writing the destination
- CMP memory forms issuing a store
- memory RMW that cannot be reconciled with the load/store/commit model
- a new frozen-spec field, opcode class, service ID, or commit mask
- `ucode_build.py` and `.uasm` divergence
- generated artifacts manually edited
- stale constants used to widen scope
- ADC/SBB implemented because they are donor-adjacent
- TEST/INC/DEC or other Rung 8 behavior implemented as a helper side effect
- 8086 vectors treated as target architecture
- ao486 RTL, pipeline, token passing, or hazard network imported
- protected/page/descriptor/privilege behavior
- broad flags-instruction behavior
- Rung 5 regression broken
- Rung 6 regression broken
- implementation without explicit authorization
- bypassing protected-file controls, Git hooks, CI checks, branch protections,
  or repository guardrails

Do not silently expand Rung 7.

---

## Work Classification Rule

Before editing files for any Rung 7 task, classify planned work as one of:

```text
Required blocker
  Explicitly required by frozen specifications or this active rung file.

Required acceptance cleanup
  Needed so documentation, source-of-truth records, generated artifacts, or
  verification evidence accurately match actual tested behavior.

Candidate implementation path requiring confirmation
  A bounded proposed way to satisfy a required blocker, but not itself frozen
  authority. It must be confirmed against live source, frozen specs, coding
  rules, and process docs before implementation.

Out of scope
  Useful, plausible, architecturally desirable, donor-adjacent, or
  future-facing, but not explicitly required by frozen specifications or this
  active rung file.
```

Only explicitly authorized required blockers, required acceptance cleanup, and
confirmed candidate implementation paths may be implemented.

Out-of-scope work must not be implemented as part of Rung 7.

Known implementation gaps listed in this file are required blockers, stop
conditions, required design decisions, or candidate implementation paths until
the live branch proves otherwise.

---

## What This Rung Is Not

Rung 7 is not:

- a general arithmetic framework
- ADC/SBB unless a future active rung includes them
- TEST/INC/DEC/NEG/NOT
- a shifts/rotates rung
- a multiply/divide rung
- a flags-instruction rung
- a protected-mode rung
- a page/descriptor/privilege rung
- an ao486 RTL import
- an ao486 pipeline import
- a z8086 clone
- an 8086-vector compliance-only pass
- a cleanup rung
- a performance or IPC optimization rung
- a future-rung preparation pass
- permission to move instruction semantics into RTL
- permission to bypass documented stage handoff or bubble behavior for speed
- permission to invent microcode syntax, service routing, commit behavior,
  codegen fields, ROM build behavior, microsequencer instruction-policy
  behavior, or unnamed alternative staging mechanisms

Rung 7 exists to prove the bounded Appendix D ALU Operations slice cleanly:
decode, operand fetch, microcode sequencing, ALU result, flag generation, CMP
writeback suppression, GPR/memory writeback, EIP advance, Rung 5 preservation,
and Rung 6 preservation through the existing staged microcoded architecture.

---

## Handoff Rule for This Rung

Any future handoff for Rung 7 must report:

- current branch
- current commit
- working tree status
- files changed
- protected files changed, if explicitly authorized
- exact instruction forms implemented
- exact instruction forms tested
- exact Rung 7 coverage remaining
- exact commands run
- actual pass/fail results
- generated-artifact status
- verification-document status
- donor material used
- test/vector status
- project-owned oracle status
- ALU service path
- EFLAGS staging/commit path
- CMP suppression path
- memory RMW path
- `ENTRY_ALU_*` dispatch mechanism
- service_dispatch routing status
- load_store reuse/generalization status
- `.uasm` / `ucode_build.py` consistency status
- `M_` / `MF_` mapping if touched
- Appendix C pseudo-instruction support status if touched
- generated package exposure for `M_ALU_OP`, `M_IS_CMP`,
  `FLAGS_FROM_T3`, `COMMIT_EFLAGS`, and `CM_ALU_REG`
- candidate implementation paths confirmed, rejected, or still requiring
  owner decision
- known limitations
- work classification decisions
- Rung 5 regression status
- Rung 6 regression status
- explicit statement that no Rung 7 completion is claimed unless full
  verification has actually passed

Do not claim Rung 7 completion without committed implementation, passing full
Appendix D ALU Operations verification, generated-artifact status,
stage-handoff/bubble-model status, known-gap resolution status, working-tree
status, and an actual `docs/implementation/rung7_verification.md` record.

---

## Summary

Rung 7 is the bounded ao486-donor ALU Operations rung.

The active operation slice is:

```text
ADD
SUB
AND
OR
XOR
CMP
```

The active form slice is:

```text
reg/reg
reg/mem
mem/reg
reg/imm
accumulator short forms
```

Rung 7 must prove result correctness, CF/OF/ZF/SF/PF/AF correctness, CMP
destination suppression, non-CMP GPR/memory writeback, memory RMW behavior,
`M_NEXT_EIP` / EIP advance, Rung 5 preservation, and Rung 6 preservation.

`third_party/ao486_notes/commands/CMD_Arith.txt` is the primary semantic donor
corpus. It must be mapped into Keystone86 metadata, microcode, services,
staging, commit, and project-owned tests. It must not be imported as RTL,
pipeline, token passing, hazard logic, or broad arithmetic-family behavior.

z8086/8086 material is supplemental overlap context only. It does not widen or
narrow the active rung.

Keep Rung 7 bounded. Keep it staged. Keep instruction meaning in microcode.
Keep RTL as bounded reusable mechanisms. Preserve registered handoffs. Treat
`SR_WAIT` as a real hold. Publish architectural GPR and EFLAGS state only
through commit. Keep memory effects on the intended load/store path. Preserve
Appendix D MOV-like fault ordering. Prove the behavior with project-owned tests
and actual regressions before claiming completion.
