# Keystone86 / Aegis — Rung 6 Bring-Up Scope

## Purpose

Rung 6 is the frozen-spec MOV bring-up rung after the accepted Rung 5 interrupt, IRET, and real-mode fault-delivery baseline.

Rung 6 proves that the required MOV instruction set can move end-to-end through the intended Keystone86 staged microcoded architecture:

1. `decoder` recognizes the frozen in-scope MOV forms and emits decode-owned metadata.
2. instruction bytes, immediates, displacements, ModRM, register fields, width information, addressing metadata, and `M_NEXT_EIP` are consumed and produced in a bounded, observable way.
3. `microsequencer` executes explicit `ENTRY_MOV` microcode.
4. microcode owns instruction meaning, sequencing, service ordering, fault ordering, staging intent, and commit intent.
5. helper services perform bounded operand, effective-address, load/store, register metadata, and writeback preparation.
6. architectural register effects become visible only through the intended commit boundary.
7. memory effects occur only through the intended load/store and bus path under microcode sequencing.
8. MOV does not update FLAGS.
9. prior Rung 0 through Rung 5 behavior remains intact.

Rung 6 is intentionally bounded to the frozen MOV rung. It is not an ALU rung, a flags-production rung, a protected-mode rung, a generalized exception rung, a segment-register MOV rung, a string-MOV rung, or a future-rung preparation pass.

Rung 6 must preserve the implementation discipline established by earlier rungs:

- Rung 3 established service-oriented stack/control-transfer sequencing and commit ownership.
- Rung 4 established bounded semantic-helper discipline.
- Rung 5 established real-mode INT / IRET / #UD delivery through explicit microcode sequencing, bounded services, registered handoffs, allowed bubbles/holds, and commit-visible architectural effects.
- Rung 6 must apply the same ownership discipline to MOV register, memory, immediate, effective-address, register-file, load/store, and EFLAGS-preservation behavior required by the frozen bring-up ladder.

The intended Rung 6 implementation style is microcode-dominant:

- microcode owns instruction sequencing and instruction meaning.
- RTL provides bounded reusable mechanisms and services.
- RTL must not become hidden per-instruction execution logic.
- commit remains the architectural visibility boundary for register-visible architectural state.
- load/store remains the memory access path for MOV memory effects.
- services remain leaf mechanisms under microcode control.
- microsequencer executes generic Appendix C microinstructions and must not become a hidden MOV executor.
- stage handoffs remain registered or explicitly latched, bubble-capable, and hold-stable while acceptance is pending.

---

## Rung 6 intent

Rung 6 is the frozen-spec MOV bring-up rung.

The final Rung 6 acceptance scope is the MOV scope defined by:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

That final scope includes MOV decode for:

```text
88 /r
89 /r
8A /r
8B /r
C6 /0
C7 /0
B0-BF
```

It also includes the MOV-related support required by Appendix D:

```text
ENTRY_MOV with correct M_OPCODE_CLASS
FETCH_IMM* variants required by MOV
FETCH_DISP* variants required by MOV
EA_CALC_16
EA_CALC_32
LOAD_RM8/16/32
STORE_RM8/16/32
LOAD_REG_META
STORE_REG_META
full 8-register architectural register file
complete ENTRY_MOV microcode
```

Required verification is the full MOV matrix from Appendix D:

```text
MOV reg, reg: all 8 register combinations, all 3 widths
MOV reg, imm: all registers, all widths
MOV reg, [mem]: memory read, all widths, all Appendix D-required addressing modes
MOV [mem], reg: memory write, all widths, all Appendix D-required addressing modes
MOV [mem], imm: immediate to memory
Flags: verify EFLAGS unchanged by MOV
```

The Rung 6 gate criterion is:

```text
Full MOV test matrix passes against reference model.
```

Implementation may proceed in smaller bounded passes. The preferred first implementation slice is:

```text
B8+rd id      MOV r32, imm32
```

This first slice is a suggested implementation starting point, not a frozen-spec replacement for the final Rung 6 gate.

That first slice is useful because it proves destination-register selection, immediate capture, pending register writeback, and commit-time architectural visibility before memory operands, effective addressing, displacement handling, and the full MOV matrix are added.

No partial implementation slice is Rung 6 complete.

Rung 6 is complete only when the frozen Appendix D MOV gate is implemented, verified, documented from actual runs, semantically aligned against the approved donor corpus or explicitly approved replacement reference, and explicitly accepted.

---

## Required reading and precedence

Before making any Rung 6 implementation change, read these files in the order required by repository authority and rung workflow:

1. `AGENTS.md`
2. `docs/spec/frozen/README.md`
3. `docs/spec/frozen/STATUS.md`
4. `docs/spec/frozen/IMPORT_MANIFEST.md`
5. `docs/spec/frozen/master_design_statement.md`
6. `docs/spec/frozen/appendix_a_field_dictionary.md`
7. `docs/spec/frozen/appendix_b_ownership_matrix.md`
8. `docs/spec/frozen/appendix_c_assembler_spec.md`
9. `docs/spec/frozen/appendix_d_bringup_ladder.md`
10. `docs/spec/frozen/verification_plan.md`
11. `docs/implementation/bringup/rung6.md`
12. `docs/implementation/coding_rules/source_of_truth.md`
13. `docs/implementation/coding_rules/review_checklist.md`
14. `docs/implementation/coding_rules/codegen_workflow.md`
15. `docs/implementation/coding_rules/namespace_sync.md`
16. `docs/process/codex_workflow.md`
17. `docs/process/developer_directive.md`
18. `docs/process/rung_execution_and_acceptance.md`
19. `docs/process/tooling_and_observability_policy.md`
20. `docs/process/dev_environment.md`
21. `docs/implementation/rung5_acceptance.md`
22. `docs/implementation/rung5_verification.md`
23. relevant design-support notes under `docs/spec/design/`, especially:
    - `docs/spec/design/front_end_stage_contracts.md`
    - `docs/spec/design/decoder_stage_design.md`
    - `docs/spec/design/microsequencer_stage_design.md`
    - `docs/spec/design/commit_stage_design.md`
    - `docs/spec/design/fetch_stage_design.md`
    - `docs/spec/design/front_end_payloads.md`
24. the specific RTL, microcode, script, Makefile, and testbench files to be changed.

Precedence on conflict:

1. frozen specs under `docs/spec/frozen/`
2. `AGENTS.md`
3. active rung file: `docs/implementation/bringup/rung6.md`
4. source-of-truth and coding-rule documents
5. process and acceptance documents
6. verification records
7. user task prompt
8. reviewer comments, correction briefs, prior chat context, implementation notes, and summaries

This file is a bounded bring-up scope note. It does not replace the documents above it.

If this file conflicts with the frozen Appendix D Rung 6 gate, Appendix D wins.

Do not infer intent from prior conversations, summaries, analogies, external project knowledge, or agent memory when a frozen or process authority document answers the question.

---

## Authority and usage

This is a bring-up scope document.

It is:

- a bounded implementation-intent note for Rung 6
- subordinate to the required reading chain above
- the baseline alignment document for Rung 6 implementation and review
- a guardrail against hidden RTL instruction execution
- a guardrail against broad unreviewed MOV expansion
- a guardrail against narrowing the frozen Appendix D MOV gate
- a guardrail against premature ALU work
- a guardrail against flags-production drift
- a guardrail against protected-mode drift
- a guardrail against future-rung preparation hidden inside MOV support
- a guardrail against inferred design intent or undocumented donor interpretation
- a guardrail against turning missing microinstruction support into hidden MOV RTL behavior

It is not:

- the final verification record
- the final acceptance record
- the sole authority for implementation
- permission to narrow the frozen Rung 6 gate
- permission to widen scope beyond Appendix D
- permission to alter frozen specifications
- permission to redesign the decode, service, microcode, commit, register-file, memory, or exception architecture
- permission to implement Rung 7 or later behavior
- a file-by-file patch list for the current repository state
- a replacement for the z8086 / ao486 usage limits stated in frozen specs
- permission to use inferred intent as design authority
- permission to treat known implementation gaps as optional

Verification results do not belong in this file. Record actual run results in:

- `docs/implementation/rung6_verification.md`

Acceptance does not belong in this file. Record explicit project-owner acceptance separately in:

- `docs/implementation/rung6_acceptance.md`

Known implementation gaps may be listed here only as bounded blockers, candidate resolution paths, and required design-decision checkpoints. They must not be recorded as completed until verified by actual implementation and test results.

Where this file includes candidate implementation paths derived from review, those paths are not frozen-spec authority. They must be confirmed in Pass 1 against the live repo, frozen specs, coding rules, and process documents before implementation.

---

## Protected-file rule

This file is a protected authority file under `AGENTS.md`.

Do not edit, rewrite, rename, delete, move, reformat, or commit changes to this file unless the user explicitly authorizes this exact file and exact intended change.

The same protected-file rule applies to:

```text
docs/spec/frozen/**
docs/implementation/coding_rules/**
docs/process/**
docs/implementation/bringup/rung*.md
AGENTS.md
```

If a protected file appears to need changes during Rung 6 implementation, stop and report:

1. the protected file path
2. the exact change that appears necessary
3. why the change appears necessary
4. whether the issue is a conflict, typo, stale acceptance record, scope question, generated-source synchronization issue, or live-source implementation blocker

Do not bypass protected-file checks, Git hooks, CI checks, branch protections, or repository guardrails.

---

## Exact scope source

For exact rung gate criteria and the frozen bring-up ladder, use:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

This file describes intent, pass structure, known blockers, candidate resolutions, required decision points, and boundaries for Rung 6 implementation. It does not replace Appendix D.

This file must not be used to infer additional instruction coverage beyond what Appendix D and this file explicitly assign to Rung 6.

This file must also not be used to reduce the final Rung 6 acceptance scope below the frozen Appendix D MOV gate.

---

## z8086 and ao486 usage rule

The two frozen-spec project inspirations are:

```text
z8086 = structural template / architectural inspiration
ao486 = semantic corpus / instruction-behavior donor
```

Use both only as the frozen specifications define them.

### z8086 structural-template rule

Use `z8086` only as described by:

- `docs/spec/frozen/master_design_statement.md`

`z8086` may guide the clean bounded microcoded machine structure:

```text
compact microcoded architecture
microsequencer as the center of the machine
decoder as classifier
translate / dispatch table pattern
entry ID plus sequence-counter style control
move-to-action microinstruction loop concept
stall/wait mechanism under microcode control
single clock domain discipline
no vendor primitive dependence
small clean machine philosophy
large ISA surface through ROM sequencing rather than hardware explosion
```

Do not copy `z8086` blindly as an implementation source.

Do not use `z8086` to widen or narrow the active rung scope.

Do not import `z8086` behavior unless the frozen specs or active rung file explicitly require that behavior.

Do not treat `z8086` as a replacement for Keystone86 frozen ownership rules.

### ao486 semantic-corpus rule

Use `ao486` only as described by:

- `docs/spec/frozen/master_design_statement.md`

`ao486` is the semantic donor for x86/486 instruction meaning, not the structural architecture to import.

Allowed `ao486` donor use:

```text
ao486 CMD_*.txt <decode>
  -> Keystone86 dispatch metadata fields and ENTRY_* selection

ao486 CMD_*.txt <microcode>
  -> Keystone86 explicit microcode routine labels and step structure

ao486 CMD_*.txt <read>
  -> Keystone86 service calls such as FETCH_*, FETCH_DISP_*, EA_CALC_*, LOAD_RM*, LOAD_REG_META, with WAIT returns

ao486 CMD_*.txt <execute>
  -> Keystone86 semantic checks, service selection, fault staging, and operation intent where required

ao486 CMD_*.txt <write>
  -> Keystone86 STAGE / commit intent, STORE_REG_META, STORE_RM*, COMMIT_GPR, COMMIT_EIP, COMMIT_EFLAGS where required, and ENDI

ao486 common_*.txt
  -> Keystone86 shared service-library behavior only where bounded by Appendix D
```

Forbidden `ao486` donor use:

```text
Do not import ao486's 4-stage pipeline as the architectural center.
Do not preserve ao486's read/execute/write split as the Keystone86 programming model.
Do not import ao486 AutogenGenerator-style distributed combinational control.
Do not import ao486 pipeline reset/interlock structure.
Do not import ao486 mc_cmd token passing as Keystone86 architecture.
Do not import ao486 rd_mutex_busy hazard inference network.
Do not import ao486 Verilog RTL.
Do not move instruction policy into decoder, services, or commit_engine.
Do not copy broad ao486 behavior beyond the frozen Rung 6 MOV gate.
Do not use ao486 as permission to implement future-rung behavior.
```

If the actual approved ao486 `CMD_MOV*.txt` / `common_*.txt` donor material is not present in the repository or provided in the task context, stop before claiming final MOV semantic alignment or Rung 6 completion.

Early bounded implementation slices may proceed only as provisional Appendix D-aligned work and must record donor material as unavailable if the approved donor corpus is not present.

Do not infer semantic alignment from Appendix D alone.

Do not infer additional architectural rules from either `z8086` or `ao486`.

---

## Microcode-dominant implementation rule

Rung 6 is expected to be microcode-dominant.

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

Acceptable Rung 6 RTL:

```text
decoder classification and MOV metadata capture
fetch immediate/displacement service support
EA_CALC_16 / EA_CALC_32 service support
LOAD_RM8/16/32 and STORE_RM8/16/32 service support
LOAD_REG_META and STORE_REG_META service support
architectural register-file storage required by MOV
commit support required to publish staged register writes
memory-store visibility support required by MOV memory-destination forms
generic Appendix C microinstruction support required by Rung 6
testbench observability needed to prove boundaries
```

Unacceptable Rung 6 RTL:

