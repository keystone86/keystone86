# Keystone86 / Aegis — Claude Code Session Contract

## READ THIS BEFORE TOUCHING ANYTHING

This file is loaded at the start of every Claude Code session.
It is not optional reading. It is the entry gate for all work in this repo.

---

## What this project is

Keystone86 is a microcoded 80486-class x86 CPU core in SystemVerilog.
It is not a pipeline CPU. It is not ao486. It is a control-first,
microcode-driven machine where instruction meaning lives in microcode
routines, not in distributed RTL logic.

Current generation: **Aegis**
Current status: **Rung 3 passing** — near CALL/RET service path proven.
Next milestone: Rung 4 (Jcc).

This is an active implementation project with strict architectural
guardrails. Drift from those guardrails is the primary failure mode.
Every session must actively resist drift.

---

## Required reading chain — do this before any implementation work

Read these files in order before making any RTL, microcode, testbench,
or Makefile changes. Do not skip. Do not skim.

```
1. docs/process/developer_directive.md
2. docs/process/developer_handoff_contract.md
3. docs/process/rung_execution_and_acceptance.md
4. docs/process/tooling_and_observability_policy.md
5. docs/implementation/coding_rules/source_of_truth.md
6. docs/implementation/coding_rules/review_checklist.md
7. docs/spec/frozen/appendix_b_ownership_matrix.md
8. docs/spec/frozen/appendix_d_bringup_ladder.md
9. docs/implementation/bringup/rung{N}.md  ← current rung document
```

Precedence on conflict:
1. `docs/spec/frozen/` — constitutional authority, never overridden
2. `docs/implementation/coding_rules/source_of_truth.md`
3. `docs/process/developer_directive.md`
4. `docs/process/developer_handoff_contract.md`
5. Rung bring-up document

---

## The single most important rule

**Microcode owns instruction meaning. Hardware is subordinate.**

If you are about to implement instruction behavior in RTL — stop.
If a service is about to check which instruction is running — stop.
If the decoder is about to compute operand values — stop.
If architectural state is about to become visible before ENDI — stop.

These are not style preferences. They are the architectural foundation
of the entire project. Violating them produces a machine that cannot
be corrected by microcode update alone. That is not acceptable.

---

## Authoritative file map

### Live RTL — these files are compiled and simulated

```
rtl/core/cpu_top.sv
rtl/core/prefetch_queue.sv
rtl/core/decoder.sv
rtl/core/microsequencer.sv
rtl/core/microcode_rom.sv
rtl/core/commit_engine.sv
rtl/core/bus_interface.sv
rtl/core/services/fetch_engine.sv
rtl/core/services/flow_control.sv
rtl/core/services/service_dispatch.sv
```

### Scaffold only — future phases, do not modify for current rung work

```
rtl/core/frontend/         ← future front-end refactor
rtl/core/microcode/        ← future microcode refactor
rtl/core/services/         ← except fetch_engine, flow_control, service_dispatch
rtl/core/bus/              ← future bus refactor
sim/tb/integration/        ← future integration tests
sim/tb/unit/               ← future unit tests
```

### Frozen constitutional spec — never edit, only reference

```
docs/spec/frozen/master_design_statement.md
docs/spec/frozen/appendix_a_field_dictionary.md
docs/spec/frozen/appendix_b_ownership_matrix.md
docs/spec/frozen/appendix_c_assembler_spec.md
docs/spec/frozen/appendix_d_bringup_ladder.md
docs/spec/frozen/verification_plan.md
```

### Generated artifacts — never edit manually

```
rtl/include/keystone86_pkg.sv     ← regenerate with: make codegen
rtl/include/*.svh                 ← regenerate with: make codegen
build/microcode/ucode.hex         ← regenerate with: make ucode
build/microcode/dispatch.hex      ← regenerate with: make ucode
```

### Authoritative shared RTL constants

All RTL modules must use:
```systemverilog
import keystone86_pkg::*;
```
Never use `\`include` for `.svh` files in RTL. Those exist for external
tooling compatibility only.

