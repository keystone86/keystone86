# Keystone86 / Aegis — Rung 4 Bring-Up Scope

## Goal

Establish the first clean **conditional control-transfer path** for short Jcc as the bounded foundation for later control-flow expansion.

Rung 4 proves that short conditional branches can move end to end through the intended staged architecture:

1. `decoder` classifies the in-scope short Jcc forms and emits decode-owned condition metadata
2. the active path preserves the bounded short-displacement and condition metadata required by the active slice
3. `flow_control` performs the bounded `CONDITION_EVAL` work required to determine taken vs not-taken from the relevant architectural flags
4. `microsequencer` sequences that path and waits correctly where required
5. `commit_engine` makes the architectural EIP result real only at ENDI, with redirect visibility only for taken branches

This rung is intentionally narrow. It exists to prove the short Jcc service/control path and module ownership boundaries, not to optimize or broaden coverage beyond the bounded Rung 4 objective.

## Required reading and precedence

Read these before changing RTL, microcode, testbenches, or Make targets for this rung:

1. `docs/process/developer_directive.md`
2. `docs/process/developer_handoff_contract.md`
3. `docs/process/rung_execution_and_acceptance.md`
4. `docs/process/tooling_and_observability_policy.md`
5. `docs/implementation/coding_rules/source_of_truth.md`
6. `docs/implementation/coding_rules/review_checklist.md`
7. `docs/spec/frozen/appendix_d_bringup_ladder.md`
8. this file: `docs/implementation/bringup/rung4.md`

Precedence on conflict:

1. `docs/spec/frozen/appendix_d_bringup_ladder.md`
2. `docs/implementation/coding_rules/source_of_truth.md`
3. `docs/process/developer_directive.md`
4. `docs/process/developer_handoff_contract.md`
5. `docs/process/rung_execution_and_acceptance.md`
6. `docs/process/tooling_and_observability_policy.md`
7. `docs/implementation/coding_rules/review_checklist.md`
8. this bring-up document

This file is a bounded bring-up scope note. It does not replace the documents above it.

## Authority and usage

This is a **bring-up scope document**.

It is:
- a bounded implementation-intent note for Rung 4
- subordinate to the required reading chain above
- the baseline alignment document for corrective Rung 4 bring-up work

It is not:
- the final verification record
- the sole authority for implementation
- permission to widen scope by interpretation
- permission to change file roles or invent new deliverables
- a file-by-file patch list for the current repo state

Verification results do not belong in this file. Record actual run results in:

- `docs/implementation/rung4_verification.md`

## Exact scope source

For exact instruction forms, required services, and rung gate criteria, use:

- `docs/spec/frozen/appendix_d_bringup_ladder.md`

This file describes intent and boundaries for Rung 4 implementation. It does not replace the exact rung content defined there.

This rung document must not be used to infer additional instruction coverage beyond what Appendix D explicitly assigns to Rung 4 and what the active regression for Rung 4 is intended to prove.

For Rung 4 specifically, Appendix D is the exact source for the bounded build obligations, including:

- `70h`–`7Fh` decode to `ENTRY_JCC`
- `M_COND_CODE = opcode & 0x0F`
- `flow_control: CONDITION_EVAL`
- `ENTRY_JCC` microcode complete

These exact bounded obligations must not be replaced by “equivalent” interpretations that widen ownership or execution shape.

## Design intent

Rung 4 is where the project must prove the first clean **flag-driven conditional branch slice** beyond the unconditional redirect baseline already established earlier.

The intended ownership is:

- **decoder**: classification and decode-owned condition metadata only
- **active path**: preservation of bounded displacement and condition metadata required by the active short Jcc slice
- **`flow_control`**: taken / not-taken decision from the relevant architectural flags through the bounded `CONDITION_EVAL` path
- **microsequencer**: service issue, wait behavior, and control sequencing
- **commit_engine**: architectural EIP visibility, committed redirect for taken Jcc, and correct fall-through architectural result for not-taken Jcc at ENDI

No module should absorb another module’s responsibility just because a shortcut appears convenient.

Rung 4 is not complete because short Jcc decode entries exist. Rung 4 is complete only when the active short Jcc slice works behaviorally as an integrated system.

This document is intended to keep the developer on the authoritative Rung 4 design path. It should be used to bring implementation into alignment with frozen spec and current directives, not to preserve drifted behavior because it already exists in the repo.

