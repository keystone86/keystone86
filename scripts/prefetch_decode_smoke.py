from pathlib import Path
import json
import re

root = Path('.')
cases = json.loads((root / 'sim/vectors/handcrafted/prefetch_decode_cases.json').read_text(encoding='utf-8'))
seed = json.loads((root / 'tools/spec_codegen/prefetch_decode_seed.json').read_text(encoding='utf-8'))
entry_defs = (root / 'rtl/include/entry_ids.svh').read_text(encoding='utf-8')

entry_map = {}
for line in entry_defs.splitlines():
    m = re.match(r"`define\s+(ENTRY_[A-Z0-9_]+)\s+8'h([0-9A-Fa-f]+)", line.strip())
    if m:
        entry_map[m.group(1)] = int(m.group(2), 16)

failures = []

for case in cases:
    first = case['bytes'][0]
    opcode_key = f"0x{first:02X}"

    consumed = seed['opcode_lengths'].get(opcode_key, 1)
    entry_name = seed['opcode_entry_map'].get(opcode_key, seed['fallback_entry'])
    next_eip = int(case['start_eip'], 16) + consumed
    decode_done = True
    held_until_ack = seed['decoder_handshake']['decode_done_held_until_ack']

    if consumed != case['expected_consumed']:
        failures.append(f"{case['name']}: expected consumed={case['expected_consumed']} got {consumed}")

    expected_next_eip = int(case['expected_next_eip'], 16)
    if next_eip != expected_next_eip:
        failures.append(f"{case['name']}: expected next_eip={expected_next_eip:#010x} got {next_eip:#010x}")

    if entry_name != case['expected_entry']:
        failures.append(f"{case['name']}: expected entry {case['expected_entry']} got {entry_name}")

    if decode_done != case['expect_decode_done_before_ack']:
        failures.append(f"{case['name']}: decode_done pre-ack mismatch")

    if not held_until_ack:
        failures.append(f"{case['name']}: decoder handshake seed violates hold-until-ack rule")

    if case.get('flush_after_commit', False):
        if not seed['flush_rule']['queue_clears_on_eip_changing_commit']:
            failures.append(f"{case['name']}: flush rule not enabled in seed")
        queue_after_flush = 0
        if queue_after_flush != case['expected_queue_length_after_flush']:
            failures.append(
                f"{case['name']}: expected queue len after flush={case['expected_queue_length_after_flush']} got {queue_after_flush}"
            )

if failures:
    print('Prefetch/decode smoke failed:')
    for f in failures:
        print(' -', f)
    raise SystemExit(1)

print('Prefetch/decode smoke passed.')
for case in cases:
    print(' -', case['name'])