```text
hidden per-opcode MOV execution in decoder
hidden per-opcode MOV execution in service_dispatch
hidden per-opcode MOV execution in microsequencer
hidden instruction policy in ea_calc
hidden instruction policy in load_store
hidden instruction policy in commit_engine
broad instruction-specific RTL that bypasses microcode
a service that internally sequences multiple x86 instruction steps without microcode control
a service that checks instruction identity to decide policy
a decoder that computes operand values or reads registers
a microsequencer that implements MOV semantics directly instead of executing generic microinstructions
any module writing architectural GPR/EIP/EFLAGS/segment state except through the commit path
partial commits visible before ENDI
memory writes escaping the intended load/store/bus path
future-rung data-movement or ALU behavior hidden inside MOV support
```

Rung 5 is the local implementation pattern to preserve:

```text
microcode explicitly sequenced INT / IRET / #UD
RTL services provided bounded helper behavior
commit_engine published architectural effects only at the intended boundary
registered stage handoffs were preserved
bubbles and holds were allowed where required
```

Rung 6 should follow the same pattern for MOV.

---

## In scope

The final Rung 6 scope is the full MOV scope required by:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

Required decode coverage:

```text
88 /r         MOV r/m8, r8
89 /r         MOV r/m16/r/m32, r16/r32
8A /r         MOV r8, r/m8
8B /r         MOV r16/r32, r/m16/r/m32
C6 /0         MOV r/m8, imm8
C7 /0         MOV r/m16/r/m32, imm16/imm32
B0-B7         MOV r8, imm8
B8-BF         MOV r16/r32, imm16/imm32
```

Required build and implementation coverage:

```text
ENTRY_MOV with correct M_OPCODE_CLASS
FETCH_IMM* variants required by MOV
FETCH_DISP* variants required by MOV
EA_CALC_16
EA_CALC_32
LOAD_RM8/16/32
STORE_RM8/16/32
LOAD_REG_META
STORE_REG_META
full 8-register architectural register file
complete ENTRY_MOV microcode
```

Required verification coverage:

```text
MOV reg, reg: all 8 register combinations, all 3 widths
MOV reg, imm: all registers, all widths
MOV reg, [mem]: memory read, all widths, all Appendix D-required addressing modes
MOV [mem], reg: memory write, all widths, all Appendix D-required addressing modes
MOV [mem], imm: immediate to memory
EFLAGS unchanged by MOV
```

Rung 6 includes only the narrowly scoped support genuinely required to make the frozen MOV slice function correctly end to end:

- decode recognition for the required MOV forms
- bounded opcode, ModRM, immediate, and displacement handling
- decode-owned MOV metadata, byte-consumption facts, operand/address-size facts required by Rung 6, and `M_NEXT_EIP`
- destination register metadata capture
- source register metadata capture
- register/memory operand metadata capture
- immediate assembly
- displacement assembly
- effective-address calculation required by MOV memory operands
- register metadata load/store support
- memory load/store support required by MOV
- pending GPR writeback staging
- architectural register-file update through the intended commit boundary
- memory write behavior required by MOV memory destination forms
- EFLAGS unchanged behavior
- phase-1 MOV fault-path structure required by Appendix D, with no phase-1 MOV faults taken
- generic Appendix C microinstruction support required to execute Rung 6 `ENTRY_MOV`
- observability required by Rung 6 testbenches
- Make targets required to run the Rung 6 proof
- regression wiring proving Rung 5 remains passing

Implementation must still be staged. Earlier passes may prove smaller slices, but those slices are not Rung 6 completion.

---

## Concerns that must be raised, not guessed

The following concerns are explicitly called out because they are places where an implementer could otherwise infer or invent design intent. These must be resolved through Pass 1 confirmation, owner decision, or frozen/source-of-truth authority before implementation depends on them.

### Concern 1 — Memory-destination MOV visibility is not fully settled by analogy

```text
Do not assume STORE_RM* may make a memory write architecturally visible before ENDI merely because earlier rungs had service-side effects.

Whether a memory write completed before ENDI constitutes a prohibited partial commit under Appendix B anti-drift rules is ambiguous unless the frozen specs, source-of-truth documents, or accepted implementation pattern explicitly settle it.

Pass 1 must resolve this against:
  - Appendix B ownership language
  - Appendix D phase-1 MOV fault model
  - current commit_engine behavior
  - current load_store/bus path
  - Rung 5 implementation facts, without overextending analogy
```

If this cannot be resolved without adding a new architectural ownership rule, new frozen-spec field, or broad commit redesign, stop and report.

### Concern 2 — ENTRY_MOV dispatch mechanics must distinguish frozen syntax from the live ROM builder

```text
Do not invent new microinstruction forms.
Do not invent new condition codes.
Do not assume there is a direct branch-on-opcode-class condition unless the frozen Appendix C syntax and the live Python ROM builder both support the required mechanism.

Appendix C is the frozen specification authority for microinstruction syntax and pseudo-instruction concepts.
scripts/ucode_build.py is the current live ROM builder.
They are not the same tool.

ENTRY_MOV dispatch must use only:
  - microinstruction forms defined by docs/spec/frozen/appendix_c_assembler_spec.md
  - constructs already representable in scripts/ucode_build.py
  - field names and numerical values consistent with Appendix A
```

If ENTRY_MOV needs opcode-class dispatch and the existing Appendix C / `ucode_build.py` combination lacks a legal way to compare extracted metadata, stop and report before extending either Appendix C or `ucode_build.py`.

Do not write ROM encoding in Python that has no Appendix C counterpart.

Do not write `.uasm` source that the current build path cannot represent without a documented implementation gap.

### Concern 3 — Service routing ownership must be confirmed

```text
Do not silently split LOAD_RM behavior across operand_engine and load_store.
Do not silently leave MOV-required services routed to a default/no-engine path.
Do not expand operand_engine from an earlier bounded role into full MOV load/store behavior unless the authority chain supports that change.

Pass 1 must inspect service_dispatch, operand_engine, load_store, and the service ABI together.
```

The routing decision must be documented before implementing Pass 5 or Pass 6 service-dependent behavior.

### Concern 4 — FETCH_IMM16 and FETCH_IMM32 are required early

```text
MOV r32, imm32 cannot be proven without FETCH_IMM32.
MOV r16, imm16 and C7 immediate-to-memory cannot be proven without FETCH_IMM16.
Do not treat immediate fetch expansion as a later optional cleanup.
```

Pass 3 cannot claim the first MOV execution proof unless the required immediate-fetch service is implemented and routed.

### Concern 5 — Codegen synchronization must not become field invention

```text
Only emit fields and opcode classes already defined by frozen Appendix A.
Do not add helpful future opcode classes.
Do not add new metadata fields because implementation feels easier.
Do not manually patch generated package artifacts.

If the frozen Appendix A markdown lacks a field or enum that appears necessary, stop and report under the protected-file rule.
```

### Concern 6 — `.uasm` source and `ucode_build.py` live ROM encoding must not be confused

```text
The .uasm files are required for source organization, review, and future-assembler alignment.
The current live ROM build path is scripts/ucode_build.py.
The Python builder does not currently parse .uasm files.

Do not treat .uasm changes alone as proof that the generated ROM changed.
Do not treat a Python-only ROM update as sufficient source documentation.
Do not assume Appendix C pseudo-instructions are implemented as Python helpers.
```

Pass 1 and every microcode implementation pass must keep `.uasm` source and `ucode_build.py` ROM encoding synchronized unless the repository’s source-of-truth documents explicitly say the live build path changed.

### Concern 7 — Appendix C example addresses must not be treated as literal live ROM addresses

```text
Appendix C examples may contain illustrative uPC addresses.
The actual ENTRY_MOV dispatch address must be confirmed from scripts/ucode_build.py and the current generated ROM layout.

Do not assign ENTRY_MOV addresses from Appendix C examples unless the live builder confirms those addresses.
```

If Appendix C example addresses and the live `ucode_build.py` dispatch table disagree, the live builder determines current implementation behavior while Appendix C remains syntax/source-structure authority.

### Concern 8 — `M_` and `MF_` extract-field naming belong to different layers

```text
Appendix A and Appendix C use M_ field names in frozen microcode/source notation.
The current codegen JSON and Python ROM builder may use MF_ names for the same numerical extract-field values.

Do not mix M_ and MF_ conventions within the same layer.
Do not create duplicate constants with inconsistent values.
Pass 1 must document the naming convention used in each layer before ENTRY_MOV work begins.
```

### Concern 9 — Microsequencer gaps must not become hidden MOV execution

```text
Do not solve missing microinstruction support by moving MOV instruction semantics into microsequencer.sv.

The correct ownership boundary is:

  microcode decides the MOV sequence
  microsequencer executes generic Appendix C microinstructions
  services perform bounded mechanisms
  commit publishes architectural register-visible state

If Rung 6 requires EXTRACT, LOADI, condition evaluation, MOV register-to-register micro-ops, or STAGE_GPR support, those additions must implement generic Appendix C microinstruction behavior required by Rung 6.

They must not become opcode-specific MOV execution hidden in RTL.
```

Pass 1 must classify each missing microsequencer feature as:

```text
required blocker for Pass 2
required blocker for a later Rung 6 pass
already resolved in live source
out of scope for Rung 6
```

If the only way to make `ENTRY_MOV` work is to add x86-specific MOV policy into `microsequencer.sv`, stop and report.

### Concern 10 — Do not authorize unnamed alternatives through vague “equivalent” language

```text
Do not use the phrase “equivalent” to authorize an unnamed mechanism.

Any alternative to STAGE_GPR or UOP_MOV must be named, tied to Appendix A, Appendix B, Appendix C, or an existing live service path, and confirmed in Pass 1 before implementation.

The known competing mechanisms are:
  - STAGE_GPR microinstruction support
  - STORE_REG_META service-based staging
  - generic UOP_MOV register-to-register microinstruction support
  - a service-based register-transfer path confirmed by Pass 1 to be consistent with Appendix A, Appendix B, Appendix C, and the live architecture

Do not invent a third mechanism without owner review and authority-chain support.
```

---

## Known implementation gaps and required resolution

This section records known pre-implementation gaps that must be handled explicitly during Rung 6. These are not completion claims. They are required blockers, stop conditions, candidate implementation paths, or required design decisions that must be confirmed in Pass 1 and resolved in bounded passes before Rung 6 completion can be claimed.

Where this section names a concrete resolution path, that path is a bounded proposal derived from repository review. It must be checked against the live repository, frozen specs, and process docs before implementation. If the live repository contradicts the proposed path, stop and report.

### Gap 1 — ao486 MOV donor material absent or unconfirmed

Known risk:

```text
third_party/ao486_notes/ may contain no approved CMD_MOV*.txt or common_*.txt donor material.
```

Required resolution:

```text
Pass 1 must record donor material as present or unavailable.

If donor material remains unavailable:
  - early bounded implementation slices may proceed only as provisional Appendix D-aligned work
  - final MOV semantic alignment may not be claimed
  - Rung 6 completion may not be claimed

Before final Rung 6 completion:
  - approved ao486 MOV donor material must be provided and checked, or
  - an explicitly approved replacement semantic reference must be named and accepted
```

The donor manifest, when provided, should record:

```text
source repository or archive
exact commit or immutable snapshot identifier
capture date
files included
why each file is included
usage limit: semantic donor only, not RTL/pipeline import
```

Do not infer final semantic alignment from Appendix D alone.

### Gap 2 — architectural GPR register file incomplete or placeholder

Known risk:

```text
A full 8-register architectural register file is required by Appendix D.
The implementation must confirm whether rtl/core/reg_file.sv or the active register-file location is currently a placeholder or incomplete.
The implementation must confirm whether commit_engine applies CM_GPR / CM_MOV_REG to architectural GPR storage.
```

Required resolution:

```text
Implement the smallest full architectural GPR mechanism required by Appendix D MOV.

Required behavior:
  - 8 architectural GPRs
  - 8/16/32-bit read/write behavior required by MOV
  - byte-register behavior for B0-B7 / 88 / 8A forms
  - register metadata read path for LOAD_REG_META
  - register write staging path for STORE_REG_META / CM_MOV_REG
  - commit-only architectural visibility for register-destination MOV
  - debug/testbench visibility sufficient to prove pre-commit and post-commit state
```

Candidate implementation path, requiring Pass 1 confirmation:

```text
If current source already has pc_gpr_en / pc_gpr_idx / pc_gpr_val or equivalent pending-GPR signals,
wire those into the ENDI / CM_GPR application path instead of inventing a parallel commit path.

If no width field exists for pending GPR writes, stop and identify the smallest Appendix D-consistent way to carry byte/word/dword write width.
```

Guardrails:

```text
The register file must not execute MOV semantics.
The register file must not decode instructions.
The register file must not bypass commit visibility.
Only the commit-owned path may publish architectural GPR writes.
The register file must not add future-rung behavior beyond Appendix D MOV requirements.
```

Pass impact:

```text
Required for GPR writeback passes.
Required before Rung 6 completion.
```

### Gap 3 — `EA_CALC_16` / `EA_CALC_32` service missing or placeholder

Known risk:

```text
EA_CALC_16 and EA_CALC_32 are required by Appendix D for memory MOV.
The implementation must confirm whether rtl/core/services/ea_calc.sv is placeholder, incomplete, or already active.
```

Required resolution:

```text
Implement bounded effective-address services required by Appendix D MOV.

Required behavior:
  - EA_CALC_16
  - EA_CALC_32
  - ModRM addressing support required by Appendix D MOV
  - displacement input support
  - effective-address output staging
  - SR_WAIT / explicit completion behavior
  - no protected-mode segment semantics
  - no future-rung addressing expansion
```

Candidate implementation path, requiring Pass 1 confirmation:

