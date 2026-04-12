SHELL := /bin/bash

.PHONY: help tree spec-check lint ucode ucode-clean sim-smoke regress formal clean bootstrap-info

help:
	@echo "Keystone86 task runner"
	@echo ""
	@echo "Targets:"
	@echo "  make tree         - print repo tree"
	@echo "  make spec-check   - verify frozen spec files exist"
	@echo "  make lint         - run placeholder lint checks"
	@echo "  make ucode        - run placeholder microcode build"
	@echo "  make ucode-clean  - clean generated microcode artifacts"
	@echo "  make sim-smoke    - run placeholder smoke simulation"
	@echo "  make regress      - run placeholder regression suite"
	@echo "  make formal       - run placeholder formal checks"
	@echo "  make clean        - remove generated files"

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

clean: ucode-clean
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
# Added by: bringup/rung0-reset-fetch-loop
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

rung0-sim:
	@echo "--- Rung 0: compiling RTL ---"
	@mkdir -p sim/build/rung0
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o sim/build/rung0/tb_rung0_reset_loop.vvp \
		$(IVERILOG_SOURCES)
	@echo "--- Rung 0: running simulation ---"
	vvp sim/build/rung0/tb_rung0_reset_loop.vvp

rung0-regress:
	@echo "--- Rung 0 regression ---"
	@python3 scripts/rung0_regress.py

rung0-clean:
	@rm -rf sim/build/rung0
	@echo "Rung 0 build artifacts removed."

.PHONY: rung0-sim rung0-regress rung0-clean
