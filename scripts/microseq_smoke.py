from pathlib import Path
import json
import re

root = Path('.')
cases = json.loads((root / 'sim/vectors/handcrafted/microseq_smoke_cases.json').read_text(encoding='utf-8'))
seed = json.loads((root / 'tools/spec_codegen/microseq_bootstrap_seed.json').read_text(encoding='utf-8'))
entry_defs = (root / 'rtl/include/entry_ids.svh').read_text(encoding='utf-8')

entry_map = {}
for line in entry_defs.splitlines():
    m = re.match(r"`define\s+(ENTRY_[A-Z0-9_]+)\s+8'h([0-9A-Fa-f]+)", line.strip())
    if m:
        entry_map[m.group(1)] = int(m.group(2), 16)

dispatch_hex = (root / 'build/microcode/dispatch.hex').read_text(encoding='utf-8').splitlines()
dispatch_vals = [x.strip() for x in dispatch_hex if x.strip() and not x.startswith(';')]

failures = []

for case in cases:
    sym = case['dispatch_symbol']
    if sym not in entry_map:
        failures.append(f"{case['name']}: entry symbol not found: {sym}")
        continue

    idx = entry_map[sym]
    expected_upc = int(case['expected_upc'], 16)
    seed_upc = int(seed['dispatch_upc'][sym], 16) if sym in seed['dispatch_upc'] else None
    actual_upc = int(dispatch_vals[idx], 16) if idx < len(dispatch_vals) else None

    if seed_upc is None:
        failures.append(f"{case['name']}: no seed dispatch mapping for {sym}")
        continue
    if seed_upc != expected_upc:
        failures.append(f"{case['name']}: seed upc mismatch expected {expected_upc:#05x} got {seed_upc:#05x}")
    if actual_upc is None:
        failures.append(f"{case['name']}: dispatch.hex missing entry index {idx:#04x}")
        continue
    if actual_upc != expected_upc:
        failures.append(f"{case['name']}: dispatch.hex expected {expected_upc:#05x} got {actual_upc:#05x}")

    next_state = seed['endi_behavior']['next_state']
    if next_state != case['expected_next_state_after_endi']:
        failures.append(
            f"{case['name']}: ENDI next state expected {case['expected_next_state_after_endi']} got {next_state}"
        )

if failures:
    print('Microsequencer smoke failed:')
    for f in failures:
        print(' -', f)
    raise SystemExit(1)

print('Microsequencer smoke passed.')
for case in cases:
    print(' -', case['name'])