```text
EA_CALC_16 computes 16-bit effective offsets required by MOV.
EA_CALC_32 computes 32-bit effective offsets required by MOV.
The service receives already-latched metadata and displacement operands.
The service returns an effective offset through the established service-result path.
Segment-base addition is not added in Rung 6 unless the frozen specs already require it.
```

Guardrails:

```text
ea_calc must compute effective addresses only.
ea_calc must not know which instruction is executing.
ea_calc must not perform memory access.
ea_calc must not decide exception priority.
ea_calc must not implement protected-mode descriptor or privilege behavior.
```

Pass impact:

```text
Required for memory-source and memory-destination MOV.
Required before full Rung 6 completion.
```

### Gap 4 — `LOAD_RM*` / `STORE_RM*` / register metadata services missing or placeholder

Known risk:

```text
LOAD_RM8/16/32, STORE_RM8/16/32, LOAD_REG_META, and STORE_REG_META are required by Appendix D.
The implementation must confirm whether rtl/core/services/load_store.sv is placeholder, incomplete, or already active.
```

Required resolution:

```text
Implement bounded load/store and register metadata services required by Appendix D MOV.

Required service coverage:
  - LOAD_RM8
  - LOAD_RM16
  - LOAD_RM32
  - STORE_RM8
  - STORE_RM16
  - STORE_RM32
  - LOAD_REG_META
  - STORE_REG_META
```

Required behavior:

```text
handle register-form operands required by MOV
handle memory-form operands required by MOV through the intended memory/bus path
return explicit completion or SR_WAIT
preserve stage-boundary handoff rules
provide sufficient observability for Rung 6 tests
```

Candidate implementation path, requiring Pass 1 confirmation:

```text
Register-form LOAD_REG_META reads a GPR by metadata-selected index and width.
Register-form STORE_REG_META stages a pending GPR write for commit at ENDI.
Memory-form LOAD_RM* reads through the intended memory/bus path and waits with SR_WAIT until complete.
Memory-form STORE_RM* writes through the intended memory/bus path and waits with SR_WAIT until complete.
```

Guardrails:

```text
load_store must not execute MOV policy.
load_store must not decode instructions.
load_store must not decide exception priority.
load_store must not update architectural GPR state directly outside commit.
load_store must not implement ALU-memory or future-rung memory behavior.
```

Pass impact:

```text
Register-form portions are required for register-register MOV.
Memory portions are required for memory-source and memory-destination MOV.
All required portions are needed before full Rung 6 completion.
```

### Gap 5 — Rung 6 Makefile targets absent or incomplete

Known risk:

```text
The active Makefile may not yet contain rung6-* targets.
```

Required resolution:

Add Rung 6 targets as their corresponding testbenches land:

```text
rung6-pass3-sim
rung6-mov-reg-imm-sim
rung6-mov-reg-reg-sim
rung6-mov-reg-mem-sim
rung6-mov-mem-reg-sim
rung6-mov-mem-imm-sim
rung6-flags-unchanged-sim
rung6-regress
```

`rung6-regress` must include or invoke:

```text
make rung5-regress
make rung6-mov-reg-reg-sim
make rung6-mov-reg-imm-sim
make rung6-mov-reg-mem-sim
make rung6-mov-mem-reg-sim
make rung6-mov-mem-imm-sim
make rung6-flags-unchanged-sim
```

Candidate implementation path, requiring Pass 1 confirmation:

```text
Add each target only when the corresponding testbench exists and is expected to pass.
Do not add aggregate rung6-regress until all required subtargets exist, or mark it clearly blocked and non-passing.
Mirror the existing Rung 5 Makefile pattern where applicable.
```

Guardrails:

```text
Do not add fake passing targets.
Do not mark unimplemented tests as successful.
Do not claim aggregate Rung 6 regression until all required subtargets exist and pass.
```

### Gap 6 — MOV opcode class and register metadata constants may be missing from generated package

Known risk:

```text
ENTRY_MOV and CM_MOV_REG may already exist.
OC_MOV_RM_R, OC_MOV_R_RM, OC_MOV_R_IMM, OC_MOV_RM_IMM, M_REG_DST, M_REG_SRC, and M_REG_RM may be absent from generated RTL/package artifacts.
```

Required resolution:

```text
Do not manually edit generated package artifacts.

First inspect:
  - docs/spec/frozen/appendix_a_field_dictionary.md
  - Appendix A codegen source, such as appendix_a_codegen.json or the current equivalent
  - tools/spec_codegen/gen_from_appendix_a.py or current generator equivalent
  - generated package output
  - codegen workflow docs

If Appendix A already defines the fields/enums:
  - treat the issue as codegen source / generated-artifact synchronization
  - update the appropriate codegen source if permitted
  - update the generator if required
  - run make codegen
  - inspect generated diffs
  - run git diff --check

If Appendix A does not define the fields/enums:
  - stop before editing frozen specs
  - report the exact missing field/enum and why it appears required
```

Required MOV opcode-class mapping:

```text
88/89 -> OC_MOV_RM_R
8A/8B -> OC_MOV_R_RM
B0-BF -> OC_MOV_R_IMM
C6/C7 -> OC_MOV_RM_IMM
```

Candidate codegen path, requiring Pass 1 confirmation:

```text
If the codegen source lacks an opcode_classes section, add only the MOV-relevant opcode-class entries required by Appendix D Rung 6.

If extract-field entries such as MF_REG_DST, MF_REG_SRC, and MF_REG_RM already exist but are emitted only as legacy macros, extend the package generator to emit canonical M_REG_DST, M_REG_SRC, M_REG_RM, and M_NEXT_EIP package constants.

If emitting all already-defined extract fields is simpler and does not invent new values, that is acceptable only if it remains a codegen synchronization change and does not alter frozen specs.
```

The MOV-relevant opcode classes are:

```text
OC_MOV_RM_R
OC_MOV_R_RM
OC_MOV_R_IMM
OC_MOV_RM_IMM
```

The MOV-relevant register metadata selectors include:

```text
M_REG_DST
M_REG_SRC
M_REG_RM
M_NEXT_EIP
```

Naming-layer note:

```text
Appendix A and Appendix C use the M_ prefix for EXTRACT field names in microcode source:
  M_OPCODE_CLASS
  M_REG_DST
  M_REG_SRC
  M_NEXT_EIP

The current codegen JSON and scripts/ucode_build.py may use MF_ names for the same underlying extract-field values:
  MF_OPCODE_CLASS
  MF_REG_DST
  MF_REG_SRC
  MF_NEXT_EIP

These names may refer to the same numerical IMM10 extract-field indices, but they belong to different layers.
```

Required Pass 1 confirmation:

```text
Confirm the naming convention used in each layer:
  - frozen Appendix A markdown
  - Appendix C / .uasm source
  - appendix_a_codegen.json or current codegen source
  - scripts/ucode_build.py
  - generated package

Document the mapping before writing ENTRY_MOV.
Do not mix M_ and MF_ conventions within the same layer.
Do not create duplicate constants with different numerical values.
```

Guardrails:

```text
New fields or enums must not be invented ad hoc in RTL.
Generated artifacts must not be manually patched.
Frozen specs must not be changed without explicit protected-file authorization.

tools/spec_codegen/appendix_a_codegen.json is a codegen source input, not the frozen Appendix A markdown.
Editing it to reflect values already defined in docs/spec/frozen/appendix_a_field_dictionary.md is a codegen synchronization change, not a frozen-spec change.

Do not add entries to the codegen source that are not already defined in the frozen Appendix A markdown.
If an entry appears required but is absent from frozen Appendix A, stop and report under the protected-file rule.
Only add MOV-required opcode-class constants for Rung 6; do not preemptively add future-rung opcode classes unless they are already generated from existing authoritative data and required by the current codegen workflow.
```

### Gap 7 — memory-destination MOV architectural visibility path unresolved

Known risk:

```text
CM_MOV_REG covers register-destination MOV.
Memory-destination MOV forms require a clear architectural visibility path for memory writes.
A dedicated CM_MOV_MEM mask may not exist.
```

Required resolution:

Before implementing memory-destination MOV, choose and document the smallest Appendix B-consistent mechanism.

Acceptable options to evaluate:

```text
Option A:
  STORE_RM* completes the memory write through load_store under microcode sequencing.
  ENDI then uses a no-GPR commit / cleanup mask.
  Memory visibility is constrained to the intended load/store/bus path and Rung 6 handoff model.

Option B:
  introduce a bounded CM_MOV_MEM or CM_MEM_STORE mask.
  commit_engine authorizes memory-store visibility at ENDI.
  memory writes still occur through the intended load/store/bus path.
```

Reviewer recommendation, not frozen authority:

```text
Option A is a candidate implementation path for Rung 6 only if Pass 1 confirms it is consistent with Appendix B, Appendix D, the active source-of-truth documents, and the live load/store/bus architecture.

Grounded rationale to confirm:
  - Appendix D states that phase-1 MOV cannot fault.
  - If no later Rung 6 fault can occur after STORE_RM*, there may be no required discard point after a completed memory store.
  - Option A may avoid adding a new commit-mask field solely for Rung 6 memory-destination MOV.

Unresolved authority question:
  - Whether a memory write completed before ENDI constitutes a prohibited partial commit under Appendix B anti-drift rules is ambiguous unless the frozen specs or active source-of-truth documents explicitly settle it.
  - Appendix B clearly identifies GPRs, EIP, EFLAGS, and segment-visible state as commit-owned architectural state.
  - External memory visibility must be resolved against the actual frozen spec text and live bus/load-store design, not by analogy to Rung 5.
```

Required Pass 1 decision:

```text
Pass 1 must state whether Option A is accepted as the Rung 6 implementation path, rejected, or still blocked pending owner decision.

If Option A is accepted:
  - memory-destination MOV uses STORE_RM* under microcode sequencing
  - ENDI uses a no-GPR commit / cleanup path
  - testbenches observe and verify the memory write payload and timing
  - the Pass 1 report must explain why this does not violate Appendix B partial-commit discipline

If Option A is not accepted:
  - stop before creating a new commit mask or new ownership rule
```

Selection criteria:

```text
must preserve Appendix B ownership
must keep memory writes on intended load/store/bus path
must not let load_store execute instruction policy
must not create partial commits before ENDI if controlling docs require ENDI visibility
must not break Rung 5
must be observable in testbench
must be bounded to Appendix D MOV
```

Stop condition:

```text
If the memory-destination visibility path requires a new architectural ownership rule, new frozen-spec field, or broad commit redesign, stop and report before implementation.
```

### Gap 8 — MOV decode absent or incomplete

Known risk:

```text
decoder.sv may not yet recognize B0-BF, 88/89/8A/8B, or C6/C7 as ENTRY_MOV.
```

Required resolution:

Add decode support in bounded slices:

```text
Pass 2:
  B8-BF -> ENTRY_MOV, OC_MOV_R_IMM, destination from opcode[2:0], immediate-width metadata, M_NEXT_EIP

Pass 4:
  B0-B7 immediate-to-byte-register support
  B8-BF word/dword immediate-to-register support as required by Appendix D

Pass 5:
  88/89/8A/8B register-register ModRM.mod=11 support

Pass 6:
  88/89/8A/8B memory forms
  C6/C7 immediate-to-memory forms
  displacement and EA metadata required by Appendix D
```

Candidate metadata details, requiring Pass 1 confirmation against Appendix A and live decoder structure:

```text
B8-BF first slice:
  M_OPCODE_CLASS = OC_MOV_R_IMM
  M_REG_DST = opcode[2:0]
  M_IMM_CLASS = immediate width required by selected form
  M_MODRM_CLASS = no-ModRM / none form if such encoding exists in current metadata model
  M_NEXT_EIP = EIP of byte immediately following the consumed immediate
```

Guardrails:

```text
decoder remains classifier/metadata only
decoder must not read operands
decoder must not write registers
decoder must not access memory
decoder must not assert decode completion before all required bytes are consumed and M_NEXT_EIP is valid/stable
```

### Gap 9 — `ENTRY_MOV` microcode absent or incomplete

Known risk:

```text
microcode/src/entries/ may not yet contain ENTRY_MOV implementation.
scripts/ucode_build.py may not yet wire ENTRY_MOV into the generated ROM.
```

Frozen-spec authority for `ENTRY_MOV`:

```text
Appendix C defines ENTRY_MOV as a valid microcode entry.
Appendix C lists entries/entry_mov.uasm as part of the expected microcode source set.
Appendix C shows ENTRY_MOV beginning with extraction of M_OPCODE_CLASS, for example:
  ENTRY_MOV: EXTRACT T6, M_OPCODE_CLASS
```

This is frozen-spec authority that `ENTRY_MOV` exists and begins by extracting the opcode class. It is not invented intent.

Note:

```text
The addresses shown in Appendix C Section 7.3 listing examples are illustrative; see Concern 7 and Gap 13.

The instruction content — specifically that ENTRY_MOV begins with EXTRACT and uses M_OPCODE_CLASS — is grounded in the frozen spec’s instruction-set definition and field-index table.

The instruction content and the example addresses must not be treated as the same type of authority.
```

The dispatch mechanism after that extraction still depends on:

```text
Appendix C-supported branch and comparison forms
live scripts/ucode_build.py helper functions and encoding patterns
available T-register comparison conditions
current generated field constants
microsequencer support for the required generic microinstructions
```

Do not invent a direct branch-on-opcode-class condition unless Appendix C, the live builder, and the microsequencer support it.

Required resolution:

Add `ENTRY_MOV` in staged slices:

