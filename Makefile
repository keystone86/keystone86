SHELL := /bin/bash

HOST_UID := $(shell id -u)
HOST_GID := $(shell id -g)

.PHONY: help require-container \
        tree spec-check lint ucode ucode-clean sim-smoke regress formal clean bootstrap-info \
        bootstrap-status namespace-check codegen spec-sync-status frozen-manifest-check \
        version-status release-notes ucode-bootstrap-check decode-dispatch-smoke \
        microseq-smoke commit-smoke service-abi-smoke prefetch-decode-smoke \
        bootstrap-report \
        rung0-sim rung0-regress rung0-clean \
        rung1-sim rung1-regress rung1-clean \
        rung2-sim rung2-regress rung2-clean \
        rung3-sim rung3-regress rung3-clean \
        rung4-sim rung4-regress rung4-clean \
        rung5-pass2-sim rung5-pass2-clean \
        dev dev-build dev-fpga

# Host-side targets:
#   make dev-build
#   make dev
#   make dev-fpga
#
# Project build, code generation, microcode, simulation, smoke-check,
# regression, formal, and cleanup targets are intended to run inside the
# Keystone86 dev container at /work.
#
# The container image sets KEYSTONE86_CONTAINER=1. Container-only targets use
# require-container as a light safety rail to avoid accidental native-host runs.

require-container:
	@if [ "$${KEYSTONE86_CONTAINER:-0}" != "1" ]; then \
		echo "ERROR: this target must be run inside the Keystone86 dev container."; \
		echo; \
		echo "Use:"; \
		echo "  make dev"; \
		echo; \
		echo "Then run this target again inside /work."; \
		exit 1; \
	fi

help:
	@echo "Keystone86 task runner"
	@echo ""
	@echo "Docker targets:"
	@echo "  make dev-build             - build the dev container image (first time + after Dockerfile changes)"
	@echo "  make dev                   - enter dev container (sim, formal, claude, codex)"
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
	@echo "  make rung4-sim             - compile and run Rung 4 RTL simulation"
	@echo "  make rung4-regress         - run Rung 4 regression (includes Rung 0 + Rung 1 + Rung 2 + Rung 3)"
	@echo "  make rung4-clean           - remove Rung 4 simulation artifacts"
	@echo "  make rung5-pass2-sim       - compile and run bounded Rung 5 Pass 2 INT_ENTER simulation"
	@echo "  make rung5-pass2-clean     - remove Rung 5 Pass 2 simulation artifacts"
	@echo "  make clean                 - remove all generated files"

# ----------------------------------------------------------------
# Docker dev environment
# ----------------------------------------------------------------

dev-build:
	docker build -t keystone86-dev -f docker/Dockerfile .

# Normal dev session — sim, formal, claude, codex, git
# Runtime user:
#   HOST_UID/HOST_GID are passed into the entrypoint so files created under
#   /work are owned by the host user, not root.
# Auth/session persistence:
#   Agent auth/config/session directories persist only in project-scoped Docker
#   named volumes. These volumes are convenience state only and are not project
#   authority. Do not mount native host ~/.codex or ~/.claude.
# SSH:
#   Mounts host ~/.ssh read-only for git push to GitHub.
# Gitconfig:
#   Mounts host ~/.gitconfig read-only for git identity.
dev:
	docker run --rm -it \
	  -e HOST_UID=$(HOST_UID) \
	  -e HOST_GID=$(HOST_GID) \
	  -e HOME=/home/dev \
	  -e KEYSTONE86_CONTAINER=1 \
	  -e GIT_CONFIG_COUNT=1 \
	  -e GIT_CONFIG_KEY_0=safe.directory \
	  -e GIT_CONFIG_VALUE_0=/work \
	  -v keystone86-claude-auth:/home/dev/.claude \
	  -v keystone86-codex-auth:/home/dev/.codex \
	  -v $(HOME)/.ssh:/home/dev/.ssh:ro \
	  -v $(HOME)/.gitconfig:/home/dev/.gitconfig:ro \
	  -v $(PWD):/work \
	  -w /work \
	  keystone86-dev

