#!/usr/bin/env python3
"""
Keystone86 / Aegis — Rung 2 Regression Runner

Runs the required earlier-rung baselines plus the active bounded Rung 2
direct-JMP regression target.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

RTL_SOURCES_COMMON = [
    "rtl/include/keystone86_pkg.sv",
    "rtl/core/bus_interface.sv",
    "rtl/core/prefetch_queue.sv",
    "rtl/core/decoder.sv",
    "rtl/core/microcode_rom.sv",
    "rtl/core/microsequencer.sv",
    "rtl/core/commit_engine.sv",
    "rtl/core/services/fetch_engine.sv",
    "rtl/core/services/flow_control.sv",
    "rtl/core/services/operand_engine.sv",
    "rtl/core/services/stack_engine.sv",
    "rtl/core/services/interrupt_engine.sv",
    "rtl/core/services/service_dispatch.sv",
    "rtl/core/cpu_top.sv",
]

TESTS = [
    {
        "name": "rung0_reset_loop",
        "sources": RTL_SOURCES_COMMON + [
            "sim/models/bootstrap_mem.sv",
            "sim/tb/tb_rung0_reset_loop.sv",
        ],
        "description": "Rung 0 baseline: reset, ENTRY_NULL, RAISE FC_UD, ENDI, FETCH_DECODE",
        "pass_marker": "RESULT: PASS",
    },
    {
        "name": "rung1_nop_loop",
        "sources": RTL_SOURCES_COMMON + [
            "sim/tb/tb_rung1_nop_loop.sv",
        ],
        "description": "Rung 1: NOP classification, dispatch, EIP+1, 10 NOPs, 100 NOPs, no faults",
        "pass_marker": "RESULT: PASS",
    },
    {
        "name": "rung2_jmp",
        "sources": RTL_SOURCES_COMMON + [
            "sim/models/bootstrap_mem.sv",
            "sim/tb/tb_rung2_jmp.sv",
        ],
        "description": "Rung 2: bounded direct JMP service path, committed redirect, bounded self-loop",
        "pass_marker": "RESULT: ALL RUNG 2 TESTS PASSED",
    },
]

INCLUDE_DIRS = ["rtl/include", "build/microcode"]


def run_test(test: dict, sim_dir: Path, verbose: bool) -> bool:
    tb_name = test["name"]
    out_bin = sim_dir / f"{tb_name}.vvp"

    inc_flags: list[str] = []
    for inc in INCLUDE_DIRS:
        inc_flags += ["-I", str(ROOT / inc)]

    compile_cmd = (
        ["iverilog", "-g2012", "-Wall"]
        + inc_flags
        + ["-o", str(out_bin)]
        + [str(ROOT / src) for src in test["sources"]]
    )

    compile_result = subprocess.run(
        compile_cmd,
        capture_output=not verbose,
        text=True,
        cwd=str(ROOT),
    )
    if compile_result.returncode != 0:
        print(f"  COMPILE FAIL: {tb_name}")
        if compile_result.stderr:
            print(compile_result.stderr[:4000])
        return False

    run_result = subprocess.run(
        ["vvp", str(out_bin)],
        capture_output=not verbose,
        text=True,
        cwd=str(ROOT),
    )
    output = (run_result.stdout or "") + (run_result.stderr or "")

    if verbose:
        print(output, end="" if output.endswith("\n") else "\n")
    else:
        for line in output.splitlines():
            if "RESULT" in line or "PASS" in line or "FAIL" in line:
                print(f"    {line}")

    return run_result.returncode == 0 and test["pass_marker"] in output


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Keystone86 / Aegis Rung 2 regression runner"
    )
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    print("Keystone86 / Aegis — Rung 2 Regression")
    print(f"Root: {ROOT}")
    print()

    prereq_errors: list[str] = []
    for required in ["build/microcode/ucode.hex", "build/microcode/dispatch.hex"]:
        if not (ROOT / required).exists():
            prereq_errors.append(f"Missing: {required} — run 'make ucode' first")
    if not shutil.which("iverilog"):
        prereq_errors.append("iverilog not found in PATH")

    if prereq_errors:
        print("PREREQUISITE ERRORS:")
        for msg in prereq_errors:
            print(f"  {msg}")
        return 1

    sim_dir = ROOT / "build" / "sim" / "rung2"
    sim_dir.mkdir(parents=True, exist_ok=True)

    passed = 0
    failed = 0

    for test in TESTS:
        print(f"Running: {test['name']}")
        print(f"  {test['description']}")
        ok = run_test(test, sim_dir, args.verbose)
        if ok:
            print("  RESULT: PASS")
            passed += 1
        else:
            print("  RESULT: FAIL")
            failed += 1
        print()

    print("=" * 48)
    print("Rung 2 Regression Summary")
    print(f"  Passed: {passed}")
    print(f"  Failed: {failed}")
    print(f"  Total:  {passed + failed}")
    print()

    if failed == 0:
        print("RESULT: ALL RUNG 2 TESTS PASSED")
        print()
        print("Rung 2 gate criteria satisfied:")
        print("  [x] Rung 0 baseline still passes")
        print("  [x] Rung 1 baseline still passes")
        print("  [x] Bounded direct JMP service path passes")
        print("  [x] Committed redirect occurs at ENDI")
        print("  [x] Committed redirect flush is observed")
        print("  [x] No fault in bounded direct JMP loop")
        print("  [x] Active decoded entry remains ENTRY_JMP_NEAR")
        return 0

    print(f"RESULT: {failed} TEST(S) FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
