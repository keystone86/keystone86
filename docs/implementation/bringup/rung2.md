# Keystone86 / Aegis — Rung 2 Bring-Up Scope

## Goal

Establish the first clean **service-oriented direct control-transfer path** as the foundation for later rungs.

Rung 2 proves that a direct JMP instruction can move end-to-end through the intended staged architecture:

1. `decoder` classifies the instruction form and emits decode-owned metadata
2. `fetch_engine` acquires the displacement payload
3. `flow_control` computes and validates the redirect target
4. `microsequencer` sequences those services and waits correctly
5. `commit_engine` makes the redirect architecturally visible at ENDI and flushes fetch

This rung is intentionally narrow. It exists to prove the control-transfer service path and module ownership boundaries, not to optimize or broaden coverage beyond the bounded Rung 2 objective.

## Required reading and precedence

Read these before changing RTL, microcode, testbenches, or Make targets for this rung:

1. `docs/process/developer_directive.md`
2. `docs/process/developer_handoff_contract.md`
3. `docs/implementation/coding_rules/source_of_truth.md`
4. `docs/spec/frozen/appendix_d_bringup_ladder.md`
5. this file: `docs/implementation/bringup/rung2.md`

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
- a bounded implementation-intent note for Rung 2
- subordinate to the required reading chain above

It is not:
- the final verification record
- the sole authority for implementation
- permission to widen scope by interpretation
- permission to change file roles or invent new deliverables

Verification results do not belong in this file. Record actual run results in:

- `docs/implementation/rung2_verification.md`

## Exact scope source

For exact instruction forms, required services, and rung gate criteria, use:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

This file describes intent and boundaries for Rung 2 implementation. It does not replace the exact rung content defined there.

This rung document must not be used to infer additional instruction coverage beyond what Appendix D explicitly assigns to Rung 2 and what the active regression for Rung 2 is intended to prove.

## Design intent

Rung 2 is where the project must stop relying on front-end shortcuts and instead prove the staged service path that later rungs build on.

The intended ownership is:

- **decoder**: classification and decode-owned metadata only
- **fetch_engine**: displacement fetch services
- **flow_control**: relative-target computation and near-transfer validation
- **microsequencer**: service issue, wait behavior, and microcode control flow
- **commit_engine**: architectural EIP visibility and redirect flush at ENDI

No module should absorb another module’s responsibility just because a shortcut appears convenient.

## Stage-boundary expectations

Rung 2 should preserve clear stage boundaries.

Where a signal represents a real stage handoff, preserved metadata item, service result, or commit-visible decision, it **must** remain explicitly latched or registered at the boundary unless the controlling documents clearly define a different behavior.

Do not replace clear stage handoff points with broad combinational reach-through paths just to make the active slice work. The point of this rung is to establish a clean foundation for later rungs, not a shortcut that blurs ownership.

Examples of boundaries that should remain explicit in this rung include:

- decoder-owned outputs handed to `microsequencer`
- service results handed back to `microsequencer`
- metadata carried across the active service path
- commit-visible redirect information handed to `commit_engine`

This does not mean every local control signal must be registered. It means real stage outputs and handoff points must remain understandable, reviewable, and ownership-safe.

## Stage handoff model

Rung 2 follows a registered stage-to-stage handoff model.

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
- classify the exact Rung 2 direct JMP forms required by `docs/spec/frozen/appendix_d_bringup_ladder.md` to `ENTRY_JMP_NEAR`
- provide only decode-owned metadata
- do **not** compute the redirect target
- do **not** consume displacement bytes that belong to the fetch service path

### `fetch_engine`
Implement the displacement-fetch behavior required by the active Rung 2 path.

Required active-path services are only the services explicitly required for Rung 2 by `docs/spec/frozen/appendix_d_bringup_ladder.md`.

Do not add broader fetch framework beyond what the bounded Rung 2 path genuinely needs.

### `flow_control`
Implement the target-computation and near-transfer-validation behavior required by the active Rung 2 path.

Do not move this behavior into decoder, commit, or unrelated helper logic.

