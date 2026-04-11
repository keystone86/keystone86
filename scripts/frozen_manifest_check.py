from pathlib import Path

manifest = Path('docs/spec/frozen/IMPORT_MANIFEST.md')
status = Path('docs/spec/frozen/STATUS.md')

if not manifest.exists():
    print('Missing import manifest.')
    raise SystemExit(1)
if not status.exists():
    print('Missing frozen status file.')
    raise SystemExit(1)

txt = manifest.read_text(encoding='utf-8')
required_names = [
    'master_design_statement.md',
    'appendix_a_field_dictionary.md',
    'appendix_b_ownership_matrix.md',
    'appendix_c_assembler_spec.md',
    'appendix_d_bringup_ladder.md',
    'verification_plan.md',
]
missing = [n for n in required_names if n not in txt]
if missing:
    print('Manifest missing imported entries for:')
    for n in missing:
        print(' -', n)
    raise SystemExit(1)

print('Frozen manifest looks complete.')
