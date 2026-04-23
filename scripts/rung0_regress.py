#!/usr/bin/env python3
"""
Keystone86 / Aegis — Rung 0 Regression Runner
scripts/rung0_regress.py

Runs the Rung 0 RTL simulation suite and reports pass/fail.
"""

import subprocess
import sys
import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).parent.parent

RTL_SOURCES = [
    "rtl/include/entry_ids.svh",
    "rtl/include/fault_defs.svh",
    "rtl/include/commit_defs.svh",
    "rtl/include/field_defs.svh",
    "rtl/include/service_ids.svh",
    "rtl/include/keystone86_pkg.sv",
    "rtl/core/bus_interface.sv",
    "rtl/core/prefetch_queue.sv",
    "rtl/core/decoder.sv",
    "rtl/core/microcode_rom.sv",
    "rtl/core/microsequencer.sv",
    "rtl/core/commit_engine.sv",
    "rtl/core/services/fetch_engine.sv",
    "rtl/core/services/flow_control.sv",
    "rtl/core/services/service_dispatch.sv",
    "rtl/core/cpu_top.sv",
    "sim/models/bootstrap_mem.sv",
    "sim/tb/tb_rung0_reset_loop.sv",
]

INCLUDE_DIRS = [
    "rtl/include",
    "build/microcode",
]

TESTS = [
    {
        "name": "rung0_reset_loop",
        "tb": "tb_rung0_reset_loop",
        "description": "Reset vector, ENTRY_NULL dispatch, RAISE FC_UD, ENDI, FETCH_DECODE return, no-hang",
    }
]


def run_iverilog(test: dict, sim_dir: Path, verbose: bool) -> bool:
    tb_name = test["tb"]
    out_bin = sim_dir / f"{tb_name}.vvp"

    inc_flags = []
    for d in INCLUDE_DIRS:
        inc_flags += ["-I", str(ROOT / d)]

    compile_cmd = (
        ["iverilog", "-g2012", "-Wall"]
        + inc_flags
        + ["-o", str(out_bin)]
        + [str(ROOT / s) for s in RTL_SOURCES]
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

    return "ALL TESTS PASSED" in output and result.returncode == 0


def check_prerequisites() -> list[str]:
    missing = []

    for f in ["build/microcode/ucode.hex", "build/microcode/dispatch.hex"]:
        if not (ROOT / f).exists():
            missing.append(f"Missing: {f} — run 'make ucode' first")

    for s in RTL_SOURCES:
        if not (ROOT / s).exists():
            missing.append(f"Missing RTL source: {s}")

    if not shutil.which("iverilog"):
        missing.append("iverilog not found — install Icarus Verilog")

    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description="Keystone86 Rung 0 regression runner")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show full simulation output")
    parser.add_argument("--simulator", default="iverilog", choices=["iverilog"], help="Simulator to use")
    args = parser.parse_args()

    print("Keystone86 / Aegis — Rung 0 Regression")
    print(f"Root: {ROOT}")
    print()

    missing = check_prerequisites()
    if missing:
        print("PREREQUISITE ERRORS:")
        for m in missing:
            print(f"  {m}")
        return 1

    sim_dir = ROOT / "build" / "sim" / "rung0"
    sim_dir.mkdir(parents=True, exist_ok=True)

    passed = 0
    failed = 0

    for test in TESTS:
        print(f"Running: {test['name']}")
        print(f"  {test['description']}")
        ok = run_iverilog(test, sim_dir, args.verbose)
        if ok:
            print("  RESULT: PASS")
            passed += 1
        else:
            print("  RESULT: FAIL")
            failed += 1
        print()

    print("=" * 48)
    print("Rung 0 Regression Summary")
    print(f"  Passed: {passed}")
    print(f"  Failed: {failed}")
    print(f"  Total:  {passed + failed}")
    print()

    if failed == 0:
        print("RESULT: ALL RUNG 0 TESTS PASSED")
        print()
        print("Rung 0 gate criteria satisfied:")
        print("  [x] reset vector fetch at 0xFFFFFFF0")
        print("  [x] decoder stub emits ENTRY_NULL")
        print("  [x] dispatch table routes to bootstrap uPC 0x010")
        print("  [x] RAISE FC_UD staged")
        print("  [x] ENDI executed")
        print("  [x] microsequencer returned to FETCH_DECODE")
        print("  [x] no deadlock in bounded run")
    else:
        print(f"RESULT: {failed} TEST(S) FAILED")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())