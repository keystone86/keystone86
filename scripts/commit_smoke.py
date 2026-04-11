from pathlib import Path
import json

root = Path('.')
cases = json.loads((root / 'sim/vectors/handcrafted/commit_smoke_cases.json').read_text(encoding='utf-8'))
seed = json.loads((root / 'tools/spec_codegen/commit_bootstrap_seed.json').read_text(encoding='utf-8'))

bits = seed['bits']
combined = seed['combined']
rules = seed['endi_rules']

def mask_value(expr: str) -> int:
    parts = [p.strip() for p in expr.split('|')]
    value = 0
    for p in parts:
        if p in combined:
            for sub in combined[p]:
                value |= 1 << bits[sub]
        else:
            value |= 1 << bits[p]
    return value

failures = []

for case in cases:
    mask = mask_value(case['mask_symbol'])
    fault_pending = case['fault_pending_before']
    pc_eip_en = case['pc_eip_en']
    pc_eip_val = int(case['pc_eip_val'], 16)

    has_eip = bool(mask & (1 << bits['CM_EIP']))
    has_clr03 = bool(mask & (1 << bits['CM_CLR03']))
    has_clr47 = bool(mask & (1 << bits['CM_CLR47']))
    has_clrf = bool(mask & (1 << bits['CM_CLRF']))

    commit_eip = has_eip and pc_eip_en and not (fault_pending and rules['apply_eip_only_if_no_fault_pending'])
    eip_after = f"0x{pc_eip_val:08X}" if commit_eip else "UNCHANGED"
    clear_fault = has_clrf and rules['clear_fault_only_if_clrf_set']

    if commit_eip != case['expect_commit_eip']:
        failures.append(f"{case['name']}: commit_eip expected {case['expect_commit_eip']} got {commit_eip}")
    if eip_after != case['expect_eip_after']:
        failures.append(f"{case['name']}: eip_after expected {case['expect_eip_after']} got {eip_after}")
    if has_clr03 != case['expect_clear_t0_t3']:
        failures.append(f"{case['name']}: clear_t0_t3 expected {case['expect_clear_t0_t3']} got {has_clr03}")
    if has_clr47 != case['expect_clear_t4_t7']:
        failures.append(f"{case['name']}: clear_t4_t7 expected {case['expect_clear_t4_t7']} got {has_clr47}")
    if clear_fault != case['expect_clear_fault']:
        failures.append(f"{case['name']}: clear_fault expected {case['expect_clear_fault']} got {clear_fault}")

if failures:
    print('Commit/ENDI smoke failed:')
    for f in failures:
        print(' -', f)
    raise SystemExit(1)

print('Commit/ENDI smoke passed.')
for case in cases:
    print(' -', case['name'])