```text
Slice 1:
  MOV r32, imm32
  FETCH_IMM32
  STORE_REG_META or STAGE_GPR, whichever Pass 1 confirms as the Appendix A/B/C-consistent staging path
  ENDI CM_MOV_REG

Width expansion:
  MOV r8, imm8
  MOV r16/r32, imm16/imm32

Register-register:
  LOAD_REG_META source
  STORE_REG_META destination or generic UOP_MOV register-to-register microinstruction path, whichever Pass 1 confirms as Appendix A/B/C-consistent
  ENDI CM_MOV_REG

Memory-source:
  FETCH_DISP*
  EA_CALC_*
  LOAD_RM*
  STORE_REG_META or STAGE_GPR, whichever Pass 1 confirms as the Appendix A/B/C-consistent staging path
  ENDI CM_MOV_REG

Memory-destination:
  FETCH_DISP*
  EA_CALC_*
  LOAD_REG_META or FETCH_IMM*
  STORE_RM*
  ENDI selected memory-completion / cleanup path
```

Candidate first-slice microcode shape, requiring Pass 1 confirmation against Appendix C, `ucode_build.py`, condition codes, microsequencer support, and the service ABI:

```text
ENTRY_MOV must select the correct MOV subpath using decoded metadata already produced by decoder.

For the first provisional slice:
  - begin with the frozen-spec ENTRY_MOV opcode-class extraction shape
  - handle the already-decoded immediate-to-register MOV class
  - call the appropriate FETCH_IMM* service for the decoded immediate width
  - wait for explicit service completion
  - preserve Appendix D fault-ordering structure
  - stage the destination register write using either STAGE_GPR microinstruction support or STORE_REG_META service-based staging, whichever Pass 1 confirms is consistent with Appendix A, Appendix B, Appendix C, and the live architecture
  - complete with ENDI CM_MOV_REG or the current authoritative register-destination MOV commit mask

The exact microinstruction sequence depends on:
  - Appendix C microinstruction forms
  - current ucode_build.py encoding helpers
  - available EXTRACT behavior
  - available T-register comparison conditions
  - available branch forms
  - current microsequencer support for those generic microinstructions
```

Guardrails:

```text
microcode owns service ordering
service completion must be explicit before dependent micro-ops advance
SR_WAIT is hold, not completion
Appendix D fault-ordering structure must be preserved
phase-1 MOV fault paths may exist but are not taken
ENTRY_MOV must not include Rung 7+ ALU/flag-production behavior
do not rely on exact pseudo-code names if the live Python ROM builder uses different helper names
do not invent new microinstruction forms
do not invent new condition codes
do not assume there is a direct branch-on-opcode-class condition unless Appendix C, the live Python builder, and microsequencer already support it
if ENTRY_MOV needs opcode-class dispatch and the current Appendix C / ucode_build.py / microsequencer combination lacks a way to compare extracted metadata, stop and report the missing mechanism before extending any layer
do not use unnamed “equivalent” mechanisms; name the actual Appendix A/B/C-defined microinstruction or live service path selected by Pass 1
```

### Gap 10 — Rung 5 acceptance must be confirmed before implementation

Known risk:

```text
Rung 6 starts only from the accepted Rung 5 baseline.
```

Required resolution:

Pass 1 must confirm:

```text
docs/implementation/rung5_acceptance.md
docs/implementation/rung5_verification.md
current branch
current HEAD
working tree status
HEAD relationship to accepted Rung 5 commit
```

Known review finding to verify in Pass 1:

```text
rung5_acceptance.md records explicit acceptance tied to commit b8e75f9.
rung5_verification.md records clean verification.
```

If Rung 5 acceptance cannot be confirmed, stop before Rung 6 implementation.

### Gap 11 — `FETCH_IMM16` and `FETCH_IMM32` missing or unconfirmed

Known risk:

```text
FETCH_IMM16 and FETCH_IMM32 are required by Appendix D Rung 6 MOV.
The implementation must confirm whether fetch_engine.sv currently implements FETCH_IMM16 and FETCH_IMM32 or whether only FETCH_IMM8 is active.
The implementation must confirm whether service_dispatch.sv routes FETCH_IMM16 and FETCH_IMM32 to the fetch engine.
```

Required resolution:

```text
Implement or enable FETCH_IMM16 and FETCH_IMM32 using the existing fetch/immediate byte-consumption model required by the frozen stage-boundary rules.

Required behavior:
  - FETCH_IMM8 consumes one immediate byte
  - FETCH_IMM16 consumes two immediate bytes
  - FETCH_IMM32 consumes four immediate bytes
  - immediate bytes are assembled in x86 little-endian order
  - service completion is explicit
  - SR_WAIT remains hold, not completion
  - decoder and microcode must not advance based on partial immediate data
```

Extension semantics:

```text
FETCH_IMM8 zero-extends the immediate byte to the service result width.
This is correct for MOV B0-B7 byte-register immediate forms.
Do not confuse FETCH_IMM8 zero-extension with displacement sign-extension.
FETCH_IMM16 and FETCH_IMM32 immediate assembly must be confirmed against Appendix A and the live fetch/service ABI before implementation.
```

Guardrails:

```text
Do not implement immediate fetch as instruction-specific MOV RTL.
Do not bypass the fetch engine's registered handoff / SR_WAIT behavior.
Do not use displacement sign-extension rules for immediate fetch unless the frozen specs explicitly require it for a specific immediate class.
Do not let service_dispatch route an immediate service to the default/no-engine path.
```

Pass impact:

```text
Required for Pass 3 MOV r32, imm32.
Required for Pass 4 immediate-width expansion.
Required for C6/C7 immediate-to-memory forms.
Required before full Rung 6 completion.
```

### Gap 12 — `service_dispatch.sv` does not route all MOV-required services and may overlap existing operand service routing

Known risk:

```text
Rung 6 requires service routing for:
  - FETCH_IMM16
  - FETCH_IMM32
  - EA_CALC_16
  - EA_CALC_32
  - LOAD_RM8
  - LOAD_RM16
  - LOAD_RM32
  - STORE_RM8
  - STORE_RM16
  - STORE_RM32
  - LOAD_REG_META
  - STORE_REG_META

The implementation must confirm whether service_dispatch.sv currently routes each required service to the correct bounded engine.
```

Additional known risk:

```text
Earlier rungs may route LOAD_RM16 or LOAD_RM32 to operand_engine for a bounded CALL/control-transfer subset.
Rung 6 requires the full MOV LOAD_RM*/STORE_RM* surface.
The implementation must confirm whether the existing operand_engine routing remains valid, should be moved to load_store, or should remain split by a documented bounded mechanism.
```

Required resolution:

```text
As each MOV-required service implementation lands, add or confirm its service_dispatch routing.
Confirm whether LOAD_RM16 and LOAD_RM32 route to load_store, remain routed to operand_engine, or are split by a bounded documented rule.
Document the routing decision in the Pass 1 report before implementing Pass 5 or Pass 6 behavior that depends on it.
```

Guardrails:

```text
service_dispatch remains routing/muxing only.
service_dispatch must not execute MOV policy.
Do not leave two conflicting engines responsible for the same service without a documented ownership rule.
Do not silently route MOV-required services to a default/no-engine path.
Do not expand operand_engine beyond its bounded earlier-rung role unless the authority chain supports that change.
```

Pass impact:

```text
Blocking for any pass that calls a newly required MOV service.
Required before register-register MOV if LOAD_REG_META / STORE_REG_META depend on service_dispatch.
Required before memory MOV if EA_CALC*, LOAD_RM*, or STORE_RM* depend on service_dispatch.
Required before full Rung 6 completion.
```

### Gap 13 — `.uasm` source files and `ucode_build.py` serve different purposes and both require updates

Known risk:

```text
The current effective bootstrap ROM generator is scripts/ucode_build.py.
scripts/ucode_build.py builds ROM words directly in Python.
scripts/ucode_build.py does not currently parse .uasm files.

The .uasm files under microcode/src/ are required for source organization, review, and future assembler alignment.
The .uasm files do not currently affect the built ROM unless scripts/ucode_build.py is also updated.
```

Required resolution:

```text
To add or change ENTRY_MOV behavior:

1. Write or update microcode/src/entries/entry_mov.uasm for review, source organization, and future-assembler alignment.
2. Add the equivalent ROM encoding to scripts/ucode_build.py so the built ROM actually changes.
3. Keep the .uasm source and Python ROM encoding consistent with each other, Appendix C, and Appendix A.
```

Appendix C macro caution:

```text
Appendix C specifies pseudo-instructions such as WIDTH_DISPATCH and ADDR_DISPATCH.
These are frozen-spec assembler concepts.
They are not automatically available as Python helpers in scripts/ucode_build.py.

Before using any Appendix C pseudo-instruction concept in the Python ROM builder, confirm the corresponding Python helper or encoding pattern exists.
Do not assume an Appendix C macro is implemented in ucode_build.py.
```

Address-example caution:

```text
Appendix C examples may contain illustrative uPC addresses.
The live dispatch address must be taken from scripts/ucode_build.py and the current generated ROM layout.
Do not treat Appendix C example addresses as literal implementation addresses unless the live builder confirms them.
```

Naming-layer caution:

```text
Appendix A and Appendix C use M_ field names in frozen microcode/source notation.
The current codegen JSON and Python ROM builder may use MF_ names for the same numerical extract-field values.
Confirm the correct naming convention for each layer before editing.
```

Guardrails:

```text
Do not treat .uasm changes alone as proof that the ROM changed.
Do not treat ucode_build.py Python encoding alone as sufficient without a corresponding .uasm source update for review purposes.
Do not add Python ROM logic that has no corresponding .uasm representation.
Do not add .uasm syntax that cannot be represented by the current Appendix C spec or current Python builder without a documented blocker/decision.
Do not assume Appendix C pseudo-instructions such as WIDTH_DISPATCH or ADDR_DISPATCH exist as Python builder helpers without confirming ucode_build.py support.
```

Pass impact:

```text
Applies from Pass 2 onward wherever ENTRY_MOV microcode is added or changed.
Pass 2 must update both review-source microcode and live ROM builder if ENTRY_MOV behavior changes.
```

### Gap 14 — `microsequencer.sv` implements only a subset of Appendix C microinstructions and condition codes

Known risk:

```text
The live microsequencer.sv implements only the microinstructions and condition codes needed through Rung 5.

The following condition codes are defined in the generated package and/or Appendix C but are not currently evaluated by microsequencer.sv:
  - C_T0Z
  - C_T0NZ
  - C_W8
  - C_W16
  - C_W32
  - C_ADDR16
  - C_ADDR32

In the current live source, these fall through to the default branch behavior and do not take the branch.

The following UOP classes are defined but not currently implemented by microsequencer.sv:
  - UOP_LOADI
  - UOP_MOV register-to-register

In the current live source, these fall through to default uPC advance with no useful effect.

UOP_EXTRACT is currently only partially implemented:
  - only the specific FC_TO_VECTOR extraction case is handled
  - general field extraction is not implemented
  - extraction into arbitrary T-register destinations is not implemented

UOP_STAGE is currently only partially implemented:
  - STAGE_STACK_ADJ is handled
  - general staging, including STAGE_GPR required for MOV register writeback, is not handled

UOP_COMMIT (UOP_CLASS=0xB) and UOP_CLEAR_FAULT (UOP_CLASS=0xD) are also defined in Appendix C but unimplemented in the current microsequencer.
Pass 1 must confirm whether either is required for ENTRY_MOV.
If neither is required for the frozen Rung 6 MOV scope, classify them as out of scope for Rung 6.
Do not implement UOP_COMMIT or UOP_CLEAR_FAULT speculatively merely because they are defined in Appendix C.

The corresponding live ROM builder, scripts/ucode_build.py, must also be inspected because it may lack constants and helper functions for these microinstruction forms, condition codes, extract fields, and commit/stage behavior.
```

Required resolution:

```text
Pass 1 must inspect microsequencer.sv, scripts/ucode_build.py, Appendix C, Appendix B, and the generated package together.

Pass 1 must classify each missing microinstruction, condition code, extract-field behavior, staging behavior, and Python ROM-builder helper as:
  - required blocker for Pass 2
  - required blocker for a later Rung 6 pass
  - already resolved in live source
  - out of scope for Rung 6

Do not implement microsequencer extensions that are not explicitly required by Appendix C and the active Rung 6 pass.

Do not implement general EXTRACT, LOADI, MOV register-to-register, condition-code, STAGE, COMMIT, or CLEAR_FAULT behavior speculatively beyond what Rung 6 requires.
```

Guardrails:

```text
Extending microsequencer.sv must not move x86 instruction policy into the microsequencer.
The microsequencer executes microinstructions; it must not implement MOV semantics directly.
Microinstruction extensions must follow Appendix B ownership rules.
Microinstruction extensions must remain bounded to Appendix C-defined behavior and Rung 6-required use.
scripts/ucode_build.py must encode only behavior that has an Appendix C / .uasm counterpart or an explicitly documented current-builder representation.
Any change to microsequencer.sv or scripts/ucode_build.py must preserve Rung 5 regression before claiming pass progress.
```

Pass impact:

```text
Required before Pass 2 ENTRY_MOV skeleton can execute meaningful opcode-class extraction or dispatch.
Required before any pass that depends on EXTRACT, LOADI, MOV register-to-register, width/address condition dispatch, or STAGE_GPR.
UOP_COMMIT and UOP_CLEAR_FAULT are not automatically required by Rung 6; Pass 1 must classify them.
Required before Rung 6 completion.
```

---

## Implementation slice policy

Rung 6 should be developed in small bounded passes.

The first implementation slice should be intentionally smaller than the final gate:

```text
B8+rd id      MOV r32, imm32
```

That first slice exists to prove the register writeback and commit model before the more complex MOV forms are layered in.

The staged implementation order does not redefine the final Rung 6 gate.

The final gate remains the full Appendix D MOV scope.

Do not mistake a pass-level proof for Rung 6 completion.

Do not narrow Appendix D to make an early pass easier.

Do not widen Appendix D because z8086, ao486, review comments, or chat context suggest additional useful behavior.

---

## Out of scope

