# Keystone86 / Aegis — Rung 5 Bring-Up Scope

## Purpose

This file defines the functional scope and proof target for Rung 5 bring-up.

Read `docs/process/developer_directive.md` first.

That directive defines the general development rules for this project, including scope control, handoff requirements, validation discipline, anti-drift expectations, and required reading.

This file defines **what Rung 5 is**, **what it must prove**, and **what remains out of scope**.

Rung 5 must use the stable patterns established by Rung 3 and Rung 4:

- Rung 3 established service-oriented CALL/RET stack/control-transfer discipline.
- Rung 4 established bounded semantic-helper discipline through `CONDITION_EVAL`, where RTL computes a named primitive result but microcode still owns instruction sequencing.
- Rung 5 must preserve those boundaries while adding the first interrupt-entry, interrupt-return, and fault-delivery slice.

---

## Rung 5 intent

Rung 5 is the INT / IRET / real-mode fault-delivery bring-up rung.

It is the first rung that must prove real-mode interrupt entry and interrupt return as an integrated architectural control-transfer and stack-state slice.

Rung 5 builds directly on:

- the Rung 2 committed redirect / prefetch-flush baseline
- the Rung 3 CALL/RET stack-visible commit baseline
- the Rung 4 microcode-controlled condition/service-result discipline

Rung 5 is functional implementation work, not cleanup.

Rung 5 must be treated as a **complete integrated slice**, not as isolated opcode recognition. The rung is only complete when decode, immediate fetch, interrupt entry, interrupt return, microcode sequencing, fault delivery, stack-visible behavior, flag behavior, and commit-visible EIP/CS/FLAGS behavior work together.

---

## Required reading and precedence

Read these before changing RTL, microcode, testbenches, or Make targets for this rung:

1. `docs/process/developer_directive.md`
2. `docs/process/developer_handoff_contract.md`
3. `docs/process/rung_execution_and_acceptance.md`
4. `docs/process/tooling_and_observability_policy.md`
5. `docs/implementation/coding_rules/source_of_truth.md`
6. `docs/implementation/coding_rules/review_checklist.md`
7. `docs/spec/frozen/appendix_a_field_dictionary.md`
8. `docs/spec/frozen/appendix_b_ownership_matrix.md`
9. `docs/spec/frozen/appendix_d_bringup_ladder.md`
10. this file: `docs/implementation/bringup/rung5.md`

Precedence on conflict:

1. frozen specs under `docs/spec/frozen/`
2. `docs/implementation/coding_rules/source_of_truth.md`
3. process docs under `docs/process/`
4. this bring-up document

This file is a bounded bring-up scope note. It does not replace the documents above it.

---

## Authority and usage

This is a **bring-up scope document**.

It is:

- a bounded implementation-intent note for Rung 5
- subordinate to the required reading chain above
- the baseline alignment document for Rung 5 implementation and review
- a guardrail against hidden RTL instruction execution, broad exception-system expansion, and future-rung drift

It is not:

- the final verification record
- the sole authority for implementation
- permission to widen scope by interpretation
- permission to change file roles or invent new deliverables
- permission to implement protected-mode interrupt semantics
- permission to redesign flags, stack, fetch, bus, or exception architecture beyond the bounded Rung 5 slice
- a file-by-file patch list for the current repo state

Verification results do not belong in this file. Record actual run results in:

- `docs/implementation/rung5_verification.md`

---

## Exact scope source

For exact instruction forms, required services, and rung gate criteria, use:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

This file describes intent and boundaries for Rung 5 implementation. It does not replace the exact rung content defined there.

This rung document must not be used to infer additional instruction coverage beyond what Appendix D explicitly assigns to Rung 5 and what the active regression for Rung 5 is intended to prove.

---

## In scope

Rung 5 covers the minimum integrated functional slice needed to prove real-mode INT / IRET and fault delivery.

That includes:

- decoder support for `CD imm8` → `ENTRY_INT`
- decoder support for `CF` → `ENTRY_IRET`
- immediate fetch support required for `INT imm8`
- bounded `INT_ENTER` support needed by the Rung 5 real-mode interrupt-entry path
- bounded `IRET_FLOW` support needed by the Rung 5 real-mode interrupt-return path
- `ENTRY_INT` microcode complete for the in-scope `INT imm8` form
- `ENTRY_IRET` microcode complete for the in-scope `IRET` form
- `SUB_FAULT_HANDLER` microcode complete enough to deliver `#UD` for unknown opcode through the same bounded `INT_ENTER` path
- commit-visible EIP / CS / FLAGS behavior needed to prove interrupt entry and return
- stack-visible behavior needed to prove FLAGS, CS, and IP are pushed and popped in the correct architectural order
- IF clearing on interrupt entry
- FLAGS restoration on IRET
- required proof behavior for:
  - `INT imm8`
  - `IRET`
  - `INT 0x21` round trip with a trivial handler
  - `#UD` delivery for unknown opcode through `SUB_FAULT_HANDLER`

Rung 5 includes whatever narrowly scoped support is genuinely required to make that INT / IRET / fault-delivery slice function correctly end to end.

---

## Out of scope

Unless explicitly requested, Rung 5 does **not** include:

- unrelated cleanup
- directory restructuring
- package/include cleanup unrelated to INT/IRET bring-up
- Makefile cleanup unrelated to INT/IRET bring-up
- debug-framework redesign
- Python-generation cleanup unrelated to INT/IRET bring-up
- README modernization unrelated to the requested handoff
- `INT3` (`CC`)
- `INTO` (`CE`)
- two-byte or alternate interrupt forms beyond `CD imm8`
- protected-mode interrupt semantics
- IDT descriptor handling
- privilege checks
- task gates
- interrupt gates, trap gates, or descriptor validation
- page-fault delivery
- maskable external interrupt controller behavior
- PIC/APIC modeling
- STI/CLI instruction bring-up beyond the IF effects required inside INT/IRET
- broad EFLAGS redesign
- broad stack-engine redesign
- broad bus/memory subsystem redesign
- generalized exception framework beyond what is required for `SUB_FAULT_HANDLER` to deliver `#UD`
- nested exception handling
- double-fault behavior
- new fault classes beyond those required by the frozen Rung 5 scope
- Rung 6 MOV behavior
- Rung 7 ALU / flag-production behavior
- Rung 8 remaining instruction behavior
- speculative future-rung preparation
- generic framework work intended mainly for later rungs

Rung 5 should be expanded only enough to make the INT / IRET / fault-delivery system slice work and be provable.

---

## Architectural constraints

Rung 5 must preserve the frozen ownership boundaries.

In particular:

- decoder remains classification / byte-consumption logic
- decoder must not perform interrupt entry, IVT lookup, stack effects, flag changes, or control-transfer commit
- microsequencer remains control owner
- microcode must explicitly sequence the INT, IRET, and fault-delivery paths
- interrupt-related RTL services must remain bounded semantic primitives called by microcode
- helper RTL must not silently become a hidden instruction engine
- commit path remains the architectural visibility boundary
- stack-visible and flag-visible results become architectural only through the commit path
- fetch/prefetch redirection must occur only through committed control transfer
- important architectural distinctions between vector selection, fault state, stack data, CS/IP targets, FLAGS state, and commit outcome must not be collapsed into overloaded signals

Do not bypass architecture just to make a Rung 5 test pass.

If an apparent fix requires architectural boundary smearing, stop and surface that explicitly in the handoff.

---

## Hardware-helper guardrail

Rung 5 is allowed to add bounded RTL service helpers only when microcode explicitly calls them.

The desired model is:

```text
microcode calls a named semantic service
the service computes or stages bounded candidate results
microcode decides the next semantic step
commit makes the architectural result visible at ENDI
```

This is the same pattern proven by Rung 4:

```text
CONDITION_EVAL(cond_code, EFLAGS) -> T3
microcode branches on T3
commit publishes only the chosen architectural result
```

For Rung 5, acceptable bounded services include:

```text
INT_ENTER(vector, next_eip, flags, cs, fault_state) -> staged interrupt-entry effects
IRET_FLOW(stack state) -> staged return IP/CS/FLAGS effects
```

But those services must not become hidden opcode engines.

Good RTL service behavior:

- read the requested vector / stack state
- perform bounded real-mode IVT read or stack pop/push sequencing required by the service
- stage candidate IP/CS/FLAGS/ESP results
- report service status / fault status
- return explicit results to the microsequencer / commit path

Bad hidden RTL behavior:

- decoder sees `CD` or `CF` and directly mutates EIP, CS, FLAGS, or ESP
- interrupt service redirects fetch before microcode reaches ENDI
- interrupt service commits stack or flag state architecturally without commit control
- commit engine contains per-opcode INT/IRET semantics instead of generic commit actions
- fault delivery bypasses `SUB_FAULT_HANDLER` microcode
- helper logic decides broad exception policy not requested by Rung 5

