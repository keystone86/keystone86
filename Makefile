SHELL := /bin/bash

.PHONY: help tree spec-check lint ucode ucode-clean sim-smoke regress formal clean bootstrap-info \
        dev dev-build dev-fpga

help:
	@echo "Keystone86 task runner"
	@echo ""
	@echo "Docker targets:"
	@echo "  make dev-build             - build the dev container image (first time + after Dockerfile changes)"
	@echo "  make dev                   - enter dev container (sim, formal, claude)"
	@echo "  make dev-fpga              - enter dev container with USB passthrough (ECP5 flashing)"
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
	@echo "  make rung3-sim             - compile and run Rung 3 RTL simulation"
	@echo "  make rung3-regress         - run Rung 3 regression (includes Rung 0 + Rung 1 + Rung 2)"
	@echo "  make rung3-clean           - remove Rung 3 simulation artifacts"
	@echo "  make clean                 - remove all generated files"

# ----------------------------------------------------------------
# Docker dev environment
# ----------------------------------------------------------------

dev-build:
	docker build -t keystone86-dev -f docker/Dockerfile .

# Normal dev session — sim, formal, claude, git
# Auth: named volume persists Claude Code credentials (login once per machine)
# SSH: mounts host ~/.ssh read-only for git push to GitHub
# Gitconfig: mounts host ~/.gitconfig read-only for git identity
# ANTHROPIC_API_KEY passed through as fallback for Codespaces
dev:
	docker run --rm -it \
	  -v keystone86-claude-auth:/root/.claude \
	  -v $(HOME)/.ssh:/root/.ssh:ro \
	  -v $(HOME)/.gitconfig:/root/.gitconfig:ro \
	  -e ANTHROPIC_API_KEY=$(ANTHROPIC_API_KEY) \
	  -v $(PWD):/work \
	  -w /work \
	  keystone86-dev \
	  bash -c 'git config --global --add safe.directory /work; exec bash'

# Hardware session — adds USB passthrough for ECP5 flashing
# Not available in Codespaces (no USB access)
dev-fpga:
	docker run --rm -it \
	  -v keystone86-claude-auth:/root/.claude \
	  -v $(HOME)/.ssh:/root/.ssh:ro \
	  -v $(HOME)/.gitconfig:/root/.gitconfig:ro \
	  -e ANTHROPIC_API_KEY=$(ANTHROPIC_API_KEY) \
	  -v $(PWD):/work \
	  -w /work \
	  --device /dev/bus/usb \
	  -v /dev/bus/usb:/dev/bus/usb \
	  --privileged \
	  keystone86-dev \
	  bash -c 'git config --global --add safe.directory /work; exec bash'

# ----------------------------------------------------------------
# Project checks
# ----------------------------------------------------------------

tree:
	@python3 scripts/tree.py .

spec-check:
	@python3 scripts/spec_check.py

lint:
	@python3 scripts/lint.py

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

# ----------------------------------------------------------------
# Build — all generated artifacts go under build/
# ----------------------------------------------------------------

ucode:
	@python3 scripts/ucode_build.py

ucode-bootstrap-check:
	@python3 scripts/ucode_bootstrap_check.py

ucode-clean:
	@rm -f build/microcode/ucode.hex build/microcode/dispatch.hex \
	       build/microcode/ucode.lst build/microcode/dispatch.lst
	@echo "Removed generated microcode outputs."

# ----------------------------------------------------------------
# Smoke checks (host-side, no RTL simulation)
# ----------------------------------------------------------------

sim-smoke:
	@python3 scripts/sim_smoke.py

regress:
	@python3 scripts/regress.py

formal:
	@python3 scripts/formal.py

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
# Shared RTL source lists and include paths
# All build artifacts go under build/ — never into source directories
# ----------------------------------------------------------------

IVERILOG_INCDIRS = -I rtl/include -I build/microcode

RTL_SOURCES_COMMON = \
  rtl/include/keystone86_pkg.sv \
  rtl/core/bus_interface.sv \
  rtl/core/prefetch_queue.sv \
  rtl/core/decoder.sv \
  rtl/core/microcode_rom.sv \
  rtl/core/microsequencer.sv \
  rtl/core/commit_engine.sv \
  rtl/core/services/fetch_engine.sv \
  rtl/core/services/flow_control.sv \
  rtl/core/services/service_dispatch.sv \
  rtl/core/cpu_top.sv