Unless explicitly authorized in a separate rung or protected-file pass, Rung 6 does not include:

- unrelated cleanup
- directory restructuring
- broad package/include cleanup
- broad Makefile cleanup
- debug-framework redesign
- broad Python-generation refactor beyond the smallest required MOV build support
- generated-artifact manual edits
- README or overview modernization before implementation facts exist
- MOV to or from segment registers
- MOV to or from control registers
- MOV to or from debug registers
- MOV to or from test registers
- string MOVS instructions
- XCHG
- LEA
- PUSH/POP expansion beyond already accepted Rung 5 behavior
- ALU operations
- ADD, SUB, AND, OR, XOR, CMP, TEST, INC, DEC, NEG, NOT
- flags updates
- flags-production behavior
- operand-size override behavior beyond what Appendix D requires for Rung 6 MOV
- address-size override behavior beyond what Appendix D requires for Rung 6 MOV
- protected-mode behavior
- descriptor validation
- privilege checks
- task gates
- PIC/APIC behavior
- INT3
- INTO
- nested exceptions
- double faults
- generalized exception handling
- new fault classes beyond the already accepted bounded #UD path and whatever unsupported-MOV rejection is required
- Rung 7 ALU / flag-production behavior
- Rung 8 or later behavior
- speculative future-rung preparation
- broad microsequencer feature completion beyond the generic Appendix C behavior required by Rung 6

Rung 6 should be expanded only enough to make the frozen Appendix D MOV scope work and be provable.

---

## Architectural constraints

Rung 6 must preserve the frozen ownership boundaries.

In particular:

- decoder remains classification and byte/metadata collection logic.
- decoder may identify required MOV entry points and collect bounded opcode, ModRM, immediate, displacement, register, width, addressing metadata, byte-consumption facts, and `M_NEXT_EIP`.
- `M_NEXT_EIP` is the actual metadata field for the EIP of the byte immediately following the instruction; there is no separate post-instruction length field unless the frozen specs define one.
- decoder must not directly update architectural GPR state.
- decoder must not directly update architectural memory state.
- decoder must not directly update architectural EIP/ESP/SP/CS/FLAGS.
- microsequencer remains sequencing owner for generic microinstructions.
- microsequencer must not know x86 encoding beyond the decode payload and dispatch entry.
- microsequencer must not implement x86 MOV semantics directly.
- microcode must explicitly sequence required MOV behavior.
- helper RTL must remain bounded service or preparation logic, not a hidden instruction engine.
- service_dispatch must remain routing/muxing only.
- ea_calc must compute effective addresses only and must not know which instruction is executing.
- load_store must perform register-form operand access and memory access only as a service.
- commit path remains the architectural visibility boundary for architectural register publication.
- memory writes required by MOV must occur only through the intended load/store/bus path under microcode sequencing.
- register-visible results become architectural only through the intended commit boundary.
- fetch/prefetch progression must remain consistent with committed instruction completion.
- unsupported forms must continue to use the existing bounded unsupported / #UD path where applicable.
- Rung 5 INT, IRET, and #UD behavior must remain intact.

Do not bypass architecture just to make a Rung 6 test pass.

If an apparent fix requires architectural boundary smearing, stop and surface that explicitly.

---

## Register-writeback guardrail

Rung 6 is allowed to add bounded RTL support for pending GPR writeback only when explicitly sequenced.

The desired model for register-destination MOV forms is:

```text
decoder identifies MOV form and captures bounded metadata
microsequencer enters ENTRY_MOV
microcode sequences the MOV operation
bounded helper/service logic prepares a pending register write
commit_engine publishes the architectural register update at ENDI
```

Acceptable bounded behavior:

- compute destination register index from the selected opcode or ModRM field.
- compute source register index from the selected opcode or ModRM field.
- assemble the selected immediate width.
- load memory source operands through the intended load/store path.
- stage pending writeback data and destination.
- expose pending writeback observability for the testbench.
- commit the staged register write only at the architectural commit boundary.
- use either STAGE_GPR microinstruction support or STORE_REG_META service-based staging only after Pass 1 confirms the selected path is consistent with Appendix A, Appendix B, Appendix C, and the live architecture.

Bad hidden RTL behavior:

- decoder directly writes the architectural register file.
- operand helper writes architectural state before commit.
- microsequencer mutates architectural GPR state outside the commit path.
- microsequencer implements MOV register write behavior as x86 opcode policy rather than executing generic microinstructions.
- commit engine contains broad opcode-specific MOV execution instead of bounded commit publication.
- service dispatch silently implements generalized instruction behavior beyond routing.
- register state becomes visible before the intended commit boundary.
- unnamed alternative staging mechanisms.

---

## Memory-MOV guardrail

Rung 6 includes memory MOV behavior required by Appendix D.

That support must remain MOV-specific and bounded to the frozen Rung 6 gate.

Acceptable bounded behavior:

- use `EA_CALC_16` and `EA_CALC_32` only as required for Rung 6 MOV addressing.
- use displacement fetch variants only as required by Rung 6 MOV addressing.
- use `LOAD_RM8/16/32` and `STORE_RM8/16/32` only as required for Rung 6 MOV operands.
- use `LOAD_REG_META` and `STORE_REG_META` only as required for Rung 6 MOV.
- prove memory reads and writes through focused MOV testbenches.
- prove all Appendix D-required addressing modes.
- preserve prior Rung 5 behavior.

Bad hidden RTL behavior:

- adding generalized memory instruction execution beyond MOV.
- adding ALU-memory operations.
- adding stack-memory expansion beyond Rung 5.
- adding segment-register behavior.
- adding protected-mode memory semantics.
- adding descriptor validation or privilege checks.
- treating EA support as permission to implement future-rung addressing behavior beyond MOV.

Appendix D states that phase-1 MOV cannot fault. Rung 6 microcode may include the required fault-path structure, but those paths must not create new phase-1 fault behavior beyond the frozen fault-ordering model.

If memory MOV implementation begins to require protected mode, segment validation, generalized exception policy, or future-rung behavior, stop and report.

---

## Fault-ordering guardrail

Rung 6 must preserve the Appendix D MOV fault-ordering model.

For MOV forms, Appendix D defines this ordering:

```text
1. Instruction fetch
2. FETCH_DISP*
3. EA_CALC_*
4. LOAD_RM*
5. STORE_RM*
```

The ordering is enforced by microcode sequencing. Earlier service calls that can fault are called before later ones. If an earlier service faults in a future phase, microcode branches to `SUB_FAULT_HANDLER` before calling subsequent services.

For phase 1 / Rung 6:

```text
MOV cannot fault in phase 1.
All fault paths in MOV microcode are present but will never be taken.
```

Do not create hardware fault-priority logic for MOV.

Do not let services decide exception priority.

Do not add generalized exception handling as part of Rung 6.

---

## Pipeline and stage-boundary expectations

Rung 6 must preserve clear stage boundaries.

Where a signal represents a real stage handoff, preserved metadata item, immediate payload, displacement payload, effective address, service result, pending register write, memory write intent, commit-visible decision, or architectural register update, it must remain explicitly latched or registered at the boundary unless the controlling documents clearly define a different behavior.

Do not replace clear stage handoff points with broad combinational reach-through paths just to make the active MOV slice work.

Correctness, ownership clarity, Fmax discipline, and reviewable handoff behavior take priority over zero-bubble execution.

Examples of boundaries that should remain explicit in this rung include:

- fetch / decoder byte visibility
- decoder-owned MOV classification handed to microsequencer
- destination register metadata
- source register metadata
- operand width metadata
- immediate payload metadata
- displacement payload metadata
- `M_NEXT_EIP`
- effective-address metadata
- memory load result metadata
- memory store intent metadata
- pending writeback valid / destination / value
- commit-time architectural register publication
- debug/testbench observability for pre-commit versus post-commit register state
- generic microinstruction result handoffs required by Rung 6

---

## Stage handoff and bubble model

Rung 6 follows a registered stage-to-stage handoff model.

For the active MOV paths in this rung:

- each stage performs only its intended work
- each stage registers or explicitly latches its output at the stage boundary
- the producing stage must hold that output stable until the receiving stage can accept it
- the producing stage must not discard, overwrite, or recompute that boundary output while acceptance is pending
- the receiving stage advances only when it can legally accept the handoff
- bubbles between stages are allowed
- correctness, ownership clarity, timing discipline, and reviewable handoff behavior take priority over zero-bubble execution
- `SR_WAIT` remains a true wait / hold condition, not a terminal completion
- service completion must be explicit before microcode advances
- commit-visible register state changes must occur only at ENDI
- memory writes must occur only through the intended load/store path under microcode sequencing
- abandoned-stream work must not survive a committed redirect, fault delivery, or other accepted control-flow boundary

For service-oriented MOV paths, `SR_WAIT` is the explicit hold condition. A stage or service that is not ready to hand off completion must hold its state and boundary outputs stable until the next stage or control owner can accept them.

A service that returns `SR_WAIT` has not completed. Microcode must not consume partial results, advance to a dependent service, or issue ENDI based on a waiting service.

Do not replace this model with broad combinational reach-through, same-cycle shortcutting, or zero-bubble bypasses that blur stage ownership.

`service_dispatch` remains a thin routing layer, not a pipeline stage in its own right unless a controlling document explicitly says otherwise. Registered or latched handoff boundaries belong in the producing service and consuming control owner, not in `service_dispatch` itself.

---

## MOV path handoff examples

The intended Rung 6 handoff model for register-destination MOV forms is:

```text
fetch / predecode
  -> decoder consumes selected MOV bytes and emits ENTRY_MOV metadata
  -> microsequencer dispatches ENTRY_MOV
  -> microcode sequences bounded MOV operation
  -> helper/service path stages pending GPR writeback
  -> commit_engine commits the selected architectural GPR update at ENDI
  -> fetch/decode advance to the next instruction
```

The intended Rung 6 handoff model for memory-source MOV forms is:

```text
fetch / predecode
  -> decoder consumes selected MOV bytes and emits ENTRY_MOV metadata
  -> microsequencer dispatches ENTRY_MOV
  -> microcode sequences ModRM/displacement/effective-address work
  -> load_store service reads the selected memory operand
  -> helper/service path stages pending GPR writeback
  -> commit_engine commits the selected architectural GPR update at ENDI
  -> fetch/decode advance to the next instruction
```

The intended Rung 6 handoff model for memory-destination MOV forms is:

```text
fetch / predecode
  -> decoder consumes selected MOV bytes and emits ENTRY_MOV metadata
  -> microsequencer dispatches ENTRY_MOV
  -> microcode sequences ModRM/displacement/effective-address work
  -> helper/service path obtains source register or immediate data
  -> load_store service writes the selected memory operand through the intended memory path
  -> instruction completes through normal sequencing / ENDI discipline
  -> fetch/decode advance to the next instruction
```

For immediate-to-register MOV, the expected semantic payload is:

```text
opcode class: MOV immediate-to-register
destination register: opcode[2:0]
immediate value: imm8, imm16, or imm32 according to the selected form
commit action: publish pending GPR write at instruction completion
```

For register-to-register MOV, the expected semantic payload is:

```text
opcode class: MOV register-to-register
ModRM.mod: 11
destination register: selected by opcode semantics
source register: selected by opcode semantics
commit action: publish pending GPR write at instruction completion
```

For memory MOV forms, the expected semantic payload is:

```text
opcode class: MOV involving memory operand
ModRM/displacement: consumed according to the required addressing mode
effective address: calculated through EA_CALC_16 or EA_CALC_32 as required
source data: register, immediate, or memory load result according to opcode
destination: register or memory according to opcode
architectural effect: register commit or memory store through the intended path
```

---

## Required implementation shape

Rung 6 implementation should be developed in small passes.

These passes are an implementation sequence only. They do not redefine the final Rung 6 gate.

The final Rung 6 gate remains the full Appendix D MOV matrix.

### Pass 1 — Read-only alignment and blocker confirmation

Goal:

- confirm current branch and clean state.
- confirm accepted Rung 5 baseline.
- read the required authority chain.
- confirm Appendix D Rung 6 MOV scope.
- confirm z8086 / ao486 usage limits from frozen specs.
- confirm whether approved ao486 MOV donor material is present.
- inspect current decode, microcode, services, commit, register-file, generated package, Makefile, and testbench structure.
- inspect fetch_engine support for FETCH_IMM8, FETCH_IMM16, and FETCH_IMM32.
- inspect service_dispatch routing for all MOV-required services.
- inspect any operand_engine / load_store service routing overlap.
- inspect `.uasm` source status and `scripts/ucode_build.py` live ROM builder status.
- inspect `microsequencer.sv` support for Rung 6-required generic microinstructions.
- inspect `microsequencer.sv` condition-code support for Rung 6-required branches.
- inspect `scripts/ucode_build.py` helper/constant support for Rung 6-required `ENTRY_MOV` ROM encoding.
- confirm actual ENTRY_MOV dispatch address from `scripts/ucode_build.py` and generated ROM layout.
- confirm Appendix C example addresses are illustrative unless the live builder says otherwise.
- confirm M_ / MF_ naming conventions in Appendix A, Appendix C, codegen source, Python builder, and generated package.
- classify planned work as required blocker, required acceptance cleanup, candidate implementation path requiring confirmation, or out of scope.
- confirm all known implementation gaps listed in this file as present, absent, already resolved, or contradicted by live source.
- confirm whether candidate resolution paths in this file are consistent with live source and frozen/process authority.
- resolve or escalate the memory-destination visibility-path concern.
- resolve or escalate ENTRY_MOV opcode-class dispatch mechanics.
- classify Gap 14 items individually, including whether UOP_COMMIT or UOP_CLEAR_FAULT is out of scope for Rung 6.
- select and document the Rung 6 GPR staging path: STAGE_GPR microinstruction support or STORE_REG_META service-based staging.
- select and document the register-transfer path for register-to-register MOV: generic UOP_MOV register-to-register microinstruction support or a service-based register-transfer path confirmed by Pass 1.
- propose the smallest bounded Pass 2 implementation plan.
- make no edits.

