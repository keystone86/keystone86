from pathlib import Path
import json
import re

root = Path('.')
cases = json.loads((root / 'sim/vectors/handcrafted/service_abi_cases.json').read_text(encoding='utf-8'))
seed = json.loads((root / 'tools/spec_codegen/service_abi_seed.json').read_text(encoding='utf-8'))
fault_defs = (root / 'rtl/include/fault_defs.svh').read_text(encoding='utf-8')

sr_symbols = set()
for line in fault_defs.splitlines():
    m = re.match(r'`define\s+(SR_[A-Z]+)\s+', line.strip())
    if m:
        sr_symbols.add(m.group(1))

failures = []
for case in cases:
    svc = case['service']
    if svc not in seed['service_contracts']:
        failures.append(f"{case['name']}: unknown service {svc}")
        continue

    contract = seed['service_contracts'][svc]
    invoke = case['invoke']
    valid = True

    if seed['invoke_rules']['require_svcw_if_may_wait'] and contract['may_wait'] and invoke != 'SVCW':
        valid = False
        actual_sr = 'VIOLATION'
    else:
        actual_sr = contract['sample_sr']

    if valid != case['expected_valid']:
        failures.append(f"{case['name']}: expected valid={case['expected_valid']} got {valid}")

    if actual_sr != case['expected_sr']:
        failures.append(f"{case['name']}: expected sr={case['expected_sr']} got {actual_sr}")

    if actual_sr.startswith('SR_') and actual_sr not in sr_symbols:
        failures.append(f"{case['name']}: SR symbol missing from rtl/include/fault_defs.svh: {actual_sr}")

if failures:
    print('Service ABI smoke failed:')
    for f in failures:
        print(' -', f)
    raise SystemExit(1)

print('Service ABI smoke passed.')
for case in cases:
    print(' -', case['name'])