# ----------------------------------------------------------------
# Rung 0 RTL simulation targets
# ----------------------------------------------------------------

IVERILOG_SOURCES = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung0_reset_loop.sv

rung0-sim: ucode
	@echo "--- Rung 0: compiling RTL ---"
	@mkdir -p build/sim/rung0
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung0/tb_rung0_reset_loop.vvp \
		$(IVERILOG_SOURCES)
	@echo "--- Rung 0: running simulation ---"
	vvp build/sim/rung0/tb_rung0_reset_loop.vvp

rung0-regress: ucode
	@echo "--- Rung 0 regression ---"
	@python3 scripts/rung0_regress.py

rung0-clean:
	@rm -rf build/sim/rung0
	@echo "Rung 0 build artifacts removed."

.PHONY: rung0-sim rung0-regress rung0-clean

# ----------------------------------------------------------------
# Rung 1 RTL simulation targets
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG1 = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung1_nop_loop.sv

rung1-sim: ucode
	@echo "--- Rung 1: compiling RTL ---"
	@mkdir -p build/sim/rung1
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung1/tb_rung1_nop_loop.vvp \
		$(IVERILOG_SOURCES_RUNG1)
	@echo "--- Rung 1: running simulation ---"
	vvp build/sim/rung1/tb_rung1_nop_loop.vvp

rung1-regress: ucode
	@echo "--- Rung 1 regression (includes Rung 0 baseline check) ---"
	@python3 scripts/rung1_regress.py

rung1-clean:
	@rm -rf build/sim/rung1
	@echo "Rung 1 build artifacts removed."

.PHONY: rung1-sim rung1-regress rung1-clean

# ----------------------------------------------------------------
# Rung 2 — JMP control-transfer
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG2 = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung2_jmp.sv

rung2-sim: ucode
	@echo "--- Rung 2: compiling RTL ---"
	@mkdir -p build/sim/rung2
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung2/tb_rung2_jmp.vvp \
		$(IVERILOG_SOURCES_RUNG2)
	@echo "--- Rung 2: running simulation ---"
	vvp build/sim/rung2/tb_rung2_jmp.vvp

rung2-regress: ucode
	@echo "--- Rung 2 regression (includes Rung 0 + Rung 1 baseline checks) ---"
	@python3 scripts/rung1_regress.py
	@echo "--- Rung 2: running Rung 2 testbench ---"
	@mkdir -p build/sim/rung2
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung2/tb_rung2_jmp.vvp \
		$(IVERILOG_SOURCES_RUNG2)
	vvp build/sim/rung2/tb_rung2_jmp.vvp

rung2-clean:
	@rm -rf build/sim/rung2
	@echo "Rung 2 build artifacts removed."

.PHONY: rung2-sim rung2-regress rung2-clean

# ----------------------------------------------------------------
# Rung 3 — Near CALL and near RET
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG3 = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung3_call_ret.sv

rung3-sim: ucode
	@echo "--- Rung 3: compiling RTL ---"
	@mkdir -p build/sim/rung3
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung3/tb_rung3_call_ret.vvp \
		$(IVERILOG_SOURCES_RUNG3)
	@echo "--- Rung 3: running simulation ---"
	vvp build/sim/rung3/tb_rung3_call_ret.vvp

rung3-regress: ucode
	@echo "--- Rung 3 regression (includes Rung 0 + Rung 1 + Rung 2 baseline checks) ---"
	@python3 scripts/rung1_regress.py
	@mkdir -p build/sim/rung2
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung2/tb_rung2_jmp.vvp \
		$(IVERILOG_SOURCES_RUNG2)
	vvp build/sim/rung2/tb_rung2_jmp.vvp
	@mkdir -p build/sim/rung3
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung3/tb_rung3_call_ret.vvp \
		$(IVERILOG_SOURCES_RUNG3)
	vvp build/sim/rung3/tb_rung3_call_ret.vvp

rung3-clean:
	@rm -rf build/sim/rung3
	@echo "Rung 3 build artifacts removed."

.PHONY: rung3-sim rung3-regress rung3-clean

# ----------------------------------------------------------------
# Clean — single build/ directory covers everything
# ----------------------------------------------------------------

clean:
	@rm -rf build/
	@echo "Project clean complete."