## Stage-boundary expectations

Rung 4 should preserve clear stage boundaries.

Where a signal represents a real stage handoff, preserved metadata item, service result, condition result, or commit-visible decision, it **must** remain explicitly latched or registered at the boundary unless the controlling documents clearly define a different behavior.

Do not replace clear stage handoff points with broad combinational reach-through paths just to make the active slice work. The point of this rung is to establish a clean foundation for later conditional-control work, not a shortcut that blurs ownership.

Examples of boundaries that should remain explicit in this rung include:

- decoder-owned condition metadata handed to `microsequencer`
- bounded displacement or service results handed back to `microsequencer`
- `flow_control` condition-evaluation results handed back to the active control owner
- commit-visible Jcc information handed to `commit_engine`

This does not mean every local control signal must be registered. It means real stage outputs and handoff points must remain understandable, reviewable, and ownership-safe.

## Stage handoff model

Rung 4 follows a registered stage-to-stage handoff model.

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
- classify only the exact short Jcc forms required by `docs/spec/frozen/appendix_d_bringup_ladder.md`
- classify `70h`–`7Fh` as `ENTRY_JCC`
- provide only decode-owned metadata
- provide the correct condition-code identity for the active opcode
- provide `M_COND_CODE = opcode[3:0]` for the active short Jcc form
- provide the correct next architectural EIP for the short Jcc form
- do **not** evaluate the condition itself
- do **not** compute the final taken target as an architectural commit decision
- do **not** make architectural control-transfer effects real

### Active path
Implement only the bounded displacement and metadata handling required by the active short Jcc slice.

Required active-path services and metadata are only the services and metadata explicitly required for Rung 4 by `docs/spec/frozen/appendix_d_bringup_ladder.md`.

Do not add broader fetch framework beyond what the bounded Rung 4 path genuinely needs.

### `flow_control`
Implement only the bounded condition evaluation needed for the active short Jcc slice.

That includes the minimum support needed to prove:

- each of the 16 short Jcc opcodes maps to the correct architectural condition
- taken vs not-taken is decided from the correct architectural flags
- the taken decision and not-taken decision remain distinguishable all the way to commit-visible resolution
- the bounded `CONDITION_EVAL` result is handed back cleanly to the active control owner
- taken-path validation remains limited to the active phase-1 near-transfer rule required by Appendix D

Do not turn this rung into a broader flags-production redesign or a generalized branch-predication framework.

### `microsequencer`
Implement the control path needed to:

- issue the required short Jcc services
- remain in wait state correctly where required
- branch or advance only on valid service or condition completion
- preserve the active Jcc handoff until ENDI completes
- return control to fetch/decode only after the Rung 4 path is complete

`SR_WAIT` is a true stall, not a terminal completion.

Do not use dispatch-time cleanup that breaks the active Jcc slice. Architectural visibility remains commit-visible at ENDI.

### `commit_engine`
Remain the sole owner of architecturally visible control-transfer result for the active Rung 4 path:

- commit EIP at ENDI
- apply a committed redirect only for taken Jcc
- preserve correct fall-through architectural EIP for not-taken Jcc
- flush fetch only through the commit-visible redirect path when the branch is taken

Do not absorb decode classification, condition evaluation, or broader policy into commit.

### `service_dispatch`
If service routing is required for the active Rung 4 path, it must remain pure routing and must not absorb service or branch policy.

`service_dispatch` is a thin routing layer, not a pipeline stage in its own right unless a controlling document explicitly says otherwise. Registered or latched handoff boundaries belong in the producing service and consuming control owner, not in `service_dispatch` itself.

## Behavioral contract

Rung 4 must preserve these rules:

- each short Jcc opcode maps to the correct architectural condition
- the condition is evaluated against the correct architectural flag state
- taken Jcc applies the correct signed 8-bit displacement from the correct next architectural EIP
- not-taken Jcc falls through to the correct next architectural EIP
- EIP is correct for both taken and not-taken outcomes
- forward and backward short displacements work correctly within the bounded proof cases
- service wait behavior is real where required
- architectural redirect becomes real only at ENDI
- no stale abandoned-stream work may survive the committed redirect boundary
- decode, condition-evaluation, control, microcode, and commit-visible behavior must agree on the same architectural result
- taken-path validation remains bounded to the active phase-1 rule: a taken Jcc may fault only through the required near-transfer validation path, while a not-taken Jcc must not enter taken-path transfer validation

