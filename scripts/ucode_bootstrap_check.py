#!/usr/bin/env python3
"""
Keystone86 / Aegis bootstrap ROM consistency check.
Verifies that dispatch.hex, ucode.hex, and ucode.lst are mutually consistent
for the four bootstrap entries.

Run from repo root: python3 scripts/ucode_bootstrap_check.py
"""
from pathlib import Path
import sys

root = Path('.')

EXPECTED_DISPATCH = {
    0x00: 0x010,   # ENTRY_NULL
    0x12: 0x030,   # ENTRY_PREFIX_ONLY
    0x13: 0x020,   # ENTRY_NOP_XCHG_AX
    0xFF: 0x040,   # ENTRY_RESET
}

EXPECTED_ROM = {
    0x000: '0000E040',  # SUB_FAULT_HANDLER: ENDI CM_FAULT_END
    0x010: '0000C600',  # ENTRY_NULL: RAISE FC_UD
    0x011: '0000E040',  # ENTRY_NULL+1: ENDI CM_FAULT_END
    0x020: '0000E3C0',  # ENTRY_NOP_XCHG_AX: ENDI CM_NOP
    0x030: '0000E3C0',  # ENTRY_PREFIX_ONLY: ENDI CM_NOP
    0x040: '0000E3C0',  # ENTRY_RESET: ENDI CM_NOP
}

failures = []

# --- Check dispatch.hex ---
dispatch_path = root / 'microcode/build/dispatch.hex'
if not dispatch_path.exists():
    print('FAIL: microcode/build/dispatch.hex not found')
    sys.exit(1)

dispatch_lines = [l.strip() for l in dispatch_path.read_text().splitlines()
                  if l.strip() and not l.startswith(';')]

if len(dispatch_lines) != 256:
    failures.append(f'dispatch.hex: expected 256 entries, got {len(dispatch_lines)}')
else:
    for idx, expected_upc in EXPECTED_DISPATCH.items():
        actual_upc = int(dispatch_lines[idx], 16)
        if actual_upc != expected_upc:
            sym = {0x00: 'ENTRY_NULL', 0x12: 'ENTRY_PREFIX_ONLY',
                   0x13: 'ENTRY_NOP_XCHG_AX', 0xFF: 'ENTRY_RESET'}[idx]
            failures.append(
                f'dispatch.hex[0x{idx:02X}] ({sym}): '
                f'expected 0x{expected_upc:03X}, got 0x{actual_upc:03X}')

# --- Check ucode.hex ---
ucode_path = root / 'microcode/build/ucode.hex'
if not ucode_path.exists():
    print('FAIL: microcode/build/ucode.hex not found')
    sys.exit(1)

ucode_lines = [l.strip() for l in ucode_path.read_text().splitlines()
               if l.strip() and not l.startswith(';')]

if len(ucode_lines) != 4096:
    failures.append(f'ucode.hex: expected 4096 lines, got {len(ucode_lines)}')
else:
    for addr, expected_enc in EXPECTED_ROM.items():
        actual_enc = ucode_lines[addr].upper()
        if actual_enc != expected_enc.upper():
            failures.append(
                f'ucode.hex[0x{addr:03X}]: expected {expected_enc}, got {actual_enc}')

# --- Report ---
if failures:
    print('Bootstrap ROM check FAILED:')
    for f in failures:
        print(' -', f)
    sys.exit(1)

print('Bootstrap ROM check PASSED.')
print(f'  dispatch.hex: {len(dispatch_lines)} entries verified')
print(f'  ucode.hex: key addresses verified')
for idx, upc in EXPECTED_DISPATCH.items():
    sym = {0x00: 'ENTRY_NULL', 0x12: 'ENTRY_PREFIX_ONLY',
           0x13: 'ENTRY_NOP_XCHG_AX', 0xFF: 'ENTRY_RESET'}[idx]
    print(f'  dispatch[0x{idx:02X}] ({sym}) -> uPC 0x{upc:03X} OK')