---

## Module ownership — quick reference

| Module | Owns | Must never |
|--------|------|------------|
| `decoder` | Classification, entry ID, M_* metadata | Implement semantics, read GPRs, generate faults |
| `microsequencer` | uPC, dispatch, service invocation, stall | Access memory, modify arch state, know x86 encoding |
| `microcode ROM` | Instruction meaning, sequencing, fault ordering | Be bypassed for any instruction |
| `commit_engine` | All arch registers, ENDI execution, pending commit | Know what instruction means, decide commit mask |
| `service_dispatch` | Routing only | Hold state, make policy decisions |
| `prefetch_queue` | Byte buffering, speculative fetch | Classify bytes, initiate flushes |
| Services (leaf) | Their specific computation | Call other services, check instruction identity |

Full ownership matrix: `docs/spec/frozen/appendix_b_ownership_matrix.md`

---

## Build paths

All generated artifacts go under `build/`. Never scatter artifacts
into source directories.

```
build/microcode/     ← ucode.hex, dispatch.hex, ucode.lst, dispatch.lst
build/sim/rung0/     ← rung 0 .vvp and intermediates
build/sim/rung1/     ← rung 1 .vvp and intermediates
build/sim/rung2/     ← rung 2 .vvp and intermediates
build/sim/rung3/     ← rung 3 .vvp and intermediates
build/synth/         ← ECP5 synthesis outputs
build/formal/        ← SymbiYosys outputs
```

---

## Fresh environment setup

After clone or when switching environments:

```bash
make codegen          # generates rtl/include/ and microcode export includes
make ucode            # generates build/microcode/*.hex and *.lst
make namespace-check  # confirms namespace exports are present
make ucode-bootstrap-check  # confirms microcode ROM seed is consistent
```

---

## Simulation commands

```bash
# Individual rung simulations
make rung0-sim
make rung1-sim
make rung2-sim
make rung3-sim

# Regression (each includes all prior rungs)
make rung0-regress
make rung1-regress
make rung2-regress
make rung3-regress

# Full current baseline
make codegen && make ucode && make rung3-regress
```

iverilog flags: `-g2012 -Wall`
Include dirs: `-I rtl/include -I build/microcode`

The microcode ROM loads from `build/microcode/ucode.hex` and
`build/microcode/dispatch.hex` at runtime via `$readmemh`. These paths
are relative to the repo root where `vvp` is invoked.

---

## Bootstrap smoke checks

These run without RTL simulation (host-side Python only):

```bash
make spec-check
make frozen-manifest-check
make namespace-check
make decode-dispatch-smoke
make microseq-smoke
make commit-smoke
make service-abi-smoke
make prefetch-decode-smoke
make bootstrap-report
```

---

## ECP5 synthesis (when synthesis work begins)

```bash
# sv2v conversion then Yosys synthesis
sv2v -I rtl/include rtl/core/*.sv -o build/synth/keystone86.v
yosys -p "synth_ecp5 -json build/synth/keystone86.json" build/synth/keystone86.v
nextpnr-ecp5 --json build/synth/keystone86.json --lpf platform/lattice_ecp5/<constraints>.lpf \
             --textcfg build/synth/keystone86.config
ecppack build/synth/keystone86.config build/synth/keystone86.bit
```

Flash to hardware (requires `make dev-fpga` for USB passthrough):
```bash
openFPGALoader -b <board> build/synth/keystone86.bit
```

---

## Formal verification (when formal work begins)

SymbiYosys is available. Formal properties go in `formal/properties/`.
Outputs go in `build/formal/`.

---

## Waveform inspection

Testbenches can generate VCD files. Open with GTKWave:
```bash
gtkwave <file>.vcd
```

In Codespaces: copy the VCD to your local machine and open there,
or use a VS Code waveform extension.

---

## Rung discipline — the rules that prevent drift

