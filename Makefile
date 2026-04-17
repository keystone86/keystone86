SHELL := /bin/bash

.PHONY: help tree spec-check lint ucode ucode-clean sim-smoke regress formal clean bootstrap-info

help:
	@echo "Keystone86 task runner"
	@echo ""
	@echo "Targets:"
	@echo "  make tree                  - print repo tree"
	@echo "  make spec-check            - verify frozen spec files exist"
	@echo "  make lint                  - run placeholder lint checks"
	@echo "  make ucode                 - build bootstrap microcode artifacts"
	@echo "  make ucode-clean           - clean generated microcode artifacts"
	@echo "  make sim-smoke             - run placeholder smoke simulation"
	@echo "  make regress               - run placeholder regression suite"
	@echo "  make formal                - run placeholder formal checks"
	@echo "  make namespace-check       - verify generated/shared namespace alignment"
	@echo "  make codegen               - regenerate RTL includes and microcode export includes"
	@echo "  make spec-sync-status      - show spec/codegen sync status"
	@echo "  make frozen-manifest-check - verify frozen spec manifest"
	@echo "  make version-status        - show repository/version bootstrap status"
	@echo "  make release-notes         - generate stub release notes"
	@echo "  make ucode-bootstrap-check - verify bootstrap microcode artifacts"
	@echo "  make decode-dispatch-smoke - run decode/dispatch smoke checks"
	@echo "  make microseq-smoke        - run microsequencer smoke checks"
	@echo "  make commit-smoke          - run commit/ENDI smoke checks"
	@echo "  make service-abi-smoke     - run service ABI smoke checks"
	@echo "  make prefetch-decode-smoke - run prefetch/decode smoke checks"
	@echo "  make bootstrap-report      - print bootstrap coverage report"
	@echo "  make rung0-sim             - compile and run Rung 0 RTL simulation"
	@echo "  make rung0-regress         - run Rung 0 regression harness"
	@echo "  make rung0-clean           - remove Rung 0 simulation artifacts"
	@echo "  make rung1-sim             - compile and run Rung 1 RTL simulation"
	@echo "  make rung1-regress         - run Rung 1 regression (includes Rung 0 baseline)"
	@echo "  make rung1-clean           - remove Rung 1 simulation artifacts"
	@echo "  make rung2-sim             - compile and run Rung 2 RTL simulation"
	@echo "  make rung2-regress         - run Rung 2 regression (includes Rung 0 + Rung 1)"
	@echo "  make rung2-clean           - remove Rung 2 simulation artifacts"
	@echo "  make clean                 - remove generated files"

tree:
	@python3 scripts/tree.py .

spec-check:
	@python3 scripts/spec_check.py

lint:
	@python3 scripts/lint.py

ucode:
	@python3 scripts/ucode_build.py

ucode-clean:
	@rm -f microcode/build/ucode.hex microcode/build/dispatch.hex microcode/build/ucode.lst
	@echo "Removed generated microcode outputs."

sim-smoke:
	@python3 scripts/sim_smoke.py

regress:
	@python3 scripts/regress.py

formal:
	@python3 scripts/formal.py

clean: ucode-clean rung0-clean rung1-clean rung2-clean
	@echo "Project clean complete."

bootstrap-info:
	@echo "Keystone86 / Aegis bootstrap repository"

bootstrap-status:
	@python3 scripts/bootstrap_status.py

namespace-check:
	@python3 scripts/namespace_check.py

codegen:
	@python3 scripts/codegen.py

spec-sync-status:
	@python3 scripts/spec_sync_status.py

frozen-manifest-check:
	@python3 scripts/frozen_manifest_check.py

version-status:
	@python3 scripts/version_status.py

release-notes:
	@python3 scripts/release_notes_stub.py

ucode-bootstrap-check:
	@python3 scripts/ucode_bootstrap_check.py

decode-dispatch-smoke:
	@python3 scripts/decode_dispatch_smoke.py

microseq-smoke:
	@python3 scripts/microseq_smoke.py

commit-smoke:
	@python3 scripts/commit_smoke.py

service-abi-smoke:
	@python3 scripts/service_abi_smoke.py

prefetch-decode-smoke:
	@python3 scripts/prefetch_decode_smoke.py