---

## Pipeline and stage-boundary expectations

Rung 5 must preserve clear stage boundaries.

Where a signal represents a real stage handoff, preserved metadata item, service result, stack result, flag result, interrupt vector, fault vector, or commit-visible decision, it must remain explicitly latched or registered at the boundary unless the controlling documents clearly define a different behavior.

Do not replace clear stage handoff points with broad combinational reach-through paths just to make the active slice work.

Correctness, ownership clarity, and reviewable handoff behavior take priority over zero-bubble execution.

Examples of boundaries that should remain explicit in this rung include:

- decoder-owned outputs handed to `microsequencer`
- immediate/vector metadata for `INT imm8`
- committed or staged FLAGS values used by `INT_ENTER`
- staged IP/CS/FLAGS/ESP results from `INT_ENTER`
- staged IP/CS/FLAGS/ESP results from `IRET_FLOW`
- fault vector / fault class metadata handed to `SUB_FAULT_HANDLER`
- service results handed back to `microsequencer`
- commit-visible interrupt-entry and interrupt-return results handed to `commit_engine`

Do not let abandoned-stream work survive a committed interrupt redirect or IRET redirect.

Fetch/prefetch must be flushed only through the committed control-transfer path.

---

## Stage handoff model

Rung 5 follows a registered stage-to-stage handoff model.

For the active path in this rung:

- each stage performs only its intended work
- each stage registers or explicitly latches its output at the stage boundary
- the producing stage must hold that output stable until the receiving stage can accept it
- the producing stage must not discard, overwrite, or recompute that boundary output while acceptance is pending
- the receiving stage advances only when it can legally accept the handoff
- bubbles between stages are allowed
- `SR_WAIT` remains a true wait / hold condition, not a terminal completion
- service completion must be explicit before microcode advances
- commit-visible state changes must occur only at ENDI

Do not replace this model with broad combinational reach-through or same-cycle shortcutting that blurs stage ownership.

---

## Required implementation shape

### Decoder

Decoder must:

- classify only the exact Rung 5 forms required by `docs/spec/frozen/appendix_d_bringup_ladder.md`
- recognize `CD imm8` as `ENTRY_INT`
- recognize `CF` as `ENTRY_IRET`
- consume the opcode byte for `IRET`
- provide decode-owned metadata needed by the active path
- preserve stable `M_NEXT_EIP`
- for `INT imm8`, ensure the immediate vector is available to the active microcode/service path according to the selected implementation model

Decoder must not:

- perform IVT lookup
- push FLAGS / CS / IP
- pop IP / CS / FLAGS
- clear or restore IF
- compute final interrupt or return target policy
- commit EIP, CS, FLAGS, or ESP
- deliver faults by itself
- absorb `INT_ENTER` or `IRET_FLOW` behavior

### Fetch / immediate path

Rung 5 requires `FETCH_IMM8` support for `INT imm8`.

`FETCH_IMM8` must:

- provide the 8-bit interrupt vector to the active microcode/service path
- preserve correct `M_NEXT_EIP`
- use `SR_WAIT` if the byte is not yet available
- avoid treating a temporary queue-empty condition as architectural fault in phase 1
- remain a fetch/immediate service, not an interrupt policy owner

Do not broaden this into all future immediate fetch behavior unless genuinely required by the Rung 5 slice.

### Interrupt service path

`INT_ENTER` is the bounded interrupt-entry service required by Rung 5.

For the Rung 5 real-mode slice, `INT_ENTER` must support enough behavior to prove:

- vector selection from `INT imm8`
- vector selection from `SUB_FAULT_HANDLER` for `#UD`
- IVT lookup for the selected vector
- IVT vector entry interpreted as real-mode `offset:segment`
- FLAGS / CS / IP pushed in the correct architectural order
- IF cleared for the entered handler
- resulting CS:IP staged for commit
- stack-visible results staged for commit
- no architectural visibility before ENDI

`INT_ENTER` must not:

- implement protected-mode IDT semantics
- implement privilege checks
- implement descriptor validation
- implement external interrupt controller behavior
- commit architectural state directly
- bypass microcode or commit ownership

### IRET service path

`IRET_FLOW` is the bounded interrupt-return service required by Rung 5.