### `microsequencer`
Implement the control path needed to:
- issue the required services
- remain in wait state correctly
- branch or advance only on valid service completion
- return control to fetch/decode only after the Rung 2 path is complete

`SR_WAIT` is a true stall, not a terminal completion.

Do not use dispatch-time cleanup that breaks displacement fetch. Redirect remains commit-visible at ENDI.

### `commit_engine`
Remain the sole owner of architecturally visible redirect:
- commit EIP at ENDI
- flush fetch through the commit-visible redirect path

Do not absorb target computation or transfer validation into commit.

### `service_dispatch`
If service routing is required for the active Rung 2 path, it must remain pure routing and must not absorb service policy.

`service_dispatch` is a thin routing layer, not a pipeline stage in its own right unless a controlling document explicitly says otherwise. Registered or latched handoff boundaries belong in the producing service and consuming control owner, not in `service_dispatch` itself.

## Behavioral contract

Rung 2 must preserve these rules:

- displacement fetch remains alive long enough to complete
- service wait behavior is real
- target compute and validate occur in their intended owner
- redirect becomes architecturally real only at ENDI
- no stale abandoned-stream work may survive the committed redirect boundary

## Scope boundary

This rung should be expanded only enough to make the direct-JMP slice function correctly end to end.

It does **not** authorize:
- generic framework work mainly for later rungs
- moving target computation into decoder
- moving validation into commit
- widening into CALL / RET / Jcc behavior
- broader cleanup beyond what the active Rung 2 path genuinely requires

The phrase “minimum required surfaces” does **not** authorize general reusable infrastructure unless that infrastructure is genuinely required to make the bounded Rung 2 slice function correctly end to end.

If a proposed change appears to require broader scope than this rung defines, stop and escalate in the implementation handoff or review thread rather than silently absorbing that scope into code.

## Acceptance intent

Rung 2 is only considered complete when:

- earlier baselines still pass
- the direct-JMP service path works end to end
- wait semantics are correct
- redirect is committed only at ENDI
- flush occurs from the commit boundary
- actual required verification commands have been run
- actual results have been recorded in `docs/implementation/rung2_verification.md`

This document must not claim more instruction coverage than the implementation and regression have actually demonstrated.

## Validation

Run the project’s required Rung 2 verification commands against the delivered state and record the actual results before claiming completion.

The exact Rung 2 verification commands are defined by the current project regression targets and must be run against the delivered state.

Record the actual command lines and actual output in:

- `docs/implementation/rung2_verification.md`

## Code comment expectations

Rung 2 changes must include enough comments to preserve design intent and ownership boundaries.

Comments are required where they explain:
- what a changed module owns for this rung
- what it must not own
- why a boundary exists at this stage
- why a stall, flush, squash, or service wait occurs where it does
- why behavior is intentionally **not** implemented in another module
- why a stage handoff is latched or preserved as a registered boundary

Do not return straight code with no explanation of the active-path decisions.

At minimum, changed RTL and microcode files should include:
- a short module or file header describing the Rung 2 responsibility of that file
- comments on non-obvious control-flow decisions
- comments where ownership boundaries matter
- comments where a developer might otherwise “simplify” the code in a way that violates this rung’s intent

Examples of places that require comments in this rung include:
- service wait / `SR_WAIT` handling
- displacement fetch lifetime
- redirect visibility at ENDI
- flush / cleanup timing
- why decoder does not compute the target
- why commit does not absorb target computation or validation
- why a boundary output is registered or latched at a given stage handoff

Comments should be concise and technical. They should explain intent and boundaries, not restate obvious syntax.

## What this rung is not

Rung 2 is **not**:
- a fetch-local direct-follow optimization rung
- a generalized framework rung for later features
- permission to move target computation into decoder
- permission to move validation into commit
- permission to widen into later-rung control-transfer behavior
- permission to claim instruction forms that are not actually proven by regression

## Handoff rule for this rung

Do not label Rung 2 as passing, complete, fixed, or ready unless the required commands were actually run against the delivered state and the actual results were recorded.