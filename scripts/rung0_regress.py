#!/usr/bin/env python3
"""
Keystone86 / Aegis — Rung 0 Regression Runner
scripts/rung0_regress.py

Runs the Rung 0 RTL simulation suite and reports pass/fail.

Usage:
    python3 scripts/rung0_regress.py [--simulator iverilog|verilator]

Requirements:
    Icarus Verilog (iverilog/vvp) — default
    or Verilator (verilator) — optional

Returns:
    0 on all tests passing
    1 on any failure
"""

import subprocess
import sys
import os
import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).parent.parent

# RTL source files (Rung 0 only)
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
    "rtl/core/cpu_top.sv",
    "sim/models/bootstrap_mem.sv",
    "sim/tb/tb_rung0_reset_loop.sv",
]

# Include directories
INCLUDE_DIRS = [
    "rtl/include",
    "microcode/build",
]

TESTS = [
    {
        "name": "rung0_reset_loop",
        "tb": "tb_rung0_reset_loop",
        "description": "Reset vector, ENTRY_NULL dispatch, RAISE FC_UD, ENDI, FETCH_DECODE return, no-hang",
    }
]


def run_iverilog(test: dict, sim_dir: Path, verbose: bool) -> bool:
    """Compile and run one test with Icarus Verilog."""
    tb_name = test["tb"]
    out_bin = sim_dir / f"{tb_name}.vvp"

    # Build include flags
    inc_flags = []
    for d in INCLUDE_DIRS:
        inc_flags += ["-I", str(ROOT / d)]

    # Add microcode build directory to search path (for $readmemh)
    # by running from root so relative paths in .sv files resolve
    compile_cmd = (
        ["iverilog", "-g2012", "-Wall"]
        + inc_flags
        + ["-o", str(out_bin)]
        + [str(ROOT / s) for s in RTL_SOURCES]
    )

    if verbose:
        print(f"  Compile: {' '.join(str(x) for x in compile_cmd)}")

    result = subprocess.run(
        compile_cmd,
        capture_output=not verbose,
        text=True,
        cwd=str(ROOT),
    )

    if result.returncode != 0:
        print(f"  COMPILE FAIL: {tb_name}")
        if result.stderr:
            print(result.stderr[:2000])
        return False

    # Run simulation
    run_cmd = ["vvp", str(out_bin)]
    if verbose:
        print(f"  Run: {' '.join(run_cmd)}")

    result = subprocess.run(
        run_cmd,
        capture_output=not verbose,
        text=True,
        cwd=str(ROOT),
    )

    output = result.stdout + result.stderr
    if verbose:
        print(output)

    # Check output for pass/fail markers
    if "ALL TESTS PASSED" in output and result.returncode == 0:
        return True
    if "FAIL" in output or result.returncode != 0:
        if not verbose:
            print(output[:3000])
        return False

    # If $finish was called normally, check for pass string
    return "ALL TESTS PASSED" in output


def check_prerequisites() -> list[str]:
    """Check that required files and tools exist."""
    missing = []

    # Check microcode artifacts exist
    for f in ["microcode/build/ucode.hex", "microcode/build/dispatch.hex"]:
        if not (ROOT / f).exists():
            missing.append(f"Missing: {f} — run 'make ucode' first")

    # Check RTL sources exist
    for s in RTL_SOURCES:
        if not (ROOT / s).exists():
            missing.append(f"Missing RTL source: {s}")

    # Check simulator
    if not shutil.which("iverilog"):
        missing.append("iverilog not found — install Icarus Verilog")

    return missing


def main():
    parser = argparse.ArgumentParser(description="Keystone86 Rung 0 regression runner")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Show full simulation output")
    parser.add_argument("--simulator", default="iverilog",
                        choices=["iverilog"],
                        help="Simulator to use")
    args = parser.parse_args()

    print("Keystone86 / Aegis — Rung 0 Regression")
    print(f"Root: {ROOT}")
    print()

    # Prerequisites check
    missing = check_prerequisites()
    if missing:
        print("PREREQUISITE ERRORS:")
        for m in missing:
            print(f"  {m}")
        return 1

    # Create sim output directory
    sim_dir = ROOT / "sim" / "build" / "rung0"
    sim_dir.mkdir(parents=True, exist_ok=True)

    # Run tests
    passed = 0
    failed = 0
    results = []

    for test in TESTS:
        print(f"Running: {test['name']}")
        print(f"  {test['description']}")
        ok = run_iverilog(test, sim_dir, args.verbose)
        if ok:
            print(f"  RESULT: PASS")
            passed += 1
        else:
            print(f"  RESULT: FAIL")
            failed += 1
        results.append((test["name"], ok))
        print()

    # Summary
    print("=" * 48)
    print(f"Rung 0 Regression Summary")
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
