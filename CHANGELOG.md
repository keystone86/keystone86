# Changelog

All notable changes to this project are recorded here.

## [Unreleased]

### Post-Rung-2 cleanup — Pass 1–4

Pass 1 — documentation/clarity:
- README updated to reflect Rung 2 passing status and contracts
- Makefile: added `rung2-regress` target and filled out `help` for all rung targets
- `docs/implementation/bringup/STATUS_DASHBOARD.md` updated — Rung 2 row now Passing
- `docs/overview/bootstrap_status.md` updated with Rung 2 commands
- Added `docs/implementation/bringup/rung2.md`
- Added `docs/implementation/rung2_implementation_note.md`
- Added `docs/implementation/rung2_verification.md`

Pass 2 — shared-definition cleanup:
- `rtl/core/bus_interface.sv`: removed 5 unused `include` headers
- `rtl/core/commit_engine.sv`: removed 2 unused `include` headers
- `rtl/core/decoder.sv`: replaced `` `include "entry_ids.svh" `` with `import keystone86_pkg::*`; converted backtick symbols to package names
- `rtl/core/microsequencer.sv`: replaced 4 `include` headers with `import keystone86_pkg::*`; removed 4 duplicate `MSEQ_*` localparams; retained private `UOP_*` localparams
- `rtl/include/keystone86_pkg.sv`: header updated to clarify authoritative-source role and legacy `.svh` status
- `rtl/include/*.svh`: added legacy compatibility notices to all five headers
- Added `docs/implementation/coding_rules/source_of_truth.md`

Pass 3 — debug instrumentation cleanup:
- `rtl/core/decoder.sv`: removed dead `synthesis translate_off` `dbg_last_opcode_byte` block (written but never read or exported)

Pass 4 — file/layout cleanup:
- `TREE.txt`: regenerated from current repo state (was stale from bootstrap snapshot)
- `rtl/core/microcode/src/entries/entry_jmp_near.uasm`: added status header clarifying reference-artifact vs build-input status

Post-cleanup process documentation:
- `docs/implementation/coding_rules/review_checklist.md`: added package import discipline and `source_of_truth.md` drift gate entries
- Added `docs/process/developer_handoff_contract.md`
- Added `docs/process/rung_execution_and_acceptance.md`
- Added `docs/process/tooling_and_observability_policy.md`

---

## Rung 2 — JMP SHORT control transfer

- Implemented position-proven byte capture in `decoder.sv` (Contract 1)
- Implemented real decode/control acceptance boundary (Contract 2)
- Implemented control-transfer serialization in `microsequencer.sv` (Contract 3)
- Implemented commit-owned redirect visibility in `commit_engine.sv` (Contract 4)
- Added `squash` signal: microsequencer → decoder + prefetch_queue
- Added `target_eip` / `has_target` signals: decoder → microsequencer
- Added `pc_target_en` / `pc_target_val` signals: microsequencer → commit_engine
- Added `kill` input to `prefetch_queue.sv` for stale-work suppression
- Added Rung 2 simulation target: `make rung2-sim`
- Added `sim/tb/tb_rung2_jmp.sv` with 5 self-checking tests (19 assertions)
- Added `rtl/core/microcode/src/entries/entry_jmp_near.uasm` as reference artifact
- Bootstrap ROM updated in `scripts/ucode_build.py`: `ENTRY_JMP_NEAR` at dispatch `0x07` → uPC `0x050`

---

## Rung 1 — NOP classification and EIP advancement

- Extended `decoder.sv` with opcode classification: `0x90` → `ENTRY_NOP_XCHG_AX`, prefix opcodes → `ENTRY_PREFIX_ONLY`
- Extended `microsequencer.sv` with `pc_eip_en` / `pc_eip_val` output ports for EIP staging
- Updated `cpu_top.sv` to wire EIP staging ports
- Updated `scripts/ucode_build.py`: `ENTRY_NOP_XCHG_AX` and `ENTRY_PREFIX_ONLY` now use `ENDI CM_NOP|CM_EIP`
- Added Rung 1 simulation target: `make rung1-sim`
- Added `sim/tb/tb_rung1_nop_loop.sv` with 8 self-checking tests

---

## Rung 0 — Reset/fetch/decode/dispatch loop

- Implemented `rtl/core/bus_interface.sv`: minimal instruction fetch bus FSM
- Implemented `rtl/core/prefetch_queue.sv`: 4-byte circular instruction byte queue with flush support
- Implemented `rtl/core/decoder.sv` (stub): consumes one byte, always emits `ENTRY_NULL`
- Implemented `rtl/core/microcode_rom.sv`: synchronous ROM loading `ucode.hex` and `dispatch.hex`
- Implemented `rtl/core/microsequencer.sv`: four-state control (FETCH_DECODE, EXECUTE, WAIT_SERVICE, FAULT_HOLD)
- Implemented `rtl/core/commit_engine.sv`: reset-visible EIP state, ENDI with commit mask, fault staging
- Implemented `rtl/core/cpu_top.sv`: top-level integration with debug observability ports
- Added `sim/models/bootstrap_mem.sv`: deterministic memory model returning `0x00`
- Added Rung 0 simulation target: `make rung0-sim`
- Added `sim/tb/tb_rung0_reset_loop.sv` with 7 self-checking tests

---

## Bootstrap scaffold (Milestone A0)

- Repository scaffold established
- Frozen constitutional spec set imported (`docs/spec/frozen/`)
- `IMPORT_MANIFEST.md` and `STATUS.md` tracking constitutional files
- Appendix A codegen scaffold added (`tools/spec_codegen/`)
- Shared RTL namespace: `rtl/include/keystone86_pkg.sv` and `*.svh` files
- Bootstrap microcode seed: `microcode/src/entries/`, `scripts/ucode_build.py`
- CI and release scaffolding added
- Governance, contribution, and legal documents added
- Bring-up ladder defined in `docs/spec/frozen/appendix_d_bringup_ladder.md`
