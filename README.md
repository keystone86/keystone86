cat > README.md <<'EOF'
# Keystone86

Keystone86 is an in-progress clean-room x86 RTL core project focused on building a structured, understandable, and maintainable 80486-class-compatible design path.

The project is organized around **spec-first development**, explicit ownership boundaries between blocks, generated/shared definitions, and staged bring-up through simulation "rungs." The authoritative passing baseline is **Rung 2**. Rung 3 is being re-proven from the clean Rung 2 baseline after drift was discovered during Rung 4 work.

## Current status

Keystone86 is **active early-stage RTL bring-up**, not a finished CPU core.

What is present now:

- repository structure, frozen spec set, and design notes
- generated microcode/bootstrap artifacts
- working top-level RTL skeleton
- prefetch queue RTL
- decoder RTL with early multi-byte control-transfer support
- microsequencer RTL
- commit engine RTL
- bus interface RTL
- Rung 0 simulation target — **passing**
- Rung 1 simulation target — **passing**
- Rung 2 simulation target — **passing**
- Rung 3 — **needs re-proof** (drift discovered during Rung 4, reset to Rung 2 baseline)
- self-checking simulation testbenches for early bring-up

What is **not** present yet:

- a complete 80486-compatible execution core
- full instruction coverage
- full addressing-mode implementation
- memory-management/paging implementation
- protected-mode completeness
- caches, pipeline optimization, or performance tuning
- broad regression coverage across real software workloads

So the correct way to describe the project today is:

> **A real RTL bring-up project with working early-stage front-end/control-path simulation through Rung 2, not yet a complete 80486 core.**

## Bring-up ladder

The repo currently uses staged bring-up targets.

### Rung 0

Bootstrap reset/fetch/dispatch plumbing.

Goal:
- reset vector ownership
- fetch starts at the correct architectural address
- basic microcode dispatch loop is alive

Run:
```bash
make rung0-sim
```

### Rung 1

Basic opcode classification and sequential architectural advance.

Goal:
- decode simple instructions such as NOP-class behavior
- validate dispatch timing and ENDI/EIP commit path

Run:
```bash
make rung1-sim
```

### Rung 2

Early control-transfer correctness for short/near jump handling.

Goal:
- position-proven byte capture
- explicit decode acceptance boundary
- stale-work suppression on accepted control transfer
- commit-owned redirect visibility
- front-end retarget/flush behavior proven in simulation

Run:
```bash
make rung2-sim
```

### Rung 3

Near CALL and RET service path.

Goal:
- near CALL pushes correct return address, decrements ESP
- near RET restores EIP and ESP exactly
- RET imm16 applies post-pop stack adjustment
- nested CALL/RET depth 4 all unwind correctly
- stack-touching control-transfer path proven end-to-end

Run:
```bash
make rung3-sim
```

## Development environment

The recommended way to develop on this project is the Docker-based dev
environment. It provides a complete, reproducible toolchain for every
contributor without installing anything on your host system.

The same image includes both Claude Code and OpenAI Codex CLI. They are intended
to coexist in the same environment. Use one AI coding agent at a time.

### Tools included

- `iverilog` + `vvp` — RTL simulation
- `verilator` — fast simulation and lint
- `gtkwave` — waveform inspection
- `yosys` — synthesis frontend
- `nextpnr-ecp5` + `prjtrellis` — ECP5 place and route
- `openFPGALoader` — ECP5 hardware flashing
- `symbiyosys` + `z3` — formal verification
- `sv2v` — SystemVerilog to Verilog conversion
- `python3` + `pytest` + `pyyaml` + `jinja2` + `click` — scripting layer
- `make`, `git`, `ripgrep`, `jq`, `tree`, `dos2unix`, `entr` — repo tooling
- `claude` — Claude Code AI coding agent
- `codex` — OpenAI Codex CLI AI coding agent

### First-time setup

```bash
# Build the image (once, or after Dockerfile changes)
make dev-build

# Enter the dev environment
make dev
```

On first entry, run `claude` to log in with your personal Anthropic account.
Your Claude Code credentials persist in a local Docker volume
(`keystone86-claude-auth`) and survive container restarts.

You may also run `codex` to log in with your OpenAI / ChatGPT account, or use an
`OPENAI_API_KEY` environment variable if that is the workflow you prefer. Your
Codex CLI credentials persist in a separate local Docker volume
(`keystone86-codex-auth`) and survive container restarts.

Claude Code and Codex CLI are installed side by side. Do not run both against the
same working tree at the same time. Use one agent at a time, review its diff, and
commit only after validating the result.

Your host `~/.ssh` and `~/.gitconfig` are mounted read-only into the
container. Git push to GitHub works from inside the container using your
existing SSH key. Claude Code or Codex CLI can commit and push on your behalf
when you explicitly choose to let them do so.

### Daily workflow

```bash
make dev         # enter dev environment (sim, formal, claude, codex, git)
make dev-fpga    # enter dev environment with USB passthrough (ECP5 flashing)
```

Inside the container, all simulation, formal, synthesis, and git operations
work normally. Your host system needs nothing installed except Docker.

You can start either AI coding agent from the same shell:

```bash
claude   # Claude Code
codex    # OpenAI Codex CLI
```

Use only one coding agent at a time. A safe workflow is:

1. start a clean git branch
2. run one agent
3. give it a narrow task
4. inspect `git diff`
5. run the rung/regression checks
6. commit only after the result is understood

### Codespaces

The repo includes `.devcontainer/devcontainer.json` for GitHub Codespaces
support. The same Docker image is used. Set `ANTHROPIC_API_KEY` and/or
`OPENAI_API_KEY` as personal Codespaces secrets if you want API-key based access
inside Codespaces.

Interactive login may also be used where supported by the tool and environment.

