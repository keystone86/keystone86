# Keystone86 Aegis Bootstrap Status Dashboard

This dashboard summarizes:
- the current bootstrap smoke checks
- which bring-up rung(s) they support
- what command runs them
- what still remains as future RTL-connected work

## Current bootstrap checks

| Check | Command | Supports rung(s) | Purpose |
|---|---|---|---|
| Frozen spec presence | `make spec-check` | Constitutional baseline | Verify frozen spec files are imported and non-placeholder |
| Frozen import manifest | `make frozen-manifest-check` | Constitutional baseline | Verify manifest tracks imported constitutional files |
| Namespace scaffold | `make namespace-check` | Rung 0+ | Verify shared enum/include/export files exist |
| Spec sync status | `make spec-sync-status` | Rung 0+ | Verify Appendix A import + codegen scaffold presence |
| Codegen | `make codegen` | Rung 0+ | Regenerate namespace artifacts from Appendix A codegen JSON |
| Bootstrap microcode build | `make ucode` | Rung 0 | Generate starter `ucode.hex`, `dispatch.hex`, `ucode.lst` |
| Bootstrap microcode mapping | `make ucode-bootstrap-check` | Rung 0 | Verify starter dispatch map and ROM seed consistency |
| Decode/dispatch smoke | `make decode-dispatch-smoke` | Rung 1 | Verify initial opcode-to-entry expectations |
| Microsequencer smoke | `make microseq-smoke` | Rung 0/1 | Verify reset/dispatch/ENDI loop expectations |
| Commit/ENDI smoke | `make commit-smoke` | Rung 0 | Verify basic commit-mask and clear-fault behavior |
| Service ABI smoke | `make service-abi-smoke` | Rung 0 | Verify `SVC` vs `SVCW` and `SR_OK/WAIT/FAULT` contract |
| Prefetch/decode smoke | `make prefetch-decode-smoke` | Rung 0/1 | Verify byte consumption, `M_NEXT_EIP`, ack/flush model |
| Version status | `make version-status` | Project hygiene | Verify versioning/release scaffold presence |

## RTL simulation targets

| Target | Command | Status |
|---|---|---|
| Rung 0: reset/fetch/decode loop | `make rung0-sim` | **Passing** |
| Rung 1: NOP/dispatch/EIP advance | `make rung1-sim` | **Passing** |
| Rung 2: JMP SHORT control transfer | `make rung2-sim` | **Passing** |

## Bootstrap rung support summary

| Rung | Status | Notes |
|---|---|---|
| Rung 0: reset/fetch/decode loop | **Passing** | RTL testbench proven: `tb_rung0_reset_loop.sv` |
| Rung 1: NOP/dispatch sanity | **Passing** | RTL testbench proven: `tb_rung1_nop_loop.sv` |
| Rung 2: JMP SHORT control transfer | **Passing** | RTL testbench proven: `tb_rung2_jmp.sv` |
| Rung 3+: broader decode/execution | Not yet started | Requires Rung 3 implementation work |

## What is still future work

- CALL / RET / JCC control-transfer family (Rung 3+)
- Broader decode coverage beyond current bring-up subset
- RTL-connected service-dispatch testbench
- True queue/decode FSM regression depth
- Extended microcode/service-path execution coverage
- Rung-gate pass/fail persistence infrastructure