For the Rung 5 real-mode slice, `IRET_FLOW` must support enough behavior to prove:

- IP popped in correct architectural order
- CS popped in correct architectural order
- FLAGS popped in correct architectural order
- IF restored from popped FLAGS
- resulting IP/CS/FLAGS/ESP staged for commit
- no architectural visibility before ENDI

`IRET_FLOW` must not:

- implement protected-mode IRET semantics
- implement privilege checks
- implement task return behavior
- implement descriptor validation
- commit architectural state directly
- bypass microcode or commit ownership

### Microsequencer and microcode

Microsequencer / microcode must:

- dispatch `ENTRY_INT`
- dispatch `ENTRY_IRET`
- complete `ENTRY_INT` microcode for the in-scope `INT imm8` form
- complete `ENTRY_IRET` microcode for the in-scope `IRET` form
- complete `SUB_FAULT_HANDLER` microcode enough to deliver `#UD` via `INT_ENTER`
- issue the required services in the correct order
- branch to the fault handler on real service fault where required by Appendix D
- wait correctly on `SR_WAIT`
- preserve the active instruction/fault handoff until ENDI completes
- return control to fetch/decode only after the active path is complete

Microcode must remain the semantic path owner.

Do not move instruction sequencing into decoder, commit, or service helpers.

`SUB_FAULT_HANDLER` must remain a bounded Rung 5 fault-delivery path.

It must not become a generalized exception framework in this rung.

For Rung 5, `SUB_FAULT_HANDLER` is required only to deliver the in-scope `#UD` unknown-opcode case through `INT_ENTER` using vector `0x06`, plus any strictly required existing fault-path compatibility needed to preserve earlier rungs.

Do not add broad exception classification, nested exception handling, double-fault behavior, page-fault behavior, or protected-mode exception semantics.

### Commit engine

`commit_engine` must remain the sole owner of architecturally visible interrupt-entry and interrupt-return state.

For Rung 5, commit must make real at ENDI only:

- EIP / IP result
- CS result
- FLAGS result
- ESP result
- stack-visible committed results
- prefetch flush caused by committed control transfer
- fault-delivery result when `SUB_FAULT_HANDLER` enters the handler

Commit must not:

- classify INT or IRET
- perform IVT lookup
- perform stack push/pop sequencing by itself
- decide interrupt vector policy
- clear or restore IF outside the committed result path
- contain hidden per-opcode INT/IRET execution semantics
- redirect fetch before ENDI
- grow a family of commit-time opcode checks such as `is_int`, `is_iret`, or `is_fault` unless each one is strictly bounded, explicitly justified by Rung 5, and reviewed against the frozen ownership rules
- prefer opcode-specific commit policy when a generic commit mode/result handoff can express the same bounded behavior

### Service dispatch

If service routing is required for the active Rung 5 path, it must remain pure routing and must not absorb service policy.

`service_dispatch` is a thin routing layer, not a hidden pipeline stage or policy owner unless a controlling document explicitly says otherwise.

Registered or latched handoff boundaries belong in the producing service and consuming control owner, not in `service_dispatch` itself.

---

## Behavioral contract

Rung 5 must prove the following as one integrated system:

### `INT imm8`

- opcode `CD` is decoded as `ENTRY_INT`
- immediate byte is fetched as the interrupt vector
- IVT entry for the vector is used to form the handler CS:IP
- IVT vector entry is interpreted as real-mode `offset:segment`
- FLAGS, CS, and IP are pushed in the correct architectural order
- the pushed IP is the correct next architectural EIP for the `INT imm8` instruction
- IF is cleared for the handler
- ESP changes by the correct amount
- EIP and CS are committed to the handler target only at ENDI
- prefetch is flushed only through the committed interrupt-entry path

### `IRET`

- opcode `CF` is decoded as `ENTRY_IRET`
- IP, CS, and FLAGS are popped in the correct architectural order
- IF is restored from the popped FLAGS
- ESP changes by the correct amount
- EIP, CS, and FLAGS become architectural only at ENDI
- prefetch is flushed only through the committed interrupt-return path

### Width expectations

- push/pop width for IP, CS, and FLAGS must follow the frozen phase-1 real-mode expectation
- if the implementation finds ambiguity between current RTL width, frozen field names, and real-mode architectural width, stop and classify the issue before editing
- do not silently widen this rung into a 32-bit protected-mode interrupt or IRET implementation

### Round trip