**Before starting any rung:**
1. Confirm the prior rung is stable and passing
2. Read `docs/spec/frozen/appendix_d_bringup_ladder.md` for exact gate criteria
3. Read `docs/implementation/bringup/rung{N}.md` for bounded scope
4. Implement minimum RTL that satisfies the contracts — nothing more

**What a rung explicitly does NOT authorize:**
- Unrelated cleanup or restructuring
- Directory reorganization
- Future-rung preparation
- Scope creep into adjacent modules
- Debug framework redesign
- Pre-implementation of later-rung behavior

**If a correct implementation appears to require broader scope:**
Stop. Escalate. Do not absorb the scope silently.

---

## Known drift patterns — actively resist these

These are the specific ways this project has experienced architectural
drift. Watch for them in every session:

1. **Decoder absorbing semantics** — decoder starts computing operand
   values, reading register state, or generating faults directly.
   Decoder output is M_* metadata + ENTRY_ID only.

2. **Services checking instruction identity** — a service uses
   M_ENTRY_ID or M_OPCODE_CLASS to decide what to do. Services are
   instruction-agnostic leaf functions.

3. **Commit engine growing policy** — commit_engine starts making
   per-instruction decisions. It applies the commit mask microcode
   provides. It does not decide what the mask should be.

4. **Architectural state visible before ENDI** — GPR, EIP, EFLAGS,
   or ESP changes become visible mid-instruction. Nothing is
   architecturally visible until ENDI.

5. **Scope creep into future rungs** — implementing Rung N+1 behavior
   "while we're here." Each rung is bounded. Stay within it.

6. **Claiming completion without running verification** — reporting
   pass/complete/ready without running the actual commands and
   recording actual output. This is explicitly prohibited by the
   handoff contract.

7. **Touching scaffold files as if they are live** — files under
   `rtl/core/frontend/`, `rtl/core/microcode/` (not the live files),
   `sim/tb/integration/`, `sim/tb/unit/` are placeholders. Do not
   treat them as authoritative or modify them for current rung work.

8. **Treating existing Rung 3/4 artifacts as authoritative** — the
   repo contains Rung 3 and Rung 4 artifacts from before a drift
   reset. These are NOT the current implementation target. Rung 3
   must be re-proven clean from the Rung 2 baseline. Do not build
   on top of existing Rung 3 RTL without first verifying it passes
   `make rung3-regress` cleanly from the Rung 2 baseline.

---

## Git and commit conventions

Claude Code has full git access inside the dev container. SSH credentials
and git identity are mounted from the host — do not modify `.ssh/` or
`.gitconfig`.

### Before committing

Always run the authoritative baseline first:
```bash
make codegen && make ucode && make rung2-regress
```

Do not commit if the baseline is not passing. Do not commit if verification
was not actually run against the exact files being committed.

### Commit message format

Follow the handoff contract discipline in commit messages. Be accurate
about what actually changed — not what was intended or expected.

Format:
```
<short imperative summary — what this commit does>

- <file or area>: <what changed and why>
- <file or area>: <what changed and why>

Verification:
- <exact command run>
- <actual result>
```

Example:
```
Add Docker dev environment and build path consolidation

- docker/Dockerfile: Ubuntu 22.04 dev image with full ECP5/formal/sim toolchain
- .devcontainer/devcontainer.json: Codespaces support
- CLAUDE.md: Claude Code session guardrails and drift pattern documentation
- Makefile: add dev/dev-build/dev-fpga targets, consolidate build paths to build/
- scripts/: update 8 scripts for build/microcode/ and build/sim/ paths
- rtl/core/microcode_rom.sv: update $readmemh default paths
- docs/: update source_of_truth, tooling policy, rung docs for new paths
- README.md: Docker setup section, accurate rung status

Verification:
- make codegen && make ucode && make rung2-regress
- RESULT: ALL RUNG 2 TESTS PASSED
```

### What not to do

- Do not use vague summaries like "fix stuff" or "update files"
- Do not claim verification passed without running it
- Do not commit generated artifacts (`build/` is gitignored — this is correct)
- Do not commit partial work and label it complete
- Do not widen a commit beyond the scope of the requested task