# Hardware session — adds USB passthrough for ECP5 flashing.
# Agent auth/config/session directories persist only in project-scoped Docker
# named volumes. These volumes are convenience state only and are not project
# authority. Not available in Codespaces (no USB access).
dev-fpga:
	docker run --rm -it \
	  -e HOST_UID=$(HOST_UID) \
	  -e HOST_GID=$(HOST_GID) \
	  -e HOME=/home/dev \
	  -e KEYSTONE86_CONTAINER=1 \
	  -e GIT_CONFIG_COUNT=1 \
	  -e GIT_CONFIG_KEY_0=safe.directory \
	  -e GIT_CONFIG_VALUE_0=/work \
	  -v keystone86-claude-auth:/home/dev/.claude \
	  -v keystone86-codex-auth:/home/dev/.codex \
	  -v $(HOME)/.ssh:/home/dev/.ssh:ro \
	  -v $(HOME)/.gitconfig:/home/dev/.gitconfig:ro \
	  -v $(PWD):/work \
	  -w /work \
	  --device /dev/bus/usb \
	  -v /dev/bus/usb:/dev/bus/usb \
	  --privileged \
	  keystone86-dev

# ----------------------------------------------------------------
# Project checks
# ----------------------------------------------------------------

tree: require-container
	@python3 scripts/tree.py .

spec-check: require-container
	@python3 scripts/spec_check.py

lint: require-container
	@python3 scripts/lint.py

bootstrap-info: require-container
	@echo "Keystone86 / Aegis bootstrap repository"

bootstrap-status: require-container
	@python3 scripts/bootstrap_status.py

namespace-check: require-container
	@python3 scripts/namespace_check.py

codegen: require-container
	@python3 scripts/codegen.py

spec-sync-status: require-container
	@python3 scripts/spec_sync_status.py

frozen-manifest-check: require-container
	@python3 scripts/frozen_manifest_check.py

version-status: require-container
	@python3 scripts/version_status.py

release-notes: require-container
	@python3 scripts/release_notes_stub.py

# ----------------------------------------------------------------
# Build — all generated artifacts go under build/
# ----------------------------------------------------------------

ucode: require-container
	@python3 scripts/ucode_build.py

ucode-bootstrap-check: require-container
	@python3 scripts/ucode_bootstrap_check.py

ucode-clean: require-container
	@rm -f build/microcode/ucode.hex build/microcode/dispatch.hex \
	       build/microcode/ucode.lst build/microcode/dispatch.lst
	@echo "Removed generated microcode outputs."

# ----------------------------------------------------------------
# Smoke checks
# ----------------------------------------------------------------

sim-smoke: require-container
	@python3 scripts/sim_smoke.py

regress: require-container
	@python3 scripts/regress.py

formal: require-container
	@python3 scripts/formal.py

decode-dispatch-smoke: require-container
	@python3 scripts/decode_dispatch_smoke.py

microseq-smoke: require-container
	@python3 scripts/microseq_smoke.py

commit-smoke: require-container
	@python3 scripts/commit_smoke.py

service-abi-smoke: require-container
	@python3 scripts/service_abi_smoke.py

prefetch-decode-smoke: require-container
	@python3 scripts/prefetch_decode_smoke.py

bootstrap-report: require-container
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
  rtl/core/services/operand_engine.sv \
  rtl/core/services/stack_engine.sv \
  rtl/core/services/interrupt_engine.sv \
  rtl/core/services/service_dispatch.sv \
  rtl/core/cpu_top.sv

# ----------------------------------------------------------------
# Rung 0 RTL simulation targets
# ----------------------------------------------------------------

IVERILOG_SOURCES = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung0_reset_loop.sv

rung0-sim: require-container ucode
	@echo "--- Rung 0: compiling RTL ---"
	@mkdir -p build/sim/rung0
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung0/tb_rung0_reset_loop.vvp \
		$(IVERILOG_SOURCES)
	@echo "--- Rung 0: running simulation ---"
	vvp build/sim/rung0/tb_rung0_reset_loop.vvp

rung0-regress: require-container ucode
	@echo "--- Rung 0 regression ---"
	@python3 scripts/rung0_regress.py

rung0-clean: require-container
	@rm -rf build/sim/rung0
	@echo "Rung 0 build artifacts removed."

# ----------------------------------------------------------------
# Rung 1 RTL simulation targets
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG1 = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung1_nop_loop.sv

rung1-sim: require-container ucode
	@echo "--- Rung 1: compiling RTL ---"
	@mkdir -p build/sim/rung1
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung1/tb_rung1_nop_loop.vvp \
		$(IVERILOG_SOURCES_RUNG1)
	@echo "--- Rung 1: running simulation ---"
	vvp build/sim/rung1/tb_rung1_nop_loop.vvp

rung1-regress: require-container ucode
	@echo "--- Rung 1 regression (includes Rung 0 baseline check) ---"
	@python3 scripts/rung1_regress.py

rung1-clean: require-container
	@rm -rf build/sim/rung1
	@echo "Rung 1 build artifacts removed."

# ----------------------------------------------------------------
# Rung 2 — JMP control-transfer
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG2 = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung2_jmp.sv

rung2-sim: require-container ucode
	@echo "--- Rung 2: compiling RTL ---"
	@mkdir -p build/sim/rung2
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung2/tb_rung2_jmp.vvp \
		$(IVERILOG_SOURCES_RUNG2)
	@echo "--- Rung 2: running simulation ---"
	vvp build/sim/rung2/tb_rung2_jmp.vvp

rung2-regress: require-container ucode
	@echo "--- Rung 2 regression (includes Rung 0 + Rung 1 baseline checks) ---"
	@python3 scripts/rung1_regress.py
	@echo "--- Rung 2: running Rung 2 testbench ---"
	@mkdir -p build/sim/rung2
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung2/tb_rung2_jmp.vvp \
		$(IVERILOG_SOURCES_RUNG2)
	vvp build/sim/rung2/tb_rung2_jmp.vvp

rung2-clean: require-container
	@rm -rf build/sim/rung2
	@echo "Rung 2 build artifacts removed."

# ----------------------------------------------------------------
# Rung 3 — Near CALL and near RET
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG3 = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung3_call_ret.sv

rung3-sim: require-container ucode
	@echo "--- Rung 3: compiling RTL ---"
	@mkdir -p build/sim/rung3
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung3/tb_rung3_call_ret.vvp \
		$(IVERILOG_SOURCES_RUNG3)
	@echo "--- Rung 3: running simulation ---"
	vvp build/sim/rung3/tb_rung3_call_ret.vvp

rung3-regress: require-container ucode
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

rung3-clean: require-container
	@rm -rf build/sim/rung3
	@echo "Rung 3 build artifacts removed."

# ----------------------------------------------------------------
# Rung 4 — Short Jcc
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG4 = \
  $(RTL_SOURCES_COMMON) \
  sim/models/bootstrap_mem.sv \
  sim/tb/tb_rung4_jcc.sv

rung4-sim: require-container ucode
	@echo "--- Rung 4: compiling RTL ---"
	@mkdir -p build/sim/rung4
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung4/tb_rung4_jcc.vvp \
		$(IVERILOG_SOURCES_RUNG4)
	@echo "--- Rung 4: running simulation ---"
	vvp build/sim/rung4/tb_rung4_jcc.vvp

rung4-regress: require-container ucode
	@echo "--- Rung 4 regression (includes Rung 0 + Rung 1 + Rung 2 + Rung 3 baseline checks) ---"
	$(MAKE) rung3-regress
	@mkdir -p build/sim/rung4
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung4/tb_rung4_jcc.vvp \
		$(IVERILOG_SOURCES_RUNG4)
	vvp build/sim/rung4/tb_rung4_jcc.vvp

rung4-clean: require-container
	@rm -rf build/sim/rung4
	@echo "Rung 4 build artifacts removed."

# ----------------------------------------------------------------
# Rung 5 Pass 2 — bounded INT_ENTER smoke
# ----------------------------------------------------------------

IVERILOG_SOURCES_RUNG5_PASS2 = \
  $(RTL_SOURCES_COMMON) \
  sim/tb/tb_rung5_int_enter.sv

rung5-pass2-sim: require-container ucode
	@echo "--- Rung 5 Pass 2: compiling bounded INT_ENTER RTL simulation ---"
	@mkdir -p build/sim/rung5_pass2
	iverilog -g2012 -Wall \
		$(IVERILOG_INCDIRS) \
		-o build/sim/rung5_pass2/tb_rung5_int_enter.vvp \
		$(IVERILOG_SOURCES_RUNG5_PASS2)
	@echo "--- Rung 5 Pass 2: running bounded INT_ENTER simulation ---"
	vvp build/sim/rung5_pass2/tb_rung5_int_enter.vvp

rung5-pass2-clean: require-container
	@rm -rf build/sim/rung5_pass2
	@echo "Rung 5 Pass 2 build artifacts removed."

# ----------------------------------------------------------------
# Clean — single build/ directory covers everything
# ----------------------------------------------------------------

clean: require-container
	@rm -rf build/
	@echo "Project clean complete."