bootstrap-report:
	@python3 scripts/bootstrap_report.py

# ----------------------------------------------------------------
# Rung 0 RTL simulation targets
# ----------------------------------------------------------------

IVERILOG_SOURCES = \
  rtl/include/keystone86_pkg.sv \
  rtl/core/bus_interface.sv \
  rtl/core/prefetch_queue.sv \
  rtl/core/decoder.sv \
  rtl/core/microcode_rom.sv \
  rtl/core/microsequencer.sv \
  rtl/core/commit_engine.sv \
  rtl/core/cpu_top.sv \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung0_reset_loop.sv

IVERILOG_INCDIRS = -I rtl/include -I microcode/build

rung0-sim: ucode
	@echo "--- Rung 0: compiling RTL ---"
	@mkdir -p sim/build/rung0
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o sim/build/rung0/tb_rung0_reset_loop.vvp \
		$(IVERILOG_SOURCES)
	@echo "--- Rung 0: running simulation ---"
	vvp sim/build/rung0/tb_rung0_reset_loop.vvp

rung0-regress: ucode
	@echo "--- Rung 0 regression ---"
	@python3 scripts/rung0_regress.py

rung0-clean:
	@rm -rf sim/build/rung0
	@echo "Rung 0 build artifacts removed."

.PHONY: rung0-sim rung0-regress rung0-clean
# ----------------------------------------------------------------
# Rung 1 RTL simulation targets
# Added by: bringup/rung1-nop-dispatch
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG1 = \
  rtl/include/keystone86_pkg.sv \
  rtl/core/bus_interface.sv \
  rtl/core/prefetch_queue.sv \
  rtl/core/decoder.sv \
  rtl/core/microcode_rom.sv \
  rtl/core/microsequencer.sv \
  rtl/core/commit_engine.sv \
  rtl/core/cpu_top.sv \
  sim/tb/tb_rung1_nop_loop.sv

rung1-sim: ucode
	@echo "--- Rung 1: compiling RTL ---"
	@mkdir -p sim/build/rung1
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o sim/build/rung1/tb_rung1_nop_loop.vvp \
		$(IVERILOG_SOURCES_RUNG1)
	@echo "--- Rung 1: running simulation ---"
	vvp sim/build/rung1/tb_rung1_nop_loop.vvp

rung1-regress: ucode
	@echo "--- Rung 1 regression (includes Rung 0 baseline check) ---"
	@python3 scripts/rung1_regress.py

rung1-clean:
	@rm -rf sim/build/rung1
	@echo "Rung 1 build artifacts removed."

.PHONY: rung1-sim rung1-regress rung1-clean

# ----------------------------------------------------------------
# Rung 2 — JMP SHORT / JMP NEAR control-transfer
# Added by: bringup/rung2-jmp
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG2 = \
  rtl/include/keystone86_pkg.sv \
  rtl/core/bus_interface.sv \
  rtl/core/prefetch_queue.sv \
  rtl/core/decoder.sv \
  rtl/core/microcode_rom.sv \
  rtl/core/microsequencer.sv \
  rtl/core/commit_engine.sv \
  rtl/core/cpu_top.sv \
  sim/tb/tb_rung2_jmp.sv

rung2-sim: ucode
	@echo "--- Rung 2: compiling RTL ---"
	@mkdir -p sim/build/rung2
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o sim/build/rung2/tb_rung2_jmp.vvp \
		$(IVERILOG_SOURCES_RUNG2)
	@echo "--- Rung 2: running simulation ---"
	vvp sim/build/rung2/tb_rung2_jmp.vvp

rung2-regress: ucode
	@echo "--- Rung 2 regression (includes Rung 0 + Rung 1 baseline checks) ---"
	@python3 scripts/rung1_regress.py
	@echo "--- Rung 2: running Rung 2 testbench ---"
	@mkdir -p sim/build/rung2
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o sim/build/rung2/tb_rung2_jmp.vvp \
		$(IVERILOG_SOURCES_RUNG2)
	vvp sim/build/rung2/tb_rung2_jmp.vvp

rung2-clean:
	@rm -rf sim/build/rung2
	@echo "Rung 2 build artifacts removed."

.PHONY: rung2-sim rung2-regress rung2-clean