Expected proof:

```text
git status --short
git rev-parse --abbrev-ref HEAD
git log --oneline -n 5
```

Required Pass 1 report items:

```text
branch
HEAD
working tree status
Rung 5 acceptance baseline
ao486 MOV donor material status
z8086 structural-template relevance, if any
MOV decode support status
ENTRY_MOV microcode status
FETCH_IMM8 / FETCH_IMM16 / FETCH_IMM32 implementation status
service_dispatch routing status for all MOV-required services
operand_engine / load_store overlap decision
.uasm / ucode_build.py consistency status
actual ENTRY_MOV live ROM dispatch address
Appendix C example-address treatment
M_ / MF_ extract-field naming-layer mapping
Appendix C pseudo-instruction support status in ucode_build.py
microsequencer condition-code support status for C_T0Z, C_T0NZ, C_W8, C_W16, C_W32, C_ADDR16, C_ADDR32
microsequencer UOP support status for UOP_LOADI, UOP_MOV register-to-register, UOP_COMMIT, and UOP_CLEAR_FAULT
microsequencer EXTRACT support status for general field indices and T-register destinations
microsequencer STAGE support status for STAGE_GPR
GPR staging path decision: STAGE_GPR microinstruction support vs STORE_REG_META service-based staging
register-transfer path decision: UOP_MOV register-to-register vs service-based register-transfer path
ucode_build.py helper/constant support for required ENTRY_MOV microinstructions
Gap 14 classification for each missing microsequencer and ucode_build.py item
generated package support for ENTRY_MOV, CM_MOV_REG, OC_MOV_*, M_REG_DST, M_REG_SRC, M_REG_RM, M_NEXT_EIP
Appendix A codegen source status
code generator support for OC_* and M_* package constants
reg_file status
ea_calc status
load_store status
commit_engine GPR commit support status
memory-destination MOV commit/store-path status
memory-destination visibility-path decision or owner-blocked status
ENTRY_MOV opcode-class dispatch mechanism or missing-mechanism status
Rung 6 Make target status
exact blockers for Pass 2
exact stop conditions currently active
candidate implementation paths accepted, rejected, or needing owner decision
proposed smallest bounded Pass 2 implementation plan
explicit statement that no files were edited
```

Pass 1 must not claim Rung 6 implementation progress.

### Pass 2 — Codegen/constants, decode skeleton, immediate-fetch support, service routing, and ENTRY_MOV skeleton

Goal:

- resolve required generated constant / metadata availability through the approved codegen workflow.
- implement or enable the immediate-fetch service support required for the first MOV slice.
- add required service_dispatch routing for services used by the first MOV slice.
- resolve the minimum required Gap 14 microsequencer and `ucode_build.py` support needed for the first `ENTRY_MOV` skeleton.
- ensure `ENTRY_MOV` opcode-class extraction has a working Appendix C-consistent microinstruction path in both `.uasm` review source and `scripts/ucode_build.py`.
- preserve the boundary that microsequencer executes generic microinstructions and does not execute MOV semantics.
- add bounded decode recognition for the first selected MOV immediate-to-register form.
- add or connect the `ENTRY_MOV` microcode path.
- update both `microcode/src/entries/entry_mov.uasm` and `scripts/ucode_build.py` if ENTRY_MOV behavior changes.
- confirm the actual live ROM dispatch address used for ENTRY_MOV.
- add required build hooks.
- ensure unsupported adjacent forms still route to the existing unsupported / #UD path.
- preserve all Rung 5 behavior.

Preferred first target:

```text
B8+rd id      MOV r32, imm32
```

Expected proof:

```text
make codegen
make ucode
make rung5-regress
git diff --check
```

Pass 2 must not claim Rung 6 completion.

### Pass 3 — GPR register file and MOV immediate-to-register execution

Goal:

- implement the smallest bounded architectural GPR mechanism required for the first MOV proof.
- implement bounded immediate fetch / assembly for the selected immediate-to-register MOV form.
- route destination register selection.
- stage register writeback using STAGE_GPR microinstruction support or STORE_REG_META service-based staging, whichever Pass 1 selected.
- commit register writeback only at the architectural visibility boundary.
- prove no early architectural visibility.
- prove `FETCH_IMM32` for `MOV r32, imm32`.
- preserve `.uasm` / `ucode_build.py` consistency for any microcode behavior changed in this pass.
- preserve all Rung 5 behavior.

Primary target:

```text
B8+rd id      MOV r32, imm32
```

Expected testbench:

```text
sim/tb/tb_rung6_mov_imm.sv
```

Expected target:

```text
make rung6-pass3-sim
```

Pass 3 must not claim Rung 6 completion.

### Pass 4 — Immediate-to-register width expansion

Goal:

- extend immediate-to-register MOV to the Appendix D required widths.
- prove `B0-B7` byte immediate-to-register MOV.
- prove `B8-BF` word/dword immediate-to-register MOV as required.
- prove `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` behavior required by MOV.
- prove all registers for the supported widths.
- preserve staged writeback and commit-only architectural visibility.
- preserve `.uasm` / `ucode_build.py` consistency for any microcode behavior changed in this pass.
- preserve all Rung 5 behavior.

Required forms:

```text
B0-B7         MOV r8, imm8
B8-BF         MOV r16/r32, imm16/imm32
```

Expected target examples:

```text
make rung6-mov-reg-imm-sim
```

Target names may differ, but the verification coverage must match Appendix D.

Pass 4 must not claim Rung 6 completion unless the full Appendix D MOV gate is also complete.

### Pass 5 — Register-to-register MOV

Goal:

- add ModRM register-only MOV forms.
- implement register metadata service support required for register-register MOV.
- confirm service_dispatch routing for register metadata services.
- resolve any additional Gap 14 microsequencer and builder support required by register-register MOV, using generic UOP_MOV register-to-register microinstruction support or a service-based register-transfer path confirmed by Pass 1.
- prove `ModRM.mod = 11`.
- prove all 8 register combinations.
- prove required widths.
- preserve staged writeback and commit-only architectural visibility.
- preserve `.uasm` / `ucode_build.py` consistency for any microcode behavior changed in this pass.
- preserve all Rung 5 behavior.

Required forms:

```text
88 /r         MOV r/m8, r8 with ModRM.mod = 11
89 /r         MOV r/m16/r/m32, r16/r32 with ModRM.mod = 11
8A /r         MOV r8, r/m8 with ModRM.mod = 11
8B /r         MOV r16/r32, r/m16/r/m32 with ModRM.mod = 11
```

Expected target examples:

```text
make rung6-mov-reg-reg-sim
```

Pass 5 must not claim Rung 6 completion unless the full Appendix D MOV gate is also complete.

### Pass 6 — Memory-source and memory-destination MOV

Goal:

- implement MOV memory read forms required by Appendix D.
- implement MOV memory write forms required by Appendix D.
- implement immediate-to-memory MOV forms required by Appendix D.
- implement required displacement fetch support.
- implement required EA calculation support.
- implement required load/store support.
- confirm service_dispatch routing for EA/load/store services.
- resolve and implement the memory-destination architectural visibility path.
- resolve any additional Gap 14 microsequencer and builder support required by width/address condition dispatch or memory-form sequencing.
- prove all required widths.
- prove all Appendix D-required addressing modes.
- preserve `.uasm` / `ucode_build.py` consistency for any microcode behavior changed in this pass.
- preserve all Rung 5 behavior.

Required forms include:

```text
88 /r         MOV r/m8, r8
89 /r         MOV r/m16/r/m32, r16/r32
8A /r         MOV r8, r/m8
8B /r         MOV r16/r32, r/m16/r/m32
C6 /0         MOV r/m8, imm8
C7 /0         MOV r/m16/r/m32, imm16/imm32
```

Required support includes:

```text
FETCH_DISP* variants required by MOV
FETCH_IMM* variants required by immediate-to-memory MOV
EA_CALC_16
EA_CALC_32
LOAD_RM8/16/32
STORE_RM8/16/32
LOAD_REG_META
STORE_REG_META
```

Expected target examples:

```text
make rung6-mov-reg-mem-sim
make rung6-mov-mem-reg-sim
make rung6-mov-mem-imm-sim
```

Target names may differ, but the verification coverage must match Appendix D.

### Pass 7 — Full frozen Rung 6 MOV matrix

Goal:

- complete all MOV forms required by Appendix D.
- complete required immediate/displacement fetch support.
- complete required EA calculation support.
- complete required register metadata support.
- complete required load/store MOV support.
- complete all Rung 6-required generic microsequencer and `ucode_build.py` support from Gap 14.
- prove all MOV widths and Appendix D-required addressing forms.
- prove EFLAGS unchanged by MOV.
- preserve all Rung 0 through Rung 5 behavior.
- check ao486 donor alignment or explicitly approved replacement reference.
- confirm `.uasm` / `ucode_build.py` consistency for all ENTRY_MOV behavior.
- record verification from the actual committed candidate state.

Expected aggregate target:

```text
make rung6-regress
```

`make rung6-regress` must include or invoke:

```text
make rung5-regress
make rung6-mov-reg-reg-sim
make rung6-mov-reg-imm-sim
make rung6-mov-reg-mem-sim
make rung6-mov-mem-reg-sim
make rung6-mov-mem-imm-sim
make rung6-flags-unchanged-sim
```

Target names may differ, but the regression must prove the full Appendix D MOV matrix before Rung 6 completion is claimed.

---

## Execution-order summary

This summary is a bounded implementation order, not a completion claim and not a substitute for Appendix D.

```text
Pass 1:
  Confirm Rung 5 baseline.
  Record ao486 donor status.
  Confirm all known gaps against live source.
  Decide whether candidate Option A for memory-destination MOV is acceptable or blocked.
  Confirm ENTRY_MOV dispatch mechanics from Appendix C, ucode_build.py, and microsequencer.sv.
  Confirm FETCH_IMM16/FETCH_IMM32 status.
  Confirm service_dispatch routing and operand_engine/load_store overlap.
  Confirm .uasm / ucode_build.py dual-source requirements.
  Confirm M_ / MF_ naming layer mapping.
  Confirm actual ENTRY_MOV live ROM dispatch address.
  Classify Gap 14 microsequencer and builder blockers, including UOP_COMMIT and UOP_CLEAR_FAULT.
  Select STAGE_GPR vs STORE_REG_META staging path.
  Select UOP_MOV register-to-register vs service-based register-transfer path.
  Make no edits.

Pass 2:
  Resolve codegen/package constants through approved workflow.
  Add required immediate-fetch support for the first slice.
  Add required service routing for the first slice.
  Add minimum required generic microsequencer and builder support for ENTRY_MOV extraction/dispatch skeleton.
  Add B8-BF decode skeleton.
  Add ENTRY_MOV skeleton in both .uasm and ucode_build.py if behavior changes.
  Add first valid Rung 6 Make target only if matching testbench exists.
  Preserve rung5-regress.

Pass 3:
  Bring architectural GPR file / commit path live for MOV.
  Implement MOV r32, imm32 execution.
  Prove no early GPR visibility.
  Prove FETCH_IMM32, M_NEXT_EIP, and EFLAGS unchanged for the first slice.

Pass 4:
  Extend immediate-to-register MOV widths and registers.
  Prove FETCH_IMM8/FETCH_IMM16/FETCH_IMM32 behavior required by MOV.

Pass 5:
  Add register-register MOV via ModRM.mod=11 and register metadata services.

Pass 6:
  Add EA_CALC, LOAD_RM, STORE_RM, memory-source MOV, memory-destination MOV, and immediate-to-memory MOV.
  Confirm selected memory-destination visibility path in tests.

Pass 7:
  Confirm donor alignment or approved replacement reference.
  Confirm .uasm / ucode_build.py consistency.
  Confirm Gap 14 is resolved only to the extent required by Rung 6.
  Run full MOV matrix.
  Record verification.
  Only then seek acceptance.
```

No pass claims Rung 6 completion. Only Pass 7 with all gaps resolved and `make rung6-regress` passing against the committed state may lead to a completion claim.

---

## Behavioral contract

Rung 6 must prove the following behavior for required MOV forms:

- reset and initial state are known.
- instruction fetch begins from the expected address.
- opcode byte is consumed.
- ModRM byte is consumed where required.
- immediate bytes are consumed where required.
- displacement bytes are consumed where required.
- decode class is the bounded MOV class.
- `M_OPCODE_CLASS` is correct for each required MOV form.
- destination register metadata is correct.
- source register metadata is correct where applicable.
- operand width metadata is correct.
- `M_NEXT_EIP` is correct for each MOV form.
- immediate value is assembled correctly where applicable.
- immediate byte/word/dword assembly is little-endian.
- `FETCH_IMM8` zero-extension behavior is preserved for byte-register immediate forms.
- displacement value is assembled correctly where applicable.
- effective address is calculated correctly for memory forms.
- memory source data is loaded correctly for memory-source forms.
- memory destination data is stored correctly for memory-destination forms.
- pending register writeback is staged for register-destination forms.
- architectural register state does not change before the commit boundary.
- architectural register state changes at the commit boundary.
- final register values match expected MOV results.
- final memory values match expected MOV results.
- final EIP reflects `M_NEXT_EIP`.
- next instruction fetch begins from the expected post-MOV address.
- generic microsequencer behavior required by Rung 6 is functioning without hidden MOV execution.
- EFLAGS remain unchanged by MOV.
- phase-1 MOV fault behavior matches Appendix D.
- Rung 5 INT, IRET, and #UD behavior remains passing.

Rung 6 must not claim broader ISA coverage beyond the frozen MOV gate.

