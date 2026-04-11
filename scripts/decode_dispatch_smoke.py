from pathlib import Path
import json
import re

root = Path('.')
cases = json.loads((root / 'sim/vectors/handcrafted/decode_dispatch_cases.json').read_text(encoding='utf-8'))
seed = json.loads((root / 'tools/spec_codegen/decode_dispatch_seed.json').read_text(encoding='utf-8'))
entry_defs = (root / 'rtl/include/entry_ids.svh').read_text(encoding='utf-8')

entry_map = {}
for line in entry_defs.splitlines():
    m = re.match(r'`define\s+(ENTRY_[A-Z0-9_]+)\s+8\'h([0-9A-Fa-f]+)', line.strip())
    if m:
        entry_map[m.group(1)] = int(m.group(2), 16)

failures = []

def resolve_expected(name):
    if name not in entry_map:
        failures.append(f'Expected entry symbol not found in entry_ids.svh: {name}')
        return None
    return entry_map[name]

for case in cases:
    expected = resolve_expected(case['expected_entry'])
    if expected is None:
        continue

    if case['kind'] == 'opcode':
        opcode_key = f"0x{case['opcode']:02X}"
        actual_name = seed['opcode_map'].get(opcode_key, seed['fallback_entry'])
    elif case['kind'] == 'symbolic':
        actual_name = seed['symbolic_map'].get(case['symbol'])
    else:
        failures.append(f"Unknown case kind: {case['kind']}")
        continue

    if actual_name is None:
        failures.append(f"{case['name']}: no actual mapping found")
        continue
    if actual_name not in entry_map:
        failures.append(f"{case['name']}: mapped to unknown entry symbol {actual_name}")
        continue

    actual = entry_map[actual_name]
    if actual != expected:
        failures.append(f"{case['name']}: expected {case['expected_entry']} got {actual_name}")

if failures:
    print('Decode/dispatch smoke failed:')
    for f in failures:
        print(' -', f)
    raise SystemExit(1)

print('Decode/dispatch smoke passed.')
for case in cases:
    print(' -', case['name'])