- `INT 0x21` enters a trivial handler
- the trivial handler executes `IRET`
- original architectural state is restored as required by Rung 5
- no abandoned-stream work survives the committed INT or IRET redirect boundaries

### Fault delivery

- unknown opcode still enters `ENTRY_NULL`
- `ENTRY_NULL` raises `FC_UD`
- `SUB_FAULT_HANDLER` uses the same bounded `INT_ENTER` path to deliver vector `0x06`
- fault delivery commits the handler target at ENDI
- fault state is preserved long enough to drive delivery
- fault state is cleared only according to the commit/fault-delivery rules defined by the frozen specs and current implementation ownership

---

## Fault-ordering expectations

Rung 5 must follow Appendix D fault ordering.

For `INT`:

- `FETCH_IMM8` queue-empty behavior is wait, not architectural fault
- `INT_ENTER` IVT read may report `FC_GP`
- `INT_ENTER` stack push may report `FC_SS`
- phase-1 real-mode tests should succeed assuming valid memory

For `IRET`:

- `IRET_FLOW` stack reads may report `FC_SS`
- minimal CS validation may report `FC_GP`
- full protected-mode validation is out of scope

For unrecognized opcode:

- `ENTRY_NULL` raises `FC_UD`
- `SUB_FAULT_HANDLER` delivers vector `0x06` using `INT_ENTER`

Do not invent additional phase-1 fault behavior beyond the frozen Rung 5 requirements.

---

## Flag-state guardrail

Rung 5 is the first rung that must modify and restore FLAGS as part of interrupt semantics.

This does not authorize a broad flag-production redesign.

Rung 5 may add only the bounded flag support required to prove:

- `INT_ENTER` pushes the correct FLAGS image
- `INT_ENTER` clears IF in the handler FLAGS state
- `IRET_FLOW` restores FLAGS from the stack
- IF is restored by IRET
- unrelated FLAGS bits are preserved/restored according to the in-scope real-mode behavior

Do not implement ALU flag production, `FLAGS_FROM_T3`, `COMMIT_EFLAGS` for ALU, or broader flag instruction behavior in Rung 5.

Those belong to later rungs unless explicitly required by the frozen Rung 5 path.

---

## Stack-state guardrail

Rung 5 uses stack-visible behavior, but it is not a broad stack-engine redesign rung.

Rung 5 may add only the stack support needed to prove:

- INT pushes FLAGS / CS / IP in the required architectural order
- IRET pops IP / CS / FLAGS in the required architectural order
- ESP changes correctly
- stack-visible results become architectural only at commit

The testbench must verify both architectural order and memory layout of the interrupt frame, not only final ESP.

For INT entry, prove the pushed frame contains the expected FLAGS, CS, and IP values at the expected stack addresses according to the frozen phase-1 real-mode width expectation.

For IRET, prove the popped IP, CS, and FLAGS came from the expected stack addresses.

Do not implement broad PUSH/POP r/m coverage, general stack framework expansion, or future stack instructions beyond what the INT/IRET slice genuinely requires.

---

## CS / segment guardrail

Rung 5 must prove real-mode CS:IP control transfer for INT and IRET.

This may require bounded committed CS state support.

For the bounded Rung 5 real-mode proof, CS may be treated as committed architectural segment state required for visible CS:IP correctness.

Do not add general segment-base, descriptor-cache, hidden-segment-register, or protected-mode address-translation behavior unless the frozen specs explicitly require it for Rung 5.

If physical address formation from CS:IP is ambiguous in the current RTL, stop and classify the issue before editing.

It does not authorize:

- protected-mode segment descriptor loading
- limit checking beyond the frozen phase-1 Rung 5 requirement
- privilege checks
- far CALL/JMP
- task switching
- generalized segment register architecture beyond what the Rung 5 slice needs

Any new CS path must be narrow, explicit, and commit-visible only at ENDI.

---

## Minimum implementation surfaces

The exact RTL changes are determined by the current repo state, but Rung 5 should be expected to touch only the surfaces genuinely needed for the INT / IRET / fault-delivery slice.

That may include:

- decoder classification for `CD` and `CF`
- vector/immediate metadata generation or transport for `INT imm8`
- `FETCH_IMM8` support
- bounded interrupt-entry service support
- bounded interrupt-return service support
- microsequencer control flow for `ENTRY_INT`, `ENTRY_IRET`, and `SUB_FAULT_HANDLER`
- commit-visible EIP / CS / FLAGS / ESP support required for architectural correctness
- targeted prefetch flush handling required by committed INT/IRET redirects
- stack-visible support required for the bounded INT/IRET slice
- testbench and Makefile support needed to prove the active rung
- `docs/implementation/rung5_verification.md` after actual verification runs