---

## Unsupported-form expectations

Rung 6 must preserve bounded unsupported behavior.

Unsupported or out-of-scope forms must not partially execute, update registers, update flags, update stack state, update memory, or redirect architectural control flow outside the existing bounded unsupported / #UD path.

Examples of unsupported forms include:

```text
MOV Sreg, r/m
MOV r/m, Sreg
MOV control/debug/test register forms
MOVS string forms
XCHG
LEA
ALU operations
operand-size or address-size behavior not required by Appendix D Rung 6
protected-mode-only behavior
```

If unsupported-form testing reveals that an adjacent encoding falls through into incorrect execution, fix only the bounded classification/rejection path needed for Rung 6. Do not implement the broader instruction.

---

## Register-state guardrail

Rung 6 introduces or completes architectural GPR writeback behavior for MOV.

The design must keep clear separation between:

- decoded register metadata
- source register metadata
- destination register metadata
- pending writeback metadata
- staged writeback value
- architectural register-file state
- debug/testbench observability

Architectural GPR state must become visible only when the commit path publishes it.

A testbench may observe internal pending state, but internal pending state must not be treated as architectural state.

If the current implementation lacks a clean architectural GPR storage or debug surface, add the smallest bounded surface needed to prove Rung 6. Do not redesign the full register-file architecture beyond the Appendix D MOV requirements.

---

## Flag-state guardrail

Rung 6 MOV behavior must not update FLAGS.

No Rung 6 MOV instruction may alter condition flags, IF, TF, or any accepted Rung 5 flag behavior.

Rung 6 verification must explicitly prove that EFLAGS are unchanged by MOV.

If a proposed implementation requires flags changes, classify that as out of scope and stop.

---

## Stack-state guardrail

Rung 6 MOV behavior must not add stack semantics.

Ordinary MOV memory access may address any test memory location required by the MOV matrix, including locations that numerically overlap a stack area in a test. That does not authorize stack instruction behavior.

No Rung 6 MOV instruction may implement new stack semantics, interrupt-frame behavior, CALL/RET stack behavior, PUSH/POP behavior, or modify accepted Rung 5 INT/IRET stack behavior.

If a proposed implementation requires new stack behavior, classify that as out of scope and stop.

---

## CS / segment guardrail

Rung 6 MOV behavior must not add segment-register semantics.

No Rung 6 MOV instruction may change CS, DS, ES, FS, GS, SS, descriptor state, or protected-mode segment behavior.

The existing Rung 5 CS/IP behavior for INT and IRET must remain intact.

If Appendix D-required MOV memory addressing needs a bounded existing real-mode address assumption, implement only the minimum required for the frozen Rung 6 MOV proof. Do not add protected-mode segment semantics.

If a proposed implementation requires segment-register MOV, descriptor validation, or protected-mode segment behavior, classify that as out of scope and stop.

---

## Microsequencer guardrail

Rung 6 may require extending `microsequencer.sv` to support generic Appendix C microinstructions that were not needed in earlier rungs.

Allowed microsequencer changes:

```text
generic Appendix C-defined behavior required by Rung 6
bounded EXTRACT behavior for Rung 6-required metadata fields
bounded condition-code evaluation required by Rung 6 microcode
bounded LOADI behavior if required by Rung 6 microcode
generic UOP_MOV register-to-register microinstruction support if Pass 1 selects that path for register-transfer behavior
bounded STAGE_GPR microinstruction support if Pass 1 selects that path for register-write staging
```

Alternative service-based paths that may be selected by Pass 1:

```text
STORE_REG_META service-based staging instead of STAGE_GPR microinstruction support
service-based register-transfer path instead of generic UOP_MOV register-to-register microinstruction support
```

Forbidden microsequencer changes:

```text
x86 MOV opcode execution in microsequencer.sv
instruction-specific MOV policy hidden inside microsequencer.sv
broad implementation of all unused Appendix C features without Rung 6 need
future-rung ALU or flag behavior
direct architectural GPR publication outside commit ownership
decode of x86 instruction bytes inside microsequencer.sv
unnamed substitute mechanisms not tied to Appendix A/B/C or an existing live service path
```

The microsequencer executes microinstructions. It must not become an instruction executor.

Do not use the phrase “equivalent” to authorize an unnamed mechanism. Any alternative to `STAGE_GPR` or `UOP_MOV` must be named, tied to Appendix A/B/C or an existing live service path, and confirmed in Pass 1 before implementation.

---

## Minimum implementation surfaces

Rung 6 may require bounded changes in:

```text
rtl/core/decoder.sv
rtl/core/microsequencer.sv
rtl/core/commit_engine.sv
rtl/core/cpu_top.sv
rtl/core/services/fetch_engine.sv
rtl/core/services/operand_engine.sv
rtl/core/services/service_dispatch.sv
rtl/core/services/ea_calc.sv
rtl/core/services/load_store.sv
rtl/core/reg_file.sv
microcode/src/entries/entry_mov.uasm
microcode/src/entries/*.uasm
microcode/src/shared/*.uasm
microcode/src/ucode_main.uasm
scripts/ucode_build.py
Appendix A codegen source, if required and already authorized by frozen spec
code generator script, if required to emit already-authorized Appendix A data
Makefile
sim/tb/tb_rung6_mov_imm.sv
sim/tb/tb_rung6_mov_reg.sv
sim/tb/tb_rung6_mov_mem.sv
sim/tb/tb_rung6_mov_flags.sv
```

File names may differ in the current repository. Touch only files directly required for the bounded Rung 6 proof.

Do not edit generated files under:

```text
build/
```

Do not manually edit generated RTL/package/microcode outputs.

Do not perform a broad microcode-generation refactor as part of Rung 6.

Do not update broad project documentation until implementation and verification facts exist.

---

## Acceptance criteria

Rung 6 is not complete until all of the following are true:

- Rung 5 acceptance baseline is confirmed.
- approved ao486 donor alignment is checked, or an explicitly approved replacement semantic reference is recorded.
- decode covers `88/89/8A/8B/C6/C7/B0-BF`.
- `M_OPCODE_CLASS` is correct for all required MOV classes.
- `M_NEXT_EIP` is correct for all required MOV forms.
- required MOV register metadata fields are available through approved codegen/source workflow.
- `ENTRY_MOV` microcode is complete for the frozen Rung 6 MOV scope.
- `ENTRY_MOV` behavior is represented consistently in `.uasm` source and `scripts/ucode_build.py`.
- actual live ROM dispatch address for `ENTRY_MOV` is recorded.
- immediate fetch variants required by MOV are implemented and routed.
- `FETCH_IMM8`, `FETCH_IMM16`, and `FETCH_IMM32` behave correctly for MOV immediates.
- displacement fetch variants required by MOV are implemented.
- `EA_CALC_16` and `EA_CALC_32` are implemented and routed for MOV memory operands.
- `LOAD_RM8/16/32` and `STORE_RM8/16/32` are implemented and routed for MOV.
- `LOAD_REG_META` and `STORE_REG_META` are implemented and routed for MOV.
- service_dispatch routing for all MOV-required services is confirmed.
- operand_engine / load_store ownership overlap, if present, is resolved and documented.
- `M_` / `MF_` naming-layer mapping is confirmed and does not produce duplicate inconsistent constants.
- Appendix C example addresses are not treated as literal unless confirmed by the live builder.
- Gap 14 microsequencer and `ucode_build.py` blockers are resolved for all Rung 6-required microinstructions.
- `UOP_EXTRACT` supports the Rung 6-required metadata extraction behavior without becoming instruction-specific MOV logic.
- required Rung 6 condition-code handling is implemented only as generic Appendix C microinstruction behavior.
- required Rung 6 staging behavior is implemented through either `STAGE_GPR` microinstruction support or `STORE_REG_META` service-based staging, as selected and justified by Pass 1.
- register-to-register MOV transfer behavior is implemented through either generic `UOP_MOV` register-to-register microinstruction support or a service-based register-transfer path, as selected and justified by Pass 1.
- `UOP_COMMIT` and `UOP_CLEAR_FAULT` are either proven required and implemented within Rung 6 scope, or classified as out of scope by Pass 1 and left unimplemented.
- microsequencer changes preserve Rung 5 regression.
- full 8-register architectural register-file behavior is proven.
- register-destination MOV commits only through the intended commit boundary.
- memory-destination MOV uses the selected Appendix B-consistent store visibility path.
- MOV reg, reg passes all 8 register combinations and all 3 widths.
- MOV reg, imm passes all registers and all widths.
- MOV reg, [mem] passes all widths and all Appendix D-required addressing modes.
- MOV [mem], reg passes all widths and all Appendix D-required addressing modes.
- MOV [mem], imm passes required immediate-to-memory forms.
- unsupported adjacent forms remain bounded.
- register writeback is staged before commit.
- architectural register visibility occurs only through commit.
- memory writes occur only through the intended load/store and bus path.
- final EIP is correct for each tested instruction length.
- MOV behavior does not update FLAGS.
- MOV behavior does not add stack semantics.
- MOV behavior does not add segment-register or protected-mode semantics.
- phase-1 MOV fault behavior matches Appendix D.
- registered stage handoff / bubble / `SR_WAIT` behavior is preserved.
- Rung 0 through Rung 5 regressions still pass.
- Rung 6 regression passes.
- generated artifacts are current if generation is required.
- known implementation gaps in this file are resolved, explicitly deferred as non-completion blockers, or superseded by live-source facts recorded in verification.
- verification documentation records actual command results.
- documentation claims do not exceed tested behavior.
- working tree state is understood and recorded.

A completion claim is invalid unless based on actual command results from the committed candidate state.

---

## Validation expectations

Minimum validation before claiming Rung 6 complete:

```text
make codegen
make ucode
make rung5-regress
make rung6-regress
git diff --check
```

`make rung6-regress` must include, directly or indirectly:

```text
make rung5-regress
make rung6-mov-reg-reg-sim
make rung6-mov-reg-imm-sim
make rung6-mov-reg-mem-sim
make rung6-mov-mem-reg-sim
make rung6-mov-mem-imm-sim
make rung6-flags-unchanged-sim
```

Target names may differ, but the regression coverage must prove the full Appendix D MOV matrix.

The verification record must be created only after actual runs and must include:

- exact commit under test
- working tree status
- exact commands run
- actual pass/fail results
- testbench names
- selected instruction forms proven
- MOV matrix coverage proven
- Appendix D-required addressing modes proven
- unsupported forms tested
- EFLAGS unchanged result
- phase-1 MOV fault behavior result
- `M_NEXT_EIP` result
- `FETCH_IMM8` / `FETCH_IMM16` / `FETCH_IMM32` result
- service_dispatch routing result for MOV-required services
- operand_engine / load_store routing decision, if applicable
- `.uasm` / `ucode_build.py` consistency result
- actual `ENTRY_MOV` live ROM dispatch address
- Appendix C example-address treatment
- `M_` / `MF_` naming-layer mapping
- Appendix C pseudo-instruction support status in `ucode_build.py`
- microsequencer condition-code support used by ENTRY_MOV
- microsequencer UOP support used by ENTRY_MOV
- `UOP_EXTRACT` behavior used for `M_OPCODE_CLASS` and MOV metadata fields
- selected GPR staging path: `STAGE_GPR` microinstruction support or `STORE_REG_META` service-based staging
- selected register-transfer path: generic `UOP_MOV` register-to-register microinstruction support or service-based register-transfer path
- `UOP_COMMIT` / `UOP_CLEAR_FAULT` classification and implementation status
- `ucode_build.py` helper/constant support for ENTRY_MOV
- confirmation that microsequencer changes did not move MOV semantics into RTL
- registered stage handoff / bubble / `SR_WAIT` result
- semantic donor material used or unavailable
- generated-artifact status
- known implementation gap status
- memory-destination visibility path selected and proven
- ENTRY_MOV dispatch mechanism used
- explicit non-scope
- known limitations
- confirmation that Rung 5 remains passing

The expected verification file is:

```text
docs/implementation/rung6_verification.md
```

---

## Testbench expectations

Rung 6 testbenches should directly observe the frozen MOV slice.

For immediate-to-register MOV, the testbench should observe:

- reset and initial state
- instruction fetch sequence
- opcode byte consumption
- immediate byte consumption
- immediate byte/word/dword assembly in little-endian order
- `FETCH_IMM8` zero-extension behavior for byte-register immediate forms
- `FETCH_IMM16` behavior for word immediate forms
- `FETCH_IMM32` behavior for dword immediate forms
- decoded MOV class
- selected destination register
- assembled immediate value
- `M_NEXT_EIP`
- staged register writeback
- no early architectural register visibility
- commit-time architectural register visibility
- expected final EIP
- expected final register value
- EFLAGS unchanged
- preservation of prior Rung 5 behavior through regression

Note: specific microsequencer-internal observations required by Gap 14 microinstruction extensions, such as `EXTRACT`, condition evaluation, `LOADI`, `UOP_MOV`, or `STAGE` behavior, must be determined from Pass 1’s Gap 14 classification before testbench design for those items begins. Do not invent testbench observability requirements before Pass 1 identifies which generic microinstruction behavior is actually required.

For register-to-register MOV, the testbench should observe:

- ModRM byte consumption
- `ModRM.mod = 11`
- correct source register selection
- correct destination register selection
- all required register combinations
- all required widths
- `M_NEXT_EIP`
- no early architectural register visibility
- commit-time architectural register visibility
- EFLAGS unchanged

For memory-source MOV, the testbench should observe:

- ModRM byte consumption
- displacement byte consumption where applicable
- `M_NEXT_EIP`
- effective-address calculation
- memory read request
- memory read data capture
- selected destination register
- staged register writeback
- commit-time architectural register visibility
- expected final EIP
- expected final register value
- EFLAGS unchanged

For memory-destination MOV, the testbench should observe:

- ModRM byte consumption
- displacement byte consumption where applicable
- `M_NEXT_EIP`
- effective-address calculation
- selected source register or immediate value
- memory write request
- memory write data
- memory write width
- expected final EIP
- expected final memory value
- EFLAGS unchanged
- selected memory-store visibility path

Testbenches must not claim broader ISA coverage than the exact Appendix D Rung 6 MOV forms tested.

---

## Documentation expectations

Rung 6 implementation may require bounded updates to:

```text
README.md
docs/overview/bootstrap_status.md
docs/overview/roadmap.md
sim/README.md
docs/process/rung_execution_and_acceptance.md
docs/process/tooling_and_observability_policy.md
docs/process/dev_environment.md
docs/implementation/coding_rules/source_of_truth.md
```

Do not update these preemptively.

Documentation updates should occur only after implementation and verification facts exist.

Do not rewrite Rung 5 acceptance or verification records.

Do not alter frozen specs unless a separate protected-file review explicitly authorizes a specific change.

If any protected documentation appears stale or conflicting, stop and report the exact issue before editing.

---

## Code comment expectations

Rung 6 code should be understandable to a human maintainer.

Add concise comments where behavior is non-obvious, especially around:

- MOV opcode classification
- `M_OPCODE_CLASS`
- `M_NEXT_EIP`
- immediate assembly
- `FETCH_IMM8` zero-extension versus displacement sign-extension
- `FETCH_IMM16` / `FETCH_IMM32` byte assembly
- displacement assembly
- ModRM interpretation
- destination register metadata
- source register metadata
- operand width metadata
- effective-address calculation
- service_dispatch routing for MOV-required services
- operand_engine / load_store ownership decision, if applicable
- `.uasm` / `ucode_build.py` consistency
- `M_` / `MF_` naming-layer mapping where relevant
- actual live ROM dispatch address if visible in generated/debug output
- generic microinstruction support added for Rung 6
- EXTRACT, condition-code, LOADI, MOV micro-op, or STAGE behavior added for Rung 6
- selected GPR staging path: `STAGE_GPR` microinstruction support or `STORE_REG_META` service-based staging
- selected register-transfer path: generic `UOP_MOV` register-to-register microinstruction support or service-based register-transfer path
- memory load/store sequencing
- pending writeback staging
- commit-time register publication
- memory-store visibility path for memory-destination MOV
- EFLAGS unchanged behavior
- phase-1 MOV fault-path structure
- unsupported adjacent MOV rejection
- testbench-only observability

Comments should explain ownership and intent. They should not claim broader architectural coverage than implemented.

Do not use comments to justify scope creep. If behavior is not required by frozen specs or this active rung file, classify it as out of scope instead of implementing and commenting it.

---

## Stop conditions

Stop and report before proceeding if Rung 6 appears to require:

- approved ao486 semantic donor material is unavailable for final MOV semantic alignment or Rung 6 completion.
- proposed implementation depends on same-cycle combinational reach-through or zero-bubble bypassing across a documented stage boundary.
- memory-destination MOV requires a new architectural ownership rule, new frozen-spec field, or broad commit redesign.
- the candidate memory-destination visibility path cannot be reconciled with Appendix B, Appendix D, source-of-truth docs, or the current load/store/bus path.
- ENTRY_MOV microinstruction implementation — see Gap 14 — requires extending `microsequencer.sv` or `scripts/ucode_build.py` in a way that is not consistent with Appendix C, Appendix B ownership rules, or the current Rung 6 scope.
- microsequencer.sv begins executing MOV opcode semantics instead of generic Appendix C microinstructions.
- `UOP_EXTRACT`, `UOP_LOADI`, `UOP_MOV`, condition-code handling, `STAGE_GPR`, `UOP_COMMIT`, or `UOP_CLEAR_FAULT` support is implemented more broadly than the active Rung 6 pass requires.
- `scripts/ucode_build.py` encodes ENTRY_MOV behavior that has no Appendix C / `.uasm` counterpart and no documented current-builder justification.
- ENTRY_MOV is added only to `.uasm` source without an equivalent `scripts/ucode_build.py` ROM encoding update.
- ENTRY_MOV is added only to `scripts/ucode_build.py` without a corresponding `.uasm` review-source update.
- implementation treats Appendix C example uPC addresses as literal without confirming the live dispatch table.
- implementation mixes `M_` and `MF_` extract-field naming conventions within the same layer or creates duplicate constants with inconsistent values.
- implementation assumes Appendix C pseudo-instructions such as `WIDTH_DISPATCH` or `ADDR_DISPATCH` exist as Python builder helpers without confirming `ucode_build.py` support.
- implementation uses an unnamed “equivalent” mechanism instead of selecting and documenting a named Appendix A/B/C-defined microinstruction or live service path.
- MOV-required services are left routed to default/no-engine paths.
- LOAD_RM behavior is split across operand_engine and load_store without a documented bounded ownership rule.
- FETCH_IMM16 or FETCH_IMM32 is required by an implemented pass but not available or routed.
- codegen synchronization would require adding a field or enum not already defined by frozen Appendix A.
- MOV to/from segment registers.
- MOV to/from control/debug/test registers.
- string MOVS.
- ALU operations.
- flags updates.
- flags-production behavior.
- stack behavior beyond accepted Rung 5 paths and ordinary MOV memory access.
- protected-mode behavior.
- descriptor validation.
- privilege checks.
- task gates.
- PIC/APIC behavior.
- INT3.
- INTO.
- nested exceptions.
- double faults.
- generalized exception handling beyond MOV-required unsupported handling and Appendix D fault-path structure.
- new frozen-spec fields.
- Appendix A/B/C/D changes.
- broad microcode-generation refactor.
- generated artifact manual edits.
- broad source-of-truth rewrite.
- changes to Rung 5 acceptance or verification records.
- broad README or overview rewrite before verification facts exist.
- future-rung implementation hidden inside MOV support.
- reliance on inferred intent instead of frozen specs, active rung scope, or approved donor material.
- bypassing protected-file controls, Git hooks, CI checks, branch protections, or repository guardrails.
- live-source facts contradict a candidate resolution path in this document and the contradiction cannot be resolved without changing protected authority.

Do not silently expand Rung 6.

---

## Work classification rule

Before editing files, classify each planned change as one of:

```text
Required blocker
  Explicitly required by frozen specifications or this active rung file.

Required acceptance cleanup
  Needed so documentation, source-of-truth records, generated artifacts, or verification evidence accurately match actual tested behavior.

Candidate implementation path requiring confirmation
  A bounded proposed way to satisfy a required blocker, but not itself frozen authority.
  Must be confirmed against live source, frozen specs, coding rules, and process docs before implementation.

Out of scope
  Useful, plausible, architecturally desirable, or suggested by inspiration/reference material, but not explicitly required by frozen specifications or this active rung file.
```

Only required blockers, required acceptance cleanup, and confirmed candidate implementation paths may be implemented.

Out-of-scope work must not be implemented as part of Rung 6.

Known implementation gaps listed in this file are required blockers, stop conditions, required design decisions, or candidate implementation paths until the live branch proves otherwise.

---

## What this rung is not

Rung 6 is not:

- a general data-movement implementation beyond Appendix D MOV
- a segment-register MOV implementation
- a control/debug/test-register MOV implementation
- a string MOVS implementation
- an ALU rung
- a flags-production rung
- a protected-mode rung
- a generalized exception rung
- a performance optimization rung
- a cleanup rung
- a future-rung preparation pass
- a z8086 clone
- an ao486 pipeline import
- an opportunity to move instruction semantics into RTL
- an opportunity to bypass documented stage handoff or bubble behavior for speed
- an opportunity to hide known blockers outside the active rung directive
- permission to treat reviewer-proposed implementation details as frozen authority without Pass 1 confirmation
- permission to invent microcode syntax, service routing, commit behavior, codegen fields, ROM build behavior, microsequencer instruction-policy behavior, or unnamed alternative staging mechanisms

Rung 6 exists to prove the frozen MOV gate cleanly: bounded MOV decode, immediate/displacement fetch, effective-address support required by MOV, register metadata, load/store behavior, architectural register writeback, memory write behavior, phase-1 MOV fault-path discipline, EFLAGS preservation, and registered stage handoff discipline through the existing staged microcoded architecture.

---

## Handoff rule for this rung

Any handoff for Rung 6 must report:

- current branch
- current commit
- working tree status
- files changed
- protected files changed, if explicitly authorized
- exact instruction forms implemented
- exact Appendix D MOV coverage remaining
- exact commands run
- exact pass/fail results
- generated-artifact status
- verification-document status
- z8086 structural-template relevance, if any
- ao486 semantic donor material used or missing
- known implementation gap status
- candidate implementation paths confirmed, rejected, or still requiring owner decision
- memory-destination visibility-path decision
- ENTRY_MOV dispatch mechanism
- FETCH_IMM8 / FETCH_IMM16 / FETCH_IMM32 status
- service_dispatch routing status
- operand_engine / load_store ownership decision, if applicable
- `.uasm` / `ucode_build.py` consistency status
- actual `ENTRY_MOV` live ROM dispatch address
- Appendix C example-address treatment
- `M_` / `MF_` extract-field naming-layer mapping
- Appendix C pseudo-instruction support status in `ucode_build.py`
- Gap 14 microsequencer / `ucode_build.py` status
- condition-code support added or confirmed
- UOP support added or confirmed
- EXTRACT support added or confirmed
- STAGE_GPR vs STORE_REG_META staging decision
- UOP_MOV register-to-register vs service-based register-transfer decision
- UOP_COMMIT / UOP_CLEAR_FAULT classification
- confirmation that microsequencer remains generic microinstruction execution, not MOV execution
- stage handoff / bubble model status
- work classification decisions
- known limitations
- whether Rung 5 regression remains passing
- whether Rung 6 is ready for review or still blocked

Do not claim Rung 6 completion without committed implementation, passing full Appendix D MOV verification, semantic-donor alignment or approved replacement reference, generated-artifact status, stage-handoff/bubble-model status, known-gap resolution status, working-tree status, and an actual `docs/implementation/rung6_verification.md` record.

---

## Summary

Rung 6 is the frozen MOV register and memory data-movement rung.

The preferred first implementation slice is:

```text
B8+rd id      MOV r32, imm32
```

That first slice is not the final acceptance scope.

The final Rung 6 acceptance scope is the full Appendix D MOV gate:

```text
88 /r
89 /r
8A /r
8B /r
C6 /0
C7 /0
B0-BF
```

The two project inspirations must be used only as the frozen specs intend:

```text
z8086 = structural template / architectural inspiration
ao486 = semantic corpus / instruction-behavior donor
```

Rung 5 is the local implementation pattern: explicit microcode sequencing, bounded RTL services, registered stage handoffs, bubbles/holds where required, and commit-visible architectural effects.

The known implementation gaps are part of this active bounded directive until resolved:

```text
ao486 MOV donor material absent or unconfirmed
architectural GPR register file incomplete or unconfirmed
EA_CALC_16 / EA_CALC_32 missing or unconfirmed
LOAD_RM* / STORE_RM* / register metadata services missing or unconfirmed
Rung 6 Make targets missing or unconfirmed
MOV opcode-class and register metadata constants missing or unconfirmed
memory-destination MOV visibility path unresolved
MOV decode absent or unconfirmed
ENTRY_MOV microcode absent or unconfirmed
Rung 5 acceptance baseline must be confirmed
FETCH_IMM16 / FETCH_IMM32 missing or unconfirmed
service_dispatch routing for MOV-required services missing or unconfirmed
operand_engine / load_store ownership overlap unresolved
.uasm / ucode_build.py dual-source workflow unresolved or unconfirmed
M_ / MF_ extract-field naming-layer mapping unconfirmed
actual ENTRY_MOV live ROM dispatch address unconfirmed
Appendix C example-address treatment unconfirmed
microsequencer.sv microinstruction and condition-code implementation gaps missing or unconfirmed: general EXTRACT, LOADI, MOV register-to-register, C_T0Z/C_T0NZ, C_W8/C_W16/C_W32, C_ADDR16/C_ADDR32, general STAGE_GPR behavior, UOP_COMMIT, and UOP_CLEAR_FAULT
```

Some concrete resolution paths in this file are candidate implementation paths derived from review. They must be confirmed during Pass 1 before implementation. They are not frozen-spec authority unless the authority chain supports them.

The explicit concerns that must not be guessed are:

```text
memory-destination MOV visibility before/at ENDI
ENTRY_MOV opcode-class dispatch mechanics
service_dispatch / operand_engine / load_store ownership
FETCH_IMM16 / FETCH_IMM32 availability
codegen synchronization versus field invention
.uasm source versus ucode_build.py live ROM encoding
Appendix C pseudo-instruction support in the Python builder
Appendix C example addresses versus live ROM addresses
M_ versus MF_ naming-layer conventions
microsequencer / ucode_build.py support for Appendix C microinstructions without turning microsequencer.sv into a hidden MOV executor
unnamed “equivalent” mechanisms that are not tied to Appendix A/B/C or an existing live service path
```

The architectural point of Rung 6 is not uncontrolled MOV breadth. The point is proving the frozen MOV set through the same ownership model already established for earlier control-transfer and interrupt rungs.

Keep it bounded. Keep it staged. Keep instruction sequencing in microcode. Keep RTL as bounded reusable services. Preserve registered stage handoffs. Allow bubbles. Treat `SR_WAIT` as a real hold, not completion. Preserve `M_NEXT_EIP` correctness. Keep architectural register visibility at commit. Keep memory effects on the intended load/store path. Resolve memory-destination visibility explicitly. Preserve phase-1 MOV fault discipline. Prove EFLAGS unchanged. Resolve known blockers before claiming completion.
