# Keystone86 / Aegis - Rung 5 Verification

## Scope

Rung 5 is the bounded real-mode INT / IRET / fault-delivery bring-up rung.

The verified Rung 5 scope is:

- `CD imm8` decoded and executed as the in-scope `INT imm8` form.
- `CF` decoded and executed as the in-scope `IRET` form.
- `FETCH_IMM8` used to obtain the interrupt vector for `INT imm8`.
- bounded `INT_ENTER` real-mode interrupt entry.
- bounded `IRET_FLOW` real-mode interrupt return.
- bounded `#UD` delivery through `ENTRY_NULL -> SUB_FAULT_HANDLER -> INT_ENTER`.
- commit-visible `EIP`, `CS`, `FLAGS`, `ESP`, stack-frame, and redirect behavior at ENDI only.
- `INT 0x21` round trip through a trivial handler containing `IRET`.

Rung 5 does not include protected-mode INT/IRET, descriptor validation,
privilege checks, task gates, PIC/APIC, `INT3`, `INTO`, broad segment
translation, MOV, ALU, or Rung 6+ work.

Fetch remains the Rung 5 phase-1 flat handler-IP model. The verified behavior
does not claim full real-mode `CS << 4 + IP` physical fetch translation.

## Tested Implementation Commit

- Commit: `b8e75f9`
- Subject: `rung5: add bounded pass5 int iret roundtrip proof`
- Verification basis: committed implementation state only.

This document records the actual committed-state run results for commit
`b8e75f9`. It is not a protected authority file and does not define alternate
acceptance criteria.

## How To Run

Run from the Keystone86 dev container at `/work`:

```sh
make codegen
make ucode
make rung4-regress
make rung5-pass2-sim
make rung5-pass3-sim
make rung5-pass4-sim
make rung5-pass5-sim
make rung5-regress
```

`rung5-regress` invokes the accepted Rung 4 regression path and the Rung 5
Pass 2, Pass 3, Pass 4, and Pass 5 simulations.

## Proof Summary

Pass 2 proved bounded `INT_ENTER`:

- `CD imm8` dispatches through `ENTRY_INT`.
- `FETCH_IMM8` obtains the interrupt vector.
- `INT_ENTER` reads the real-mode IVT entry.
- `INT_ENTER` stages the 16-bit `FLAGS/CS/IP` frame.
- IF is cleared in the committed handler FLAGS image.
- handler `EIP`, `CS`, `FLAGS`, `ESP`, frame writes, and redirect become visible only through `CM_INT`.

Pass 3 proved bounded `IRET_FLOW`:

- `CF` dispatches through `ENTRY_IRET`.
- `IRET_FLOW` reads IP/CS from `[ESP+0]` and FLAGS from `[ESP+4]`.
- `IRET_FLOW` stages the popped `EIP`, `CS`, `FLAGS`, and `ESP`.
- IF is restored from the popped FLAGS word.
- return state and redirect become visible only through `CM_IRET`.

Pass 4 proved bounded `#UD` delivery:

- unknown opcode dispatches through `ENTRY_NULL`.
- `ENTRY_NULL` raises `FC_UD`.
- `SUB_FAULT_HANDLER` maps the fault to vector `0x06`.
- `SUB_FAULT_HANDLER` uses the same bounded `INT_ENTER` path.
- fault delivery commits the handler target through the bounded Rung 5 path.

Pass 5 proved the integrated Rung 5 round trip:

- reset stream executes `INT 21h`.
- `FETCH_IMM8` obtains vector `0x21`.
- `INT_ENTER` reads `IVT[0x21]`.
- `INT_ENTER` pushes the 16-bit `FLAGS/CS/IP` frame.
- the flat handler target executes `CF`.
- `CF` decodes as `ENTRY_IRET`.
- `IRET_FLOW` pops IP/CS/FLAGS.
- final `EIP`, `CS`, FLAGS low 16 bits, IF, and `ESP` match the expected post-INT continuation state.
- committed redirects/flushes occur at INT entry and IRET return.
- no early architectural visibility occurs before `CM_INT` or `CM_IRET`.

Rung 0 through Rung 4 regression remained passing during the committed-state
Rung 5 verification run.

## Command Results

| Command | Result |
|---|---|
| `make codegen` | PASS |
| `make ucode` | PASS |
| `make rung4-regress` | PASS |
| `make rung5-pass2-sim` | PASS |
| `make rung5-pass3-sim` | PASS |
| `make rung5-pass4-sim` | PASS |
| `make rung5-pass5-sim` | PASS |
| `make rung5-regress` | PASS |

## Generated Artifacts

`make codegen` and `make ucode` passed for commit `b8e75f9`.

Generated simulation and microcode build outputs remain under `build/`, which is
gitignored according to the source-of-truth document. No generated artifact is
claimed as committed by this verification record.

## Non-Coverage

This Rung 5 verification does not claim:

- protected-mode interrupt or IRET behavior.
- IDT descriptor handling or descriptor validation.
- privilege checks.
- task gates or task return behavior.
- interrupt gates, trap gates, PIC, APIC, or external interrupt-controller behavior.
- `INT3` (`CC`) or `INTO` (`CE`).
- full real-mode physical fetch translation using `CS << 4 + IP`.
- broad segment translation or hidden segment-cache behavior.
- broad stack, bus, or exception-framework redesign.
- MOV, ALU, or Rung 6+ instruction behavior.

## Acceptance Status

Rung 5 implementation verification passed at committed implementation hash
`b8e75f9`.

Rung 5 is not accepted by this record alone. The verification documentation must
be reviewed, committed, and accepted before Rung 6 can begin.

Rung 6 remains blocked until Rung 5 is fully implemented, verified, documented
from actual run results, and accepted.