### Branch and push

This project uses `main` as the primary branch. Normal flow:
```bash
git add <specific files>     # never use git add -A without reviewing diff first
git status                   # confirm only intended files are staged
git diff --cached            # review what is about to be committed
git commit -m "<message>"
git push origin main
```

When asked to commit and push, always show `git status` and `git diff --cached`
output before committing so the human can confirm the scope is correct.

### Codespaces git auth

In Codespaces, GitHub auth is handled automatically via the Codespaces
credential helper. SSH mount is not needed. `git push` works without
additional setup.



```
□ Decoder remains classification-only
□ Microcode retains policy ownership
□ Services remain leaf mechanisms
□ No architectural visibility outside commit_engine + ENDI
□ This remains a microcoded design, not hard RTL instruction implementation
□ Instruction behavior remains microcode/microsequencer driven
□ Instruction semantics remain patchable through dispatch/microcode
□ No instruction-support growth implemented as RTL-only semantic expansion
□ Any instruction behavior change has corresponding dispatch/microcode change
□ New fields/enums update Appendix A first
□ New ownership changes update Appendix B first
□ Bring-up sequence remains aligned with Appendix D
□ Shared RTL constants use import keystone86_pkg::* only
□ New authoritative-source relationships reflected in source_of_truth.md
```

Full checklist: `docs/implementation/coding_rules/review_checklist.md`

---

## Handoff format — every session that produces deliverables

Every handoff must follow `docs/process/developer_handoff_contract.md`.

Minimum required structure:

```
Status: READY FOR REVIEW  (or NOT READY FOR REVIEW)

Base: <commit hash or package name>

Scope: <one short paragraph>

Changed files:
- path/to/file

Control-source accounting:
- dispatch change: <path and note> or none
- microcode source/content change: <path and note> or none

Verification run:
- make codegen
- make ucode
- make rung{N}-regress

Verification results:
- <actual output, not inferred>

Deferred:
- <explicit list or "none">
```

Do not use:
- "should pass"
- "likely passing"
- "not rerun but unchanged"
- "expected pass"

Report only what actually ran against the actual delivered state.

---

## Current rung status

| Rung | Goal | Status | Testbench |
|------|------|--------|-----------|
| 0 | Reset/fetch/decode/dispatch loop | **Passing** | `sim/tb/tb_rung0_reset_loop.sv` |
| 1 | NOP classification, EIP advance | **Passing** | `sim/tb/tb_rung1_nop_loop.sv` |
| 2 | JMP SHORT control transfer | **Passing** | `sim/tb/tb_rung2_jmp.sv` |
| 3 | Near CALL/RET service path | **Needs re-proof from Rung 2 baseline** | `sim/tb/tb_rung3_call_ret.sv` |
| 4+ | Jcc and beyond | Superseded — do not use | — |

**Authoritative passing baseline:**
```bash
make codegen && make ucode && make rung2-regress
```

**Context:** Rung 3 previously passed but drift was discovered during Rung 4
work. The project was reset to the clean Rung 2 baseline. Rung 3 and Rung 4
artifacts remain in the repo but are not authoritative. Rung 3 must be
re-proven from the Rung 2 baseline before it can be claimed as passing again.
Rung 4 artifacts will be superseded once Rung 3 is re-proven.

**Rung 3 scope and implementation intent:**
```
docs/implementation/bringup/rung3.md
```
This is the sanitized template for Rung 3 work going forward. Use it as the
bounded scope document. Do not treat existing Rung 3 RTL artifacts as
authoritative — they may contain the drift that caused the reset.

---

## Source of truth reference

For the full authoritative source map, see:
`docs/implementation/coding_rules/source_of_truth.md`

When in doubt about which file is authoritative for any concern,
read that document first.

---

*This file is part of the Keystone86 developer environment.
It is read by Claude Code at the start of every session.
Keep it accurate. Update it when the repo structure changes.*
