# Rung 3 Resume Context

Historical notice: this file is stale Rung 3 recovery context. It is not current
project guidance and must not be used to start new rung work. Current Rung 5
verification status is recorded in `docs/implementation/rung5_verification.md`;
Rung 6 remains blocked until Rung 5 is explicitly accepted and Rung 6 is started
under the proven workflow.

Branch: `rung3-codex`

Base commit: `e56b099 Harden dev container agent workflow`

Goal: rebuild old Rung 3 artifacts so `docs/implementation/bringup/rung3.md`
passes exactly: service-oriented near `CALL`/`RET`, microcode-driven behavior,
commit-visible architectural state at `ENDI`, and verification recorded with
actual results.

## Sandbox/container context

Shell commands in the old container failed unless escalated because Bubblewrap
could not create the required namespace.

`docker/Dockerfile` was changed to add `bubblewrap` to the base apt package
list. The container still needs to be rebuilt from the host.

Suggested host-side rebuild:

```bash
make dev-build
make dev
```

If sandboxing still fails after rebuild, update the `dev` target in `Makefile`
to include:

```make
--security-opt seccomp=unconfined \
--security-opt apparmor=unconfined \
```

If that is still insufficient, use `--privileged` for the dev container.

## Worktree context

Known worktree state before container rebuild:

- `docker/Dockerfile` modified to install `bubblewrap`
- `rtl/core/decoder.sv` partially changed for Rung 3 classification-only behavior
- `rtl/core/microsequencer.sv` partially changed for Rung 3 CALL/RET service handoff
- `rtl/core/cpu_top.sv` was not successfully patched and still needs wiring
- `.claude/` was untracked

Last known `make rung3-sim` before edits: 18 passed, 15 failed.

Rung 1/Rung 2 checks inside the Rung 3 testbench passed. CALL/RET failed
because `scripts/ucode_build.py` still had placeholder CALL/RET microcode and
`cpu_top.sv` tied `pc_ret_addr_en` / `pc_ret_imm_en` to zero.

## Resume plan

1. Run `git status --short --branch`.
2. Inspect:
   - `rtl/core/decoder.sv`
   - `rtl/core/microsequencer.sv`
   - `rtl/core/cpu_top.sv`
   - `scripts/ucode_build.py`
3. Finish `cpu_top.sv` wiring for:
   - decoder metadata outputs into `microsequencer`
   - `microsequencer` `pc_ret_addr_*` and `pc_ret_imm_*` outputs into `commit_engine`
   - `t4_r` into `microsequencer`
4. Replace placeholder CALL/RET entries in `scripts/ucode_build.py` with the
   bounded Rung 3 service sequence.
5. Run:

```bash
make codegen
make ucode
make rung3-regress
```

6. Update `docs/implementation/rung3_verification.md` with actual command
   output/results only after the run.

## Required directive files already read

- `docs/process/developer_directive.md`
- `docs/process/developer_handoff_contract.md`
- `docs/process/rung_execution_and_acceptance.md`
- `docs/process/tooling_and_observability_policy.md`
- `docs/implementation/coding_rules/source_of_truth.md`
- `docs/implementation/coding_rules/review_checklist.md`
- `docs/spec/frozen/appendix_d_bringup_ladder.md`
- `docs/implementation/bringup/rung3.md`
