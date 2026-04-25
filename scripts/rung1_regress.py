#!/usr/bin/env python3
"""
Keystone86 / Aegis — Rung 1 Regression Runner
scripts/rung1_regress.py

Runs the Rung 1 RTL simulation suite and reports pass/fail.
Rung 0 regression is also run to confirm no regressions.

Usage:
    python3 scripts/rung1_regress.py [--verbose]

Returns:
    0 on all tests passing
    1 on any failure
"""
import subprocess
import sys
import shutil
import argparse
from pathlib import Path

ROOT = Path(__file__).parent.parent

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
    "rtl/core/services/service_dispatch.sv",
    "rtl/core/cpu_top.sv",
]

TESTS = [
    {
        "name": "rung0_reset_loop",
        "tb": "tb_rung0_reset_loop",
        "sources": RTL_SOURCES_COMMON + [
            "sim/models/bootstrap_mem.sv",
            "sim/tb/tb_rung0_reset_loop.sv",
        ],
        "description": "Rung 0 baseline: reset, ENTRY_NULL, RAISE FC_UD, ENDI, FETCH_DECODE",
        "pass_marker": "ALL TESTS PASSED",
    },
    {
        "name": "rung1_nop_loop",
        "tb": "tb_rung1_nop_loop",
        "sources": RTL_SOURCES_COMMON + [
            "sim/tb/tb_rung1_nop_loop.sv",
        ],
        "description": "Rung 1: NOP classification, dispatch, EIP+1, 10 NOPs, 100 NOPs, no faults",
        "pass_marker": "ALL RUNG 1 TESTS PASSED",
    },
]

INCLUDE_DIRS = ["rtl/include", "build/microcode"]


def run_test(test: dict, sim_dir: Path, verbose: bool) -> bool:
    tb_name = test["tb"]
    out_bin = sim_dir / f"{tb_name}.vvp"

    inc_flags = []
    for d in INCLUDE_DIRS:
        inc_flags += ["-I", str(ROOT / d)]

    compile_cmd = (
        ["iverilog", "-g2012", "-Wall"]
        + inc_flags
        + ["-o", str(out_bin)]
        + [str(ROOT / s) for s in test["sources"]]
    )

    result = subprocess.run(
        compile_cmd,
        capture_output=not verbose,
        text=True,
        cwd=str(ROOT),
    )

    if result.returncode != 0:
        print(f"  COMPILE FAIL: {tb_name}")
        if result.stderr:
            print(result.stderr[:4000])
        return False

    result = subprocess.run(
        ["vvp", str(out_bin)],
        capture_output=not verbose,
        text=True,
        cwd=str(ROOT),
    )

    output = result.stdout + result.stderr
    if verbose:
        print(output)

    return test["pass_marker"] in output and result.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Keystone86 Rung 1 regression runner")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    print("Keystone86 / Aegis — Rung 1 Regression")
    print(f"Root: {ROOT}")
    print()

    missing = []
    for f in ["build/microcode/ucode.hex", "build/microcode/dispatch.hex"]:
        if not (ROOT / f).exists():
            missing.append(f"Missing: {f} — run 'make ucode' first")
    if not shutil.which("iverilog"):
        missing.append("iverilog not found")
    if missing:
        print("PREREQUISITE ERRORS:")
        for m in missing:
            print(f"  {m}")
        return 1

    sim_dir = ROOT / "build" / "sim" / "rung1"
    sim_dir.mkdir(parents=True, exist_ok=True)

    passed = failed = 0

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
    print("Rung 1 Regression Summary")
    print(f"  Passed: {passed}")
    print(f"  Failed: {failed}")
    print(f"  Total:  {passed + failed}")
    print()

    if failed == 0:
        print("RESULT: ALL RUNG 1 TESTS PASSED")
        print()
        print("Rung 1 gate criteria satisfied:")
        print("  [x] Rung 0 baseline still passes")
        print("  [x] 0x90 classified as ENTRY_NOP_XCHG_AX")
        print("  [x] Dispatch routes to bootstrap uPC 0x020")
        print("  [x] EIP advances by 1 per NOP")
        print("  [x] No spurious faults in NOP stream")
        print("  [x] 100 consecutive NOPs complete cleanly")
    else:
        print(f"RESULT: {failed} TEST(S) FAILED")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
