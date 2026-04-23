from pathlib import Path

checks = {
    'frozen_manifest': Path('docs/spec/frozen/IMPORT_MANIFEST.md').exists(),
    'ucode_main': Path('microcode/src/ucode_main.uasm').exists(),
    'bootstrap_dispatch': Path('build/microcode/dispatch.hex').exists(),
    'cpu_top': Path('rtl/core/cpu_top.sv').exists(),
}

for k, v in checks.items():
    print(f'{k}: {"OK" if v else "MISSING"}')

missing = [k for k, v in checks.items() if not v]
raise SystemExit(1 if missing else 0)
