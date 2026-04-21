# Keystone86 / Aegis — Rung 3 Bring-Up Scope

## Goal

Establish the first clean **service-oriented near CALL/RET path** as the foundation for later stack-touching and conditional control-transfer rungs.

Rung 3 proves that near CALL and near RET can move end-to-end through the intended staged architecture:

1. `decoder` classifies the in-scope CALL/RET forms and emits decode-owned metadata
2. the active fetch/service path acquires any displacement or immediate payload required by the active slice
3. the active stack/service path performs the minimum push/pop work required by the active slice
4. `microsequencer` sequences those services and waits correctly
5. `commit_engine` makes the control transfer and stack-visible architectural result real only at ENDI

This rung is intentionally narrow. It exists to prove the CALL/RET service path and module ownership boundaries, not to optimize or broaden coverage beyond the bounded Rung 3 objective.

## Required reading and precedence

Read these before changing RTL, microcode, testbenches, or Make targets for this rung:

1. `docs/process/developer_directive.md`
2. `docs/process/developer_handoff_contract.md`
3. `docs/implementation/coding_rules/source_of_truth.md`
4. `docs/spec/frozen/appendix_d_bringup_ladder.md`
5. this file: `docs/implementation/bringup/rung3.md`

Precedence on conflict:

1. `docs/spec/frozen/appendix_d_bringup_ladder.md`
2. `docs/implementation/coding_rules/source_of_truth.md`
3. `docs/process/developer_directive.md`
4. `docs/process/developer_handoff_contract.md`
5. this bring-up document

This file is a bounded bring-up scope note. It does not replace the documents above it.

## Authority and usage

This is a **bring-up scope document**.

It is:
- a bounded implementation-intent note for Rung 3
- subordinate to the required reading chain above
- the baseline alignment document for corrective Rung 3 refactor work

It is not:
- the final verification record
- the sole authority for implementation
- permission to widen scope by interpretation
- permission to change file roles or invent new deliverables
- a file-by-file patch list for the current repo state

Verification results do not belong in this file. Record actual run results in:

- `docs/implementation/rung3_verification.md`

## Exact scope source

For exact instruction forms, required services, and rung gate criteria, use:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

This file describes intent and boundaries for Rung 3 implementation. It does not replace the exact rung content defined there.

This rung document must not be used to infer additional instruction coverage beyond what Appendix D explicitly assigns to Rung 3 and what the active regression for Rung 3 is intended to prove.

## Design intent

Rung 3 is where the project must prove the first clean **stack-touching control-transfer slice** beyond the Rung 2 near-JMP baseline.

The intended ownership is:

- **decoder**: classification and decode-owned metadata only
- **fetch/service path**: displacement / immediate acquisition required by the active CALL/RET slice
- **stack/service path**: minimum push/pop behavior required by the active CALL/RET slice
- **microsequencer**: service issue, wait behavior, and microcode control flow
- **commit_engine**: architectural EIP / ESP visibility, committed redirect, and commit-visible stack result at ENDI

No module should absorb another module’s responsibility just because a shortcut appears convenient.

Rung 3 is not complete because decode entries exist. Rung 3 is complete only when the active CALL/RET slice works behaviorally as an integrated system.

This document is intended to reset the developer onto the authoritative Rung 3 design path. It should be used to bring implementation back into alignment with frozen spec and current directives, not to preserve drifted behavior because it already exists in the repo.

## Stage-boundary expectations

Rung 3 should preserve clear stage boundaries.

Where a signal represents a real stage handoff, preserved metadata item, service result, stack result, or commit-visible decision, it **must** remain explicitly latched or registered at the boundary unless the controlling documents clearly define a different behavior.

Do not replace clear stage handoff points with broad combinational reach-through paths just to make the active slice work. The point of this rung is to establish a clean foundation for later rungs, not a shortcut that blurs ownership.

Examples of boundaries that should remain explicit in this rung include:

