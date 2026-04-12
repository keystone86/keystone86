#!/usr/bin/env python3
"""
Keystone86 / Aegis bootstrap ROM consistency check.
Verifies dispatch.hex and ucode.hex against expected bootstrap values.

Rung 1 note:
  ENTRY_NOP_XCHG_AX and ENTRY_PREFIX_ONLY now use ENDI CM_NOP|CM_EIP
  (word E00001C2) to enable visible EIP advancement.
  ENTRY_RESET uses ENDI CM_NOP (word E00001C0, no EIP commit).

Encoding uses correct Appendix A Section 7.1 format:
  bits[31:28] = UOP_CLASS (RAISE=0xC, ENDI=0xE)
  bits[9:0]   = IMM10 (commit mask for ENDI, fault class for RAISE)

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

# Correct Appendix A encodings with Rung 1 NOP update
EXPECTED_ROM = {
    0x000: 'E0000040',  # SUB_FAULT_HANDLER: ENDI CM_FAULT_END
    0x010: 'C1800000',  # ENTRY_NULL: RAISE FC_UD
    0x011: 'E0000040',  # ENTRY_NULL+1: ENDI CM_FAULT_END
    0x020: 'E00001C2',  # ENTRY_NOP_XCHG_AX: ENDI CM_NOP|CM_EIP  (Rung 1)
    0x030: 'E00001C2',  # ENTRY_PREFIX_ONLY: ENDI CM_NOP|CM_EIP   (Rung 1)
    0x040: 'E00001C0',  # ENTRY_RESET: ENDI CM_NOP
}

failures = []

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

# Validate UOP_CLASS fields are non-zero for RAISE and ENDI
if len(ucode_lines) == 4096:
    for addr, expected_enc in EXPECTED_ROM.items():
        word = int(ucode_lines[addr], 16)
        uc = (word >> 28) & 0xF
        if uc == 0 and int(expected_enc, 16) != 0:
            failures.append(f'ucode.hex[0x{addr:03X}]: UOP_CLASS=0 (NOP) for non-NOP instruction')

if failures:
    print('Bootstrap ROM check FAILED:')
    for f in failures:
        print(' -', f)
    sys.exit(1)

print('Bootstrap ROM check PASSED (Rung 1 encodings).')
print(f'  dispatch.hex: {len(dispatch_lines)} entries verified')
print(f'  ucode.hex: key addresses verified with Appendix A + Rung 1 encodings')
for idx, upc in EXPECTED_DISPATCH.items():
    sym = {0x00: 'ENTRY_NULL', 0x12: 'ENTRY_PREFIX_ONLY',
           0x13: 'ENTRY_NOP_XCHG_AX', 0xFF: 'ENTRY_RESET'}[idx]
    print(f'  dispatch[0x{idx:02X}] ({sym}) -> uPC 0x{upc:03X} OK')