These surfaces are in scope only to the extent required to make Rung 5 function correctly as a system.

Do not broaden implementation beyond what these behaviors require.

---

## Acceptance criteria

Rung 5 is ready for review only when all of the following are true:

- `CD imm8` is implemented as the in-scope `INT imm8` form
- `CF` is implemented as the in-scope `IRET` form
- required decode support is correct
- `FETCH_IMM8` support required by `INT imm8` is correct
- `INT_ENTER` support required by the Rung 5 real-mode path is correct
- `IRET_FLOW` support required by the Rung 5 real-mode path is correct
- `ENTRY_INT` microcode completes correctly
- `ENTRY_IRET` microcode completes correctly
- `SUB_FAULT_HANDLER` delivers `#UD` through the bounded `INT_ENTER` path
- FLAGS / CS / IP are pushed in correct order on INT
- INT stack-frame memory layout is verified at the expected stack addresses
- IP / CS / FLAGS are popped in correct order on IRET
- IRET source stack-frame memory layout is verified at the expected stack addresses
- push/pop width for IP, CS, and FLAGS follows the frozen phase-1 real-mode expectation, or any ambiguity is surfaced before implementation proceeds
- IF is cleared on INT entry
- IF is restored by IRET
- EIP / CS / FLAGS / ESP are commit-visible only at ENDI
- prefetch/control-transfer behavior is correct for INT and IRET
- `INT 0x21` round trip with trivial handler restores the required architectural state
- direct IRET behavior, if tested, is not treated as a substitute for INT-entered round-trip proof
- unknown opcode delivers `#UD` correctly through vector `0x06`
- `SUB_FAULT_HANDLER` remains a bounded `#UD` delivery path and does not become a generalized exception framework
- `INT3` (`CC`) and `INTO` (`CE`) remain unsupported unless explicitly brought into scope by frozen spec update or a later rung
- preserved baseline behavior from earlier rungs remains intact
- required proof cases have been run
- actual verification results are reported in `docs/implementation/rung5_verification.md`

Rung 5 is not complete until the integrated INT / IRET / fault-delivery slice works together and is proven.

---

## Validation expectations

Use the validation and handoff rules from `docs/process/developer_directive.md`.

Where applicable, validation for Rung 5 should include:

- required generation steps for local-only generated artifacts
- targeted INT / IRET proof cases
- targeted fault-delivery proof cases
- broader regression checks needed to show preserved baseline behavior still holds

Typical prerequisite steps may include:

- `make codegen`
- `make ucode`

The Rung 5 regression target should include or invoke the verified/documented Rung 4 regression path so that the full Rung 0 through Rung 4 baseline chain remains proven while Rung 5 is added.

Typical proof should include:

- `INT imm8` enters the correct handler from the IVT
- IVT vector entry is interpreted as real-mode `offset:segment`
- FLAGS / CS / IP are pushed in correct order and verified in stack memory
- IF is cleared after INT entry
- `IRET` pops IP / CS / FLAGS in correct order and from expected stack memory
- IF is restored after IRET
- `INT 0x21` round trip with trivial handler restores required state
- direct IRET behavior, if tested, remains supplemental rather than the main acceptance proof
- unknown opcode raises `#UD`
- `SUB_FAULT_HANDLER` delivers `#UD` through vector `0x06`
- prefetch flush occurs on committed INT/IRET redirects
- `INT3` (`CC`) and `INTO` (`CE`) remain unsupported
- earlier Rung 0 through Rung 4 regressions remain passing

Report only what actually ran.

---

## Testbench expectations

Rung 5 testbench work should prove the real path, not bypass it.

A Rung 5 testbench may initialize memory, IVT entries, handler bytes, stack contents, and reset-state assumptions needed for the bounded real-mode proof.

It must not prove Rung 5 by directly forcing final EIP, CS, FLAGS, ESP, stack results, or commit outcomes.

Acceptable testbench setup examples:

- initialize IVT entry for vector `0x21`
- place a trivial `IRET` handler at the IVT target
- initialize stack memory with an IRET frame for direct IRET tests
- initialize memory so unknown opcode delivery vector `0x06` has a valid handler target

Unacceptable testbench shortcuts:

- force committed EIP to the handler target
- force committed CS after INT entry
- force committed FLAGS after IRET
- bypass `INT_ENTER`
- bypass `IRET_FLOW`
- bypass `SUB_FAULT_HANDLER`
- inspect only final state without proving the intermediate required service/microcode path was exercised

A direct IRET frame test is allowed, but it is not sufficient by itself.

Rung 5 acceptance must include an INT-entered handler that returns through IRET, and a `#UD` fault-delivery case that reaches the handler through `SUB_FAULT_HANDLER`.

Where practical, tests should observe that the required services were issued and that ENDI was the commit-visible boundary.

---

## Code comment expectations

Rung 5 changes must include enough comments to preserve design intent and ownership boundaries.

Comments are required where they explain:

- what a changed module owns for this rung
- what it must not own
- why a boundary exists at this stage
- why a stall, wait, flush, stack push/pop, IVT read, flag update, or service completion occurs where it does
- why behavior is intentionally not implemented in another module
- why a stage handoff is latched or preserved as a registered boundary
- why a helper is a bounded service rather than a hidden instruction engine

Do not return straight code with no explanation of the active-path decisions.

At minimum, changed RTL and microcode files should include:

- a short module or file header describing the Rung 5 responsibility of that file
- comments on non-obvious interrupt/fault control-flow decisions
- comments where ownership boundaries matter
- comments where a developer might otherwise “simplify” the code in a way that violates this rung’s intent

Examples of places that require comments in this rung include:

- `FETCH_IMM8` wait behavior
- vector lifetime
- FLAGS image selection for INT push
- IF clear timing
- IRET FLAGS restore timing
- IP/CS/FLAGS stack order
- IVT read ownership
- real-mode `offset:segment` IVT interpretation
- phase-1 IP/CS/FLAGS width choice
- why `INT3` and `INTO` remain unsupported
- `SUB_FAULT_HANDLER` use of `INT_ENTER`
- why `SUB_FAULT_HANDLER` remains bounded to Rung 5 `#UD` delivery
- fault-state lifetime
- redirect visibility at ENDI
- prefetch flush timing
- why decoder does not perform interrupt entry
- why commit does not absorb broader policy
- why interrupt services do not directly commit architectural state
- why opcode-specific commit checks were avoided or, if present, why they are strictly bounded to Rung 5
- why direct IRET tests are supplemental and do not replace INT-entered round-trip proof

Comments should be concise and technical. They should explain intent and boundaries, not restate obvious syntax.

---

## What this rung is not

Rung 5 is **not**:

- a generalized exception architecture rung
- a protected-mode interrupt rung
- an IDT/descriptor validation rung
- an `INT3` or `INTO` rung
- a PIC/APIC/external interrupt rung
- a general FLAGS redesign rung
- a general stack redesign rung
- a MOV rung
- an ALU rung
- permission to move interrupt entry into decoder
- permission to move interrupt return into commit
- permission to make `interrupt_engine` a hidden instruction engine
- permission to claim instruction forms or exception behavior not actually proven by regression

---

## Handoff rule for this rung

Do not label Rung 5 as passing, complete, fixed, accepted, or ready for review unless the required commands were actually run against the delivered state and the actual results were recorded.

Every handoff must include:

- `Status: READY FOR REVIEW` or `Status: NOT READY FOR REVIEW`
- base commit used
- changed/new file manifest
- exact verification commands run
- actual results
- explicit unresolved blockers
- explicit deferred items
- confirmation that Rung 6 remains blocked until Rung 5 is accepted

Do not send a full repo snapshot unless explicitly requested.

For normal work, send only:

- modified files
- newly created files

Optionally, include a zip containing only changed/new files with repo-relative paths preserved.

---

## Summary

Rung 5 is the INT / IRET / real-mode fault-delivery bring-up rung.

Its job is to prove correct bounded real-mode interrupt entry, interrupt return, and `#UD` fault delivery through the intended microcoded/service-oriented architecture.

Rung 5 must preserve the established model:

```text
decoder classifies and captures metadata
microcode sequences the instruction/fault path
RTL services perform bounded semantic primitives
commit makes architectural state visible only at ENDI
fetch is redirected only by committed control transfer
```

The rung is complete only when `INT imm8`, `IRET`, `INT 0x21` round trip, and `#UD` delivery work as an integrated system while preserving earlier rung baselines and avoiding unrelated expansion.