- decoder-owned outputs handed to `microsequencer`
- service results handed back to `microsequencer`
- stack-related service results carried across the active path
- commit-visible CALL/RET information handed to `commit_engine`

This does not mean every local control signal must be registered. It means real stage outputs and handoff points must remain understandable, reviewable, and ownership-safe.

## Stage handoff model

Rung 3 follows a registered stage-to-stage handoff model.

For the active path in this rung:

- each stage performs only its intended work
- each stage registers or explicitly latches its output at the stage boundary
- the producing stage must hold that output stable until the receiving stage can accept it
- the producing stage must not discard, overwrite, or recompute that boundary output while acceptance is pending
- the receiving stage advances only when it can legally accept the handoff
- bubbles between stages are allowed
- correctness, ownership clarity, and reviewable handoff behavior take priority over zero-bubble execution

For service-oriented paths, `SR_WAIT` is the explicit hold condition. A stage or service that is not ready to hand off completion must hold its state and boundary outputs stable until the next stage or control owner can accept them.

Do not replace this model with broad combinational reach-through or same-cycle shortcutting that blurs stage ownership.

## Required implementation shape

### Decoder
- classify only the exact Rung 3 near CALL/RET forms required by `docs/spec/frozen/appendix_d_bringup_ladder.md`
- provide only decode-owned metadata
- do **not** compute the redirect target
- do **not** make architectural stack effects real
- do **not** absorb microcode/service policy just because CALL/RET touches both control flow and stack state

### Active fetch/service path
Implement only the displacement / immediate-fetch behavior required by the active Rung 3 CALL/RET slice.

Required active-path services are only the services explicitly required for Rung 3 by `docs/spec/frozen/appendix_d_bringup_ladder.md`.

Do not add broader fetch framework beyond what the bounded Rung 3 path genuinely needs.

### Active stack/service path
Implement only the push/pop behavior required by the active Rung 3 path.

That includes the minimum stack-touching behavior needed to prove:

- CALL pushes the correct return address
- RET restores control flow correctly
- `RET imm16` applies the required post-pop stack adjustment
- nested CALL/RET behavior returns correctly within the bounded acceptance cases

Do not turn this rung into a generalized stack-engine redesign beyond what the active slice genuinely needs.

### `microsequencer`
Implement the control path needed to:

- issue the required CALL/RET services
- remain in wait state correctly
- branch or advance only on valid service completion
- preserve the active CALL/RET handoff until ENDI completes
- return control to fetch/decode only after the Rung 3 path is complete

`SR_WAIT` is a true stall, not a terminal completion.

Do not use dispatch-time cleanup that breaks the active CALL/RET slice. Architectural visibility remains commit-visible at ENDI.

### `commit_engine`
Remain the sole owner of architecturally visible control-transfer and stack-visible commit result for the active Rung 3 path:

- commit EIP at ENDI
- commit the active stack-visible CALL/RET result at ENDI
- flush fetch through the commit-visible redirect path

Do not absorb decode classification, target computation, or broader policy into commit.

### `service_dispatch`
If service routing is required for the active Rung 3 path, it must remain pure routing and must not absorb service policy.

`service_dispatch` is a thin routing layer, not a pipeline stage in its own right unless a controlling document explicitly says otherwise. Registered or latched handoff boundaries belong in the producing service and consuming control owner, not in `service_dispatch` itself.

## Behavioral contract

Rung 3 must preserve these rules:

- CALL pushes the correct return address
- the pushed return address matches the correct next architectural EIP for the active CALL form
- ESP changes by the correct amount for the active CALL/RET form
- RET restores the correct control-flow destination
- `RET imm16` applies the required post-pop stack adjustment
- service wait behavior is real
- architectural redirect becomes real only at ENDI
- no stale abandoned-stream work may survive the committed redirect boundary
- decode, service, stack, sequencer, and commit-visible behavior must agree on the same architectural result

