from pathlib import Path

required = [
    'docs/spec/frozen/master_design_statement.md',
    'docs/spec/frozen/appendix_a_field_dictionary.md',
    'docs/spec/frozen/appendix_b_ownership_matrix.md',
    'docs/spec/frozen/appendix_c_assembler_spec.md',
    'docs/spec/frozen/appendix_d_bringup_ladder.md',
    'docs/spec/frozen/verification_plan.md',
]
missing = [p for p in required if not Path(p).exists()]
if missing:
    print('Missing frozen spec files:')
    for p in missing:
        print(' -', p)
    raise SystemExit(1)

bad = []
for p in required:
    txt = Path(p).read_text(encoding='utf-8', errors='ignore')
    if 'Placeholder' in txt[:400]:
        bad.append(p)

if bad:
    print('Frozen spec files still appear to contain placeholders:')
    for p in bad:
        print(' -', p)
    raise SystemExit(1)

print('Frozen spec placement looks complete and non-placeholder.')