Note: `make dev-fpga` (USB passthrough) is not available in Codespaces.

## Project principles

This project is intentionally built around a few strong rules:

### 1. Spec-first development

The spec and ownership model define what each block is allowed to do before broader implementation grows around it.

### 2. Explicit ownership boundaries

Modules are supposed to do one job and not quietly absorb policy that belongs elsewhere.

Examples:
- **decoder** classifies and forms a decode payload
- **microsequencer** owns accepted instruction/control sequencing
- **commit_engine** owns architectural visibility and redirect commit
- **prefetch_queue** owns buffering and fetch-side byte delivery

### 3. Staged correctness before optimization

The project is currently prioritizing:
- correctness
- testbench proof
- architectural boundaries
- understandable control flow

before attempting:
- speculative behavior
- aggressive overlap
- front-end optimization
- performance-oriented redesign

### 4. Generated shared definitions

The repo includes generated/shared include files and bootstrap microcode build outputs so that decode, dispatch, and commit definitions stay aligned.

## Repository layout

```text
docs/            Specifications, design notes, implementation plans
rtl/             Core RTL and shared include files
microcode/       Microcode sources and generated bootstrap artifacts
sim/             Testbenches and simulation build outputs
scripts/         Repo checks, codegen, smoke scripts, reporting helpers
```

## Main RTL blocks

### `rtl/core/prefetch_queue.sv`

Instruction-byte buffering and fetch-side queue management.

### `rtl/core/decoder.sv`

Early instruction decode. Current bring-up includes:
- opcode classification
- multi-byte handling for early jump bring-up
- position-proven byte capture (Rung 2)
- instruction-local target EIP formation for current Rung 2 scope

### `rtl/core/microsequencer.sv`

Microcode dispatch and execution control. Current bring-up includes:
- decode acceptance handshake
- dispatch timing management
- control-transfer serialization (Rung 2)
- JMP target staging for commit (Rung 2)

### `rtl/core/commit_engine.sv`

Architectural commit boundary. Current bring-up includes:
- reset-visible state ownership
- staged EIP/target-EIP commit
- authoritative queue flush / redirect visibility (Rung 2)
- commit-owned redirect: redirect becomes architecturally real only here

### `rtl/core/cpu_top.sv`

Top-level integration of fetch, decode, microsequencer, commit, ROM, and bus interface.

## Build and simulation

### Fresh clone setup

Some generated artifacts are committed to the repo (the RTL interface files in
`rtl/include/`), while others are local-only build products that must be created
after cloning. Run these two commands before anything else:

```bash
make codegen   # generates microcode/tools/generators/exports/*.inc
make ucode     # generates build/microcode/*.hex and *.lst
```

`make codegen` must be run once after a fresh clone and any time
`tools/spec_codegen/appendix_a_codegen.json` changes.
`make ucode` runs automatically as a dependency of all rung simulation targets.

### Verify the baseline

```bash
make namespace-check       # confirms namespace export files are present
make ucode-bootstrap-check # confirms microcode ROM seed is consistent
make rung2-regress         # runs Rung 0 + Rung 1 + Rung 2 full baseline (authoritative passing baseline)
```

### Run the early bring-up simulations

```bash
make rung0-sim
make rung1-sim
make rung2-sim
make rung3-sim
```

### Run regression (each rung includes all prior rungs)

```bash
make rung0-regress
make rung1-regress
make rung2-regress
make rung3-regress
```

### Run all bootstrap smoke checks

```bash
make decode-dispatch-smoke
make microseq-smoke
make commit-smoke
make service-abi-smoke
make prefetch-decode-smoke
```

### Clean build artifacts

```bash
make clean
```

## Development workflow

A practical workflow for contributors is:

1. update or add design/spec notes if the boundary changes
2. implement the smallest RTL change that satisfies the contract
3. prove the behavior in simulation
4. keep earlier rungs passing
5. avoid widening scope unless necessary

When using an AI coding agent, keep the same discipline:

1. give Claude Code or Codex CLI a narrow task
2. require it to inspect the relevant specs first
3. require it to report files changed
4. review `git diff`
5. run the appropriate rung/regression target
6. commit only after the change is understood

## What "Rung 2 complete" means here

Rung 2 should be understood narrowly.

It means the repo has an implemented and testable early control-transfer path for jump bring-up, including:
- correct multi-byte decode for the covered cases
- position-proven byte capture (decoder only accepts a byte when fetch-side payload proves it is the right byte at the right position)
- accepted decode/control ownership boundary (decode result becomes active only on explicit transfer to microsequencer)
- stale-work suppression (abandoned stream is not advanced after accepted control transfer)
- commit-owned redirect visibility (redirect becomes architecturally real only at ENDI in commit_engine)
- regression coverage for earlier bring-up behavior

It does **not** mean the project has finished the general front end, full x86 decode, or a complete 80486 execution machine.

## Near-term direction

Likely next steps after the current state are:

- broaden decode coverage beyond the current bring-up subset
- extend microcode/service-path execution coverage
- strengthen regression depth
- continue rung-based bring-up for additional instruction classes
- maintain architectural ownership boundaries as the design grows

## Positioning

Keystone86 is best viewed as:

- **not** a toy example
- **not** a production-ready CPU core
- **not** a finished 486 clone

It **is**:
- a serious structured RTL build-out
- a spec-driven CPU core project
- a project with real early simulation bring-up through Rung 2 already landed
- a foundation that is now beyond "empty bootstrap" with working control-transfer simulation, but still well before completion

## License

Add the intended license here if and when you decide it.

## Notes

This repository may evolve quickly while the architecture, interfaces, and bring-up ladder are still being refined. Expect early-stage iteration, especially in front-end/control-path RTL and the simulation harnesses that prove each rung.
EOF