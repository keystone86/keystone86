from pathlib import Path
import json

root = Path('.')
seed = json.loads((root / 'tools/spec_codegen/bootstrap_dashboard_seed.json').read_text(encoding='utf-8'))

command_paths = {
    'make spec-check': ['scripts/spec_check.py'],
    'make frozen-manifest-check': ['scripts/frozen_manifest_check.py'],
    'make namespace-check': ['scripts/namespace_check.py'],
    'make spec-sync-status': ['scripts/spec_sync_status.py'],
    'make ucode': ['scripts/ucode_build.py'],
    'make ucode-bootstrap-check': ['scripts/ucode_bootstrap_check.py'],
    'make decode-dispatch-smoke': ['scripts/decode_dispatch_smoke.py'],
    'make microseq-smoke': ['scripts/microseq_smoke.py'],
    'make commit-smoke': ['scripts/commit_smoke.py'],
    'make service-abi-smoke': ['scripts/service_abi_smoke.py'],
    'make prefetch-decode-smoke': ['scripts/prefetch_decode_smoke.py'],
    'make version-status': ['scripts/version_status.py'],
}

print('Keystone86 Aegis Bootstrap Report')
print('================================')
print()

for check in seed['checks']:
    cmd = check['command']
    paths = command_paths.get(cmd, [])
    status = 'OK' if all((root / p).exists() for p in paths) else 'MISSING'
    supports = ', '.join(check['supports'])
    print(f"[{status}] {check['name']}")
    print(f"      command: {cmd}")
    print(f"      supports: {supports}")
    if paths:
        print(f"      files: {', '.join(paths)}")
    print()

rung_support = {r['name']: [] for r in seed['rungs']}
for check in seed['checks']:
    for s in check['supports']:
        if s in rung_support:
            rung_support[s].append(check['name'])

print('Rung coverage')
print('-------------')
for rung in seed['rungs']:
    names = rung_support.get(rung['name'], [])
    if names:
        print(f"{rung['name']}: {', '.join(names)}")
    else:
        print(f"{rung['name']}: no bootstrap checks yet")