## Scope boundary

This rung should be expanded only enough to make the near CALL/RET slice function correctly end to end.

It does **not** authorize:

- generic framework work mainly for later rungs
- unrelated cleanup
- directory restructuring
- package/include cleanup unrelated to the active CALL/RET slice
- Makefile cleanup unrelated to the active CALL/RET slice
- debug-framework redesign
- Jcc bring-up
- broader branch/control-transfer work beyond the CALL/RET slice
- broad stack-engine redesign beyond what the active slice genuinely requires
- speculative future-rung preparation
- pre-implementation of Rung 4+ behavior

The phrase “minimum required surfaces” does **not** authorize general reusable infrastructure unless that infrastructure is genuinely required to make the bounded Rung 3 slice function correctly end to end.

If a proposed change appears to require broader scope than this rung defines, stop and escalate in the implementation handoff or review thread rather than silently absorbing that scope into code.

Do not treat current repo structure or current repo implementation as authority by itself. If existing behavior, comments, helper logic, or tests disagree with the controlling documents and bounded Rung 3 intent, the implementation must be brought back into alignment rather than the rung being widened to match drift.

## Acceptance intent

Rung 3 is only considered complete when:

- earlier baselines still pass
- the in-scope CALL/RET forms required by Appendix D work end to end
- the required stack effects are correct
- return flow is restored correctly
- the required microcode/control path completes correctly
- the commit-visible architectural result is correct
- actual required verification commands have been run
- actual results have been recorded in `docs/implementation/rung3_verification.md`

This document must not claim more instruction coverage than the implementation and regression have actually demonstrated.

## Validation

Run the project’s required Rung 3 verification commands against the delivered state and record the actual results before claiming completion.

The exact Rung 3 verification commands are defined by the current project regression targets and must be run against the delivered state.

At minimum, the active verification must prove the bounded Appendix D Rung 3 criteria for:

- CALL + RET pair correctness
- correct pushed return address
- correct ESP change for the active CALL/RET forms
- `RET imm16` stack-adjust correctness
- nested CALL/RET correctness within the bounded acceptance depth
- preserved earlier-rung baselines

Record the actual command lines and actual output in:

- `docs/implementation/rung3_verification.md`

## Code comment expectations

Rung 3 changes must include enough comments to preserve design intent and ownership boundaries.

Comments are required where they explain:

- what a changed module owns for this rung
- what it must not own
- why a boundary exists at this stage
- why a stall, flush, squash, push, pop, or service wait occurs where it does
- why behavior is intentionally **not** implemented in another module
- why a stage handoff is latched or preserved as a registered boundary

Do not return straight code with no explanation of the active-path decisions.

At minimum, changed RTL and microcode files should include:

- a short module or file header describing the Rung 3 responsibility of that file
- comments on non-obvious control-flow decisions
- comments where ownership boundaries matter
- comments where a developer might otherwise “simplify” the code in a way that violates this rung’s intent

Examples of places that require comments in this rung include:

- service wait / `SR_WAIT` handling
- return-address capture and lifetime
- push/pop lifetime and stack-adjust timing
- redirect visibility at ENDI
- flush / cleanup timing
- why decoder does not compute the final target
- why commit does not absorb broader policy
- why a boundary output is registered or latched at a given stage handoff

Comments should be concise and technical. They should explain intent and boundaries, not restate obvious syntax.

## What this rung is not

Rung 3 is **not**:

- a generalized framework rung for later features
- permission to move target computation into `decoder`
- permission to move validation or broader policy into `commit_engine`
- permission to widen into Jcc or later-rung control-transfer behavior
- permission to redesign stack architecture beyond what the active CALL/RET slice requires
- permission to claim instruction forms that are not actually proven by regression

## Handoff rule for this rung

Do not label Rung 3 as passing, complete, fixed, or ready unless the required commands were actually run against the delivered state and the actual results were recorded.