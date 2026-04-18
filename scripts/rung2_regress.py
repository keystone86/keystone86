#!/usr/bin/env python3
"""
Keystone86 / Aegis — Rung 2 Regression Runner
scripts/rung2_regress.py

Runs Rung 0 + Rung 1 + Rung 2 tests.
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
        "pass_marker": "ALL TESTS PASSED",
    },
    {
        "name": "rung1_nop_loop",
        "sources": RTL_SOURCES_COMMON + [
            "sim/tb/tb_rung1_nop_loop.sv",
        ],
        "description": "Rung 1 baseline: NOP classification, EIP+1, prefix-only",
        "pass_marker": "ALL RUNG 1 TESTS PASSED",
    },
    {
        "name": "rung2_jmp_near",
        "sources": RTL_SOURCES_COMMON + [
            "sim/tb/tb_rung2_jmp_near.sv",
        ],
        "description": "Rung 2: EB/E9 near JMP, self-loop, forward/backward, flush",
        "pass_marker": "ALL RUNG 2 TESTS PASSED",
    },
]

INCLUDE_DIRS = ["rtl/include", "microcode/build"]


def run_test(test: dict, sim_dir: Path, verbose: bool) -> bool:
    tb_name = test["name"]
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
    result = subprocess.run(compile_cmd, capture_output=not verbose,
                            text=True, cwd=str(ROOT))
    if result.returncode != 0:
        print(f"  COMPILE FAIL: {tb_name}")
        if result.stderr:
            print(result.stderr[:3000])
        return False

    result = subprocess.run(["vvp", str(out_bin)],
                            capture_output=not verbose, text=True, cwd=str(ROOT))
    output = result.stdout + result.stderr
    if verbose:
        print(output)
    else:
        # Always show the summary lines
        for line in output.splitlines():
            if "PASS" in line or "FAIL" in line or "===" in line or "RESULT" in line:
                print(f"    {line}")
    return test["pass_marker"] in output and result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description="Keystone86 Rung 2 regression runner")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    print("Keystone86 / Aegis — Rung 2 Regression")
    print(f"Root: {ROOT}")
    print()

    missing = []
    for f in ["microcode/build/ucode.hex", "microcode/build/dispatch.hex"]:
        if not (ROOT / f).exists():
            missing.append(f"Missing: {f} — run 'make ucode' first")
    if not shutil.which("iverilog"):
        missing.append("iverilog not found")
    if missing:
        print("PREREQUISITE ERRORS:")
        for m in missing:
            print(f"  {m}")
        return 1

    sim_dir = ROOT / "sim" / "build" / "rung2"
    sim_dir.mkdir(parents=True, exist_ok=True)

    passed = failed = 0
    for test in TESTS:
        print(f"Running: {test['name']}")
        print(f"  {test['description']}")
        ok = run_test(test, sim_dir, args.verbose)
        if ok:
            print(f"  RESULT: PASS")
            passed += 1
        else:
            print(f"  RESULT: FAIL")
            failed += 1
        print()

    print("=" * 48)
    print(f"Rung 2 Regression Summary")
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
        print("  [x] EB/E9 decoded as ENTRY_JMP_NEAR")
        print("  [x] Dispatch to bootstrap uPC 0x050")
        print("  [x] No spurious fault on valid JMP")
        print("  [x] EIP commits to jump target")
        print("  [x] Prefetch queue flushed after JMP")
        print("  [x] EB FE self-loop stable for 1000 cycles")
        print("  [x] Forward and backward short jumps correct")
        print("  [x] E9 near relative jump correct")
    else:
        print(f"RESULT: {failed} TEST(S) FAILED")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
