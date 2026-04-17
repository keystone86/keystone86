# Keystone86 / Aegis — Rung 2 Implementation Note

## What Changed from Rung 1

Rung 2 implements the minimum front-end/control contracts needed for correct
JMP SHORT bring-up:

1. position-proven byte capture in the decoder
2. real decode/control acceptance boundary between decoder and microsequencer
3. control-transfer serialization in the microsequencer
4. commit-owned redirect visibility in commit_engine

Four modules changed. All other modules are unchanged from Rung 1.

---

## Changes

### rtl/core/decoder.sv

**Change:** Added multi-byte decode state machine for JMP SHORT (opcode `0xEB`).

In Rung 1, the decoder consumed exactly one byte per instruction and always
produced a single-byte result. In Rung 2:

- The decoder detects `0xEB` as the start of a two-byte sequence.
- It enters a second capture state to consume the displacement byte.
- It forms the JMP target EIP as `opcode_eip + 2 + sign_extend(disp8)`.
- Byte capture is position-proven: the decoder only latches a byte when the
  fetch-side payload asserts the byte is valid at the expected byte position
  within the current non-stale stream.
- Decode result is held stable until microsequencer asserts `dec_ack`.

The classify_opcode() function is extended:

    0xEB  -> ENTRY_JMP_SHORT (or equivalent dispatch entry)
    (all prior mappings unchanged)

### rtl/core/microsequencer.sv

**Change:** Added JMP target staging and control-transfer serialization.

- On accepting a JMP decode payload (`dec_ack`), the microsequencer captures
  the JMP target EIP and stages it to `commit_engine` via `pc_target_en` /
  `pc_target_val`.
- After accepting a control-transfer instruction, the microsequencer holds
  upstream (does not re-issue `dec_ack` or allow further decode advancement)
  until ENDI completes and commit_engine has made the redirect visible.
- This is the stale-work suppression boundary: no old-path decode/dispatch
  work survives after the accepted control packet says the stream changed.

### rtl/core/commit_engine.sv

**Change:** Added commit-owned redirect visibility for JMP target EIP.

New inputs `pc_target_en` / `pc_target_val` carry the JMP target from the
microsequencer. These are registered into `pc_target_en_r` / `pc_target_val_r`.

When ENDI fires with `CM_FLUSHQ` (bit 9) set:
- `eip_r` is loaded from `pc_target_val_r` (JMP target becomes architectural EIP)
- `flush_req` is asserted with `flush_addr = pc_target_val_r` (prefetch queue retarget)

This is the single authoritative redirect event. Nothing upstream makes redirect
architecturally visible before this point.

Existing Rung 0/1 ENDI behavior (CM_EIP commit without CM_FLUSHQ) is fully
preserved for NOP and PREFIX_ONLY paths.

### rtl/core/cpu_top.sv

**Change:** Wired `pc_target_en` and `pc_target_val` from microsequencer to
commit_engine. Previously these ports were unused / tied off.

---

## How JMP SHORT Works End-to-End

The path for a single JMP SHORT (`EB 05`) instruction:

1. Decoder latches `0xEB` (opcode byte), recognizes two-byte instruction.
   Enters displacement-capture state. Asserts `dec_busy` to hold microsequencer.

2. Decoder latches `0x05` (displacement byte) at the correct position.
   Forms target EIP: `opcode_eip + 2 + 5 = opcode_eip + 7`.
   Asserts `decode_done`, `entry_id = ENTRY_JMP_SHORT`, `next_eip = target_eip`.

3. Microsequencer accepts decode result on `dec_ack`.
   Asserts `pc_target_en = 1`, `pc_target_val = target_eip` for one cycle.
   Serializes: upstream is held — no further decode advancement while the
   control-transfer is in flight.

4. `commit_engine` registers `pc_target_en_r = 1`, `pc_target_val_r = target_eip`.

5. Microsequencer dispatches `ENTRY_JMP_SHORT` and executes:
   `ENDI CM_EIP | CM_FLUSHQ`.

6. `commit_engine` processes ENDI:
   - `CM_FLUSHQ` set: `eip_r <= pc_target_val_r` (JMP target becomes visible EIP)
   - `flush_req <= 1`, `flush_addr <= pc_target_val_r` (prefetch queue retargets)
   - `endi_done = 1`

7. Microsequencer receives `endi_done`, returns to `FETCH_DECODE`.
   Upstream resumes. Prefetch queue is now fetching from the JMP target.

---

## What Was Intentionally Deferred

- Fetch-local direct stream following: not implemented. The machine serializes
  all control-transfer through commit visibility. Stream-following optimization
  is a valid later addition after the correct baseline is proven.
- Full epoch propagation through RTL: deferred. The serialized model is correct
  and sufficient for Rung 2. Epoch plumbing is a later optimization.
- JMP NEAR (opcode `0xE9`, 16/32-bit displacement): the testbench includes
  near-JMP cases. Coverage may be limited to short-JMP for initial bring-up.
- CALL / RET / JCC: deferred to Rung 3+.
- Prefix accumulation before JMP: deferred to later rungs.

---

## Interfaces Shaped for Growth

The following interfaces are now wired that were tied off in Rung 1:

- `commit_engine.pc_target_en`, `pc_target_val` — used for JMP target commit;
  shaped to also carry CALL/RET/JCC targets in later rungs
- Control-transfer serialization in microsequencer — correct baseline for
  future speculative/overlapping execution to build on

---

## Architectural Constraints Followed

**Decoder remains a classifier.** The decoder forms a decode payload and target
EIP. It does not modify architectural state. It does not own the redirect decision.

**Microsequencer stages, does not commit.** The microsequencer stages the JMP target
to commit_engine. It does not directly modify EIP or issue flush.

**Redirect is commit-owned.** The prefetch queue flush and EIP update both happen
inside commit_engine at ENDI time, and nowhere else.

**No bypass paths.** The Rung 2 front-end path is:
`bus_interface → prefetch_queue → decoder → microsequencer → commit_engine`.
No module makes redirect architecturally visible before commit.
