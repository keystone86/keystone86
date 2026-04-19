# Keystone86 / Aegis — Rung 2 Implementation Note

## Purpose

This note records what the delivered Rung 2 implementation does in the current bounded scope.

It is subordinate to:

1. `docs/spec/frozen/appendix_d_bringup_ladder.md`
2. `docs/implementation/coding_rules/source_of_truth.md`
3. `docs/process/developer_directive.md`
4. `docs/process/developer_handoff_contract.md`
5. `docs/implementation/bringup/rung2.md`

This file is descriptive. It does not widen scope and it does not replace the controlling documents above.

## Rung 2 implementation intent actually delivered

The delivered Rung 2 path proves the first clean service-oriented direct control-transfer slice for direct JMP bring-up.

The active path is:

1. `decoder` classifies the in-scope direct JMP form and emits decode-owned metadata
2. `fetch_engine` fetches the displacement payload needed by the active path
3. `flow_control` computes and validates the redirect target for the active path
4. `microsequencer` issues services, waits correctly, and drives ENDI sequencing
5. `commit_engine` makes the redirect architecturally visible at ENDI and flushes fetch

## Active ownership boundaries

### `decoder`
Owns:

- opcode classification for the in-scope direct JMP path
- decode-owned metadata handoff
- held decode result until acceptance or committed-boundary squash

Does not own:

- target computation
- architectural redirect
- commit-visible flush decision

### `fetch_engine`
Owns:

- displacement-fetch service behavior needed by the active Rung 2 path
- service-local wait/completion behavior for that fetch work

Does not own:

- decode classification
- target validation policy
- architectural redirect commit

### `flow_control`
Owns:

- target computation for the active Rung 2 path
- near-transfer validation behavior for the active path

Does not own:

- decode classification
- commit visibility
- service sequencing policy

### `microsequencer`
Owns:

- decode acceptance into the microcode/service path
- service issue and wait behavior
- `SR_WAIT` stall handling
- ENDI sequencing for the active Rung 2 path
- committed-boundary squash pulse for abandoned pre-commit work

Does not own:

- architectural visibility of redirect
- final redirect commit
- fetch-local shortcutting around the service path

### `commit_engine`
Owns:

- architecturally visible redirect at ENDI
- committed redirect flush
- final committed EIP visibility for the active path

Does not own:

- target computation
- decode classification
- earlier-stage service policy

### `service_dispatch`
In the delivered Rung 2 path, `service_dispatch` remains a thin routing layer.

It routes requests and responses for the active services and does not absorb service policy or become a separate pipeline stage.

## Stage and handoff behavior delivered

The delivered path preserves the Rung 2 handoff model:

- real stage/service boundary outputs are preserved long enough to be accepted
- service wait is real
- `SR_WAIT` does not mean completion
- bubbles are allowed
- committed redirect cleanup happens at ENDI, not at dispatch

One important delivered cleanup detail is:

- `microsequencer` stops presenting the retired JMP target once `endi_done` is already high, which prevents stale retired target restaging into `commit_engine` on the following cycle

## Active RTL and bench files for delivered Rung 2

The current delivered Rung 2 path is represented by:

- `rtl/core/decoder.sv`
- `rtl/core/microsequencer.sv`
- `rtl/core/commit_engine.sv`
- `rtl/core/prefetch_queue.sv`
- `rtl/core/services/fetch_engine.sv`
- `rtl/core/services/flow_control.sv`
- `rtl/core/services/service_dispatch.sv`
- `sim/tb/tb_rung2_jmp.sv`

## What was intentionally not carried into Rung 2

The delivered Rung 2 implementation does **not** claim or include:

- broader CALL / RET / Jcc execution coverage
- generic later-rung infrastructure beyond what this path needed
- fetch-local direct-follow shortcutting as the Rung 2 solution
- moving target computation into `decoder`
- moving validation into `commit_engine`
- turning `service_dispatch` into a policy owner or registered stage

## Verification linkage

The current delivered state is verified through:

- `make rung2-regress`

The verification record belongs in:

- `docs/implementation/rung2_verification.md`

## Developer note

If a future change makes this note describe more than the current active regression actually proves, this file should be narrowed again rather than expanded by assumption.