## Scope boundary

This rung should be expanded only enough to make the short Jcc slice function correctly end to end.

It does **not** authorize:

- generic framework work mainly for later rungs
- unrelated cleanup
- directory restructuring
- package/include cleanup unrelated to the active short Jcc slice
- Makefile cleanup unrelated to the active short Jcc slice
- debug-framework redesign
- near/long Jcc expansion beyond the in-scope short forms
- LOOP / LOOPE / LOOPNE / JCXZ family bring-up
- INT / IRET bring-up
- broad flags redesign beyond what the active short Jcc slice genuinely requires
- speculative future-rung preparation
- pre-implementation of Rung 5+ behavior
- inventing a new Jcc execution path outside `ENTRY_JCC`, `flow_control: CONDITION_EVAL`, and the bounded commit-visible result

The phrase “minimum required surfaces” does **not** authorize general reusable infrastructure unless that infrastructure is genuinely required to make the bounded Rung 4 slice function correctly end to end.

If a proposed change appears to require broader scope than this rung defines, stop and escalate in the implementation handoff or review thread rather than silently absorbing that scope into code.

Do not treat current repo structure or current repo implementation as authority by itself. If existing behavior, comments, helper logic, or tests disagree with the controlling documents and bounded Rung 4 intent, the implementation must be brought back into alignment rather than the rung being widened to match drift.

## Acceptance intent

Rung 4 is only considered complete when:

- earlier baselines still pass
- the in-scope short Jcc forms required by Appendix D work end to end
- all 16 architectural conditions are represented correctly
- taken and not-taken behavior is correct for the required proof cases
- signed 8-bit displacement handling is correct
- the required microcode/control path completes correctly
- the commit-visible architectural result is correct
- actual required verification commands have been run
- actual results have been recorded in `docs/implementation/rung4_verification.md`

This document must not claim more instruction coverage than the implementation and regression have actually demonstrated.

## Validation

Run the project’s required Rung 4 verification commands against the delivered state and record the actual results before claiming completion.

The exact Rung 4 verification commands are defined by the current project regression targets and must be run against the delivered state.

At minimum, the active verification must prove the bounded Appendix D Rung 4 criteria for:

- each of the 16 short Jcc conditions in a taken case
- each of the 16 short Jcc conditions in a not-taken case
- signed 8-bit displacement correctness
- forward short-branch correctness
- backward short-branch correctness
- fall-through correctness for not-taken Jcc
- taken-path-only validation behavior required by Appendix D
- preserved earlier-rung baselines

Record the actual command lines and actual output in:

- `docs/implementation/rung4_verification.md`

## Code comment expectations

Rung 4 changes must include enough comments to preserve design intent and ownership boundaries.

Comments are required where they explain:

- what a changed module owns for this rung
- what it must not own
- why a boundary exists at this stage
- why a stall, flush, squash, or condition decision occurs where it does
- why behavior is intentionally **not** implemented in another module
- why a stage handoff is latched or preserved as a registered boundary

Do not return straight code with no explanation of the active-path decisions.

At minimum, changed RTL and microcode files should include:

- a short module or file header describing the Rung 4 responsibility of that file
- comments on non-obvious control-flow decisions
- comments where ownership boundaries matter
- comments where a developer might otherwise “simplify” the code in a way that violates this rung’s intent

Examples of places that require comments in this rung include:

- condition-code capture and lifetime
- taken / not-taken decision lifetime
- service wait / `SR_WAIT` handling
- displacement lifetime and sign handling
- redirect visibility at ENDI
- flush / cleanup timing for taken branches
- why decoder does not evaluate the final condition
- why `flow_control` owns bounded `CONDITION_EVAL`
- why commit does not absorb broader policy
- why a boundary output is registered or latched at a given stage handoff

Comments should be concise and technical. They should explain intent and boundaries, not restate obvious syntax.

## What this rung is not

Rung 4 is **not**:

- a generalized framework rung for later features
- permission to move condition evaluation into `decoder`
- permission to move validation or broader policy into `commit_engine`
- permission to widen into near/long Jcc or later-rung control-transfer behavior
- permission to redesign flags architecture beyond what the active short Jcc slice requires
- permission to claim instruction forms that are not actually proven by regression

## Handoff rule for this rung

Do not label Rung 4 as passing, complete, fixed, or ready unless the required commands were actually run against the delivered state and the actual results were recorded.
