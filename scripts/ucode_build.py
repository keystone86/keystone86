from pathlib import Path

build = Path("build/microcode")
build.mkdir(parents=True, exist_ok=True)

# --------------------------------------------------------------------
# Dispatch table
# --------------------------------------------------------------------
dispatch_vals = []
dispatch_listing = [
    "; Keystone86 / Aegis bootstrap dispatch listing",
    "; index  upc   meaning",
]

for i in range(256):
    if i == 0x00:
        val = 0x010
        meaning = "ENTRY_NULL"
    elif i == 0x07:
        val = 0x050       # Rung 2: ENTRY_JMP_NEAR
        meaning = "ENTRY_JMP_NEAR"
    elif i == 0x09:
        val = 0x060       # Rung 3 placeholder
        meaning = "ENTRY_CALL_NEAR"
    elif i == 0x0B:
        val = 0x070       # Rung 3 placeholder
        meaning = "ENTRY_RET_NEAR"
    elif i == 0x0D:
        val = 0x080       # Rung 4: ENTRY_JCC
        meaning = "ENTRY_JCC"
    elif i == 0x0E:
        val = 0x090       # Rung 5 Pass 1: ENTRY_INT skeleton
        meaning = "ENTRY_INT"
    elif i == 0x0F:
        val = 0x0A0       # Rung 5 Pass 1: ENTRY_IRET skeleton
        meaning = "ENTRY_IRET"
    elif i == 0x12:
        val = 0x030
        meaning = "ENTRY_PREFIX_ONLY"
    elif i == 0x13:
        val = 0x020
        meaning = "ENTRY_NOP_XCHG_AX"
    elif i == 0xFF:
        val = 0x040
        meaning = "ENTRY_RESET"
    else:
        val = 0x010
        meaning = "fallback -> ENTRY_NULL"

    dispatch_vals.append(f"{val:03X}")
    dispatch_listing.append(f"0x{i:02X}   0x{val:03X}  {meaning}")

(build / "dispatch.hex").write_text("\n".join(dispatch_vals) + "\n", encoding="utf-8")
(build / "dispatch.lst").write_text("\n".join(dispatch_listing) + "\n", encoding="utf-8")

# --------------------------------------------------------------------
# Encoding helpers
# --------------------------------------------------------------------
CM_EIP       = 0x002
CM_CLR03     = 0x040
CM_CLR47     = 0x080
CM_CLRF      = 0x100
CM_FLUSHQ    = 0x200
CM_FAULT_END = CM_CLR03
CM_NOP       = CM_CLR03 | CM_CLR47 | CM_CLRF
CM_NOP_EIP   = CM_NOP | CM_EIP
CM_JMP       = CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ
CM_STACK     = 0x010
CM_SEG       = 0x008
CM_EFLAGS    = 0x004
CM_CALL      = CM_STACK | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ
CM_RET       = CM_STACK | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ
CM_INT       = CM_SEG | CM_STACK | CM_EFLAGS | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ
CM_IRET      = CM_SEG | CM_STACK | CM_EFLAGS | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ

FETCH_IMM8             = 0x01
FETCH_DISP8            = 0x04
FETCH_DISP16           = 0x05
LOAD_RM32              = 0x22
PUSH32                 = 0x41
POP32                  = 0x43
COMPUTE_REL_TARGET     = 0x46
VALIDATE_NEAR_TRANSFER = 0x44
CONDITION_EVAL         = 0x47
INT_ENTER              = 0x62
IRET_FLOW              = 0x63
STAGE_STACK_ADJ        = 0x06
REG_T4                 = 0x4
REG_SPECIAL            = 0xF
FC_INT                 = 0xA

C_ALWAYS = 0x0
C_OK     = 0x1
C_WAIT   = 0x2
C_FAULT  = 0x3
C_T3Z    = 0xC

def endi(mask: int) -> str:
    return f"{0xE0000000 | (mask & 0x3FF):08X}"

def raise_fc(fc: int) -> str:
    return f"{0xC0000000 | ((fc & 0x3F) << 22):08X}"

def svcw_small(service_id: int) -> str:
    return f"{0x90000000 | ((service_id & 0x3F) << 22):08X}"

def ext_word() -> str:
    return f"{0xF0000000:08X}"

def svcw_ext(service_id: int) -> str:
    return f"{0x90000000 | (service_id & 0xFF):08X}"

def br(cond: int, rel10: int) -> str:
    return f"{0x40000000 | ((cond & 0xF) << 18) | (rel10 & 0x3FF):08X}"

def stage(field: int, src: int, dst: int = REG_SPECIAL) -> str:
    return f"{0xA0000000 | ((dst & 0xF) << 14) | ((src & 0xF) << 10) | (field & 0x3FF):08X}"

def rel10(from_addr: int, to_addr: int) -> int:
    delta = to_addr - (from_addr + 1)
    if delta < -512 or delta > 511:
        raise ValueError(f"BR target out of range: from 0x{from_addr:03X} to 0x{to_addr:03X}")
    return delta

rom = ["00000000"] * 4096

# --------------------------------------------------------------------
# Baseline entries
# --------------------------------------------------------------------
rom[0x000] = endi(CM_FAULT_END)  # SUB_FAULT_HANDLER
rom[0x010] = raise_fc(0x6)       # ENTRY_NULL
rom[0x011] = endi(CM_FAULT_END)

rom[0x020] = endi(CM_NOP_EIP)    # ENTRY_NOP_XCHG_AX
rom[0x030] = endi(CM_NOP_EIP)    # ENTRY_PREFIX_ONLY
rom[0x040] = endi(CM_NOP)        # ENTRY_RESET

# --------------------------------------------------------------------
# Rung 2: ENTRY_JMP_NEAR at 0x050
#
# 0x050  SVCW FETCH_DISP8
# 0x051  BR   C_FAULT, SUB_FAULT_HANDLER
# 0x052  EXT
# 0x053  SVCW COMPUTE_REL_TARGET
# 0x054  BR   C_FAULT, SUB_FAULT_HANDLER
# 0x055  EXT
# 0x056  SVCW VALIDATE_NEAR_TRANSFER
# 0x057  BR   C_FAULT, SUB_FAULT_HANDLER
# 0x058  ENDI CM_JMP
# --------------------------------------------------------------------
rom[0x050] = svcw_small(FETCH_DISP8)
rom[0x051] = br(C_FAULT, rel10(0x051, 0x000))
rom[0x052] = ext_word()
rom[0x053] = svcw_ext(COMPUTE_REL_TARGET)
rom[0x054] = br(C_FAULT, rel10(0x054, 0x000))
rom[0x055] = ext_word()
rom[0x056] = svcw_ext(VALIDATE_NEAR_TRANSFER)
rom[0x057] = br(C_FAULT, rel10(0x057, 0x000))
rom[0x058] = endi(CM_JMP)

# --------------------------------------------------------------------
# Rung 3: ENTRY_CALL_NEAR at 0x060
#
# Direct CALL uses the decoder-staged disp16 payload with COMPUTE_REL_TARGET.
# Indirect CALL uses LOAD_RM32 to overwrite T2 with the r/m target. Direct CALL
# has no ModRM metadata, so LOAD_RM32 is a leaf no-op and preserves T2.
# Both forms then PUSH32, VALIDATE_NEAR_TRANSFER, and ENDI.
# --------------------------------------------------------------------
rom[0x060] = ext_word()
rom[0x061] = svcw_ext(COMPUTE_REL_TARGET)
rom[0x062] = br(C_FAULT, rel10(0x062, 0x000))
rom[0x063] = svcw_small(LOAD_RM32)
rom[0x064] = br(C_FAULT, rel10(0x064, 0x000))
rom[0x065] = ext_word()
rom[0x066] = svcw_ext(PUSH32)
rom[0x067] = br(C_FAULT, rel10(0x067, 0x000))
rom[0x068] = ext_word()
rom[0x069] = svcw_ext(VALIDATE_NEAR_TRANSFER)
rom[0x06A] = br(C_FAULT, rel10(0x06A, 0x000))
rom[0x06B] = endi(CM_CALL)

# --------------------------------------------------------------------
# Rung 3: ENTRY_RET_NEAR at 0x070
#
# RET uses POP32, validates the popped target, stages the C2 stack adjustment
# from T4 (zero for C3), and ENDI commits the staged stack/EIP state.
# --------------------------------------------------------------------
rom[0x070] = ext_word()
rom[0x071] = svcw_ext(POP32)
rom[0x072] = br(C_FAULT, rel10(0x072, 0x000))
rom[0x073] = ext_word()
rom[0x074] = svcw_ext(VALIDATE_NEAR_TRANSFER)
rom[0x075] = br(C_FAULT, rel10(0x075, 0x000))
rom[0x076] = stage(STAGE_STACK_ADJ, REG_T4)
rom[0x077] = endi(CM_RET)

# --------------------------------------------------------------------
# Rung 4: ENTRY_JCC at 0x080
#
# Short Jcc keeps condition evaluation in flow_control and the taken/not-taken
# decision in microcode. The not-taken path commits only the decoder-staged
# fall-through EIP; the taken path computes and validates the target before
# ENDI commits the redirect and flush.
# --------------------------------------------------------------------
rom[0x080] = svcw_small(FETCH_DISP8)
rom[0x081] = br(C_FAULT, rel10(0x081, 0x000))
rom[0x082] = ext_word()
rom[0x083] = svcw_ext(CONDITION_EVAL)
rom[0x084] = br(C_FAULT, rel10(0x084, 0x000))
rom[0x085] = br(C_T3Z, rel10(0x085, 0x08D))
rom[0x086] = ext_word()
rom[0x087] = svcw_ext(COMPUTE_REL_TARGET)
rom[0x088] = br(C_FAULT, rel10(0x088, 0x000))
rom[0x089] = ext_word()
rom[0x08A] = svcw_ext(VALIDATE_NEAR_TRANSFER)
rom[0x08B] = br(C_FAULT, rel10(0x08B, 0x000))
rom[0x08C] = endi(CM_JMP)
rom[0x08D] = endi(CM_NOP_EIP)

# --------------------------------------------------------------------
# Rung 5 Pass 2/3: bounded real-mode INT_ENTER and IRET_FLOW paths.
#
# ENTRY_INT proves the CD imm8 path can dispatch and invoke FETCH_IMM8 to place
# the zero-extended vector in T4, then calls INT_ENTER. INT_ENTER remains a
# bounded service; ENDI CM_INT is the only architectural visibility point.
#
# ENTRY_IRET calls IRET_FLOW for the Pass 3 bounded real-mode frame pop. The
# service stages popped EIP/CS/FLAGS/ESP only; ENDI CM_IRET is the architectural
# visibility point.
# --------------------------------------------------------------------
rom[0x090] = svcw_small(FETCH_IMM8)
rom[0x091] = br(C_FAULT, rel10(0x091, 0x000))
rom[0x092] = ext_word()
rom[0x093] = svcw_ext(INT_ENTER)
rom[0x094] = br(C_FAULT, rel10(0x094, 0x000))
rom[0x095] = endi(CM_INT)

rom[0x0A0] = ext_word()
rom[0x0A1] = svcw_ext(IRET_FLOW)
rom[0x0A2] = br(C_FAULT, rel10(0x0A2, 0x000))
rom[0x0A3] = endi(CM_IRET)

(build / "ucode.hex").write_text("\n".join(rom) + "\n", encoding="utf-8")

listing = f"""; Keystone86 / Aegis bootstrap microcode listing
; Rung 2 service-based JMP, Rung 3 service-based CALL/RET, Rung 4 Jcc,
; and Rung 5 Pass 2 INT_ENTER path plus Pass 3 bounded IRET_FLOW path
address  encoding     source
0x000    {endi(CM_FAULT_END)}   SUB_FAULT_HANDLER: ENDI CM_FAULT_END
0x010    {raise_fc(0x6)}   ENTRY_NULL: RAISE FC_UD
0x011    {endi(CM_FAULT_END)}   ENDI CM_FAULT_END
0x020    {endi(CM_NOP_EIP)}   ENTRY_NOP_XCHG_AX: ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x030    {endi(CM_NOP_EIP)}   ENTRY_PREFIX_ONLY: ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x040    {endi(CM_NOP)}   ENTRY_RESET: ENDI CM_NOP
0x050    {svcw_small(FETCH_DISP8)}   ENTRY_JMP_NEAR: SVCW FETCH_DISP8
0x051    {br(C_FAULT, rel10(0x051, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x052    {ext_word()}   EXT
0x053    {svcw_ext(COMPUTE_REL_TARGET)}   SVCW COMPUTE_REL_TARGET
0x054    {br(C_FAULT, rel10(0x054, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x055    {ext_word()}   EXT
0x056    {svcw_ext(VALIDATE_NEAR_TRANSFER)}   SVCW VALIDATE_NEAR_TRANSFER
0x057    {br(C_FAULT, rel10(0x057, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x058    {endi(CM_JMP)}   ENDI CM_JMP (0x{CM_JMP:03X})
0x060    {ext_word()}   ENTRY_CALL_NEAR: EXT
0x061    {svcw_ext(COMPUTE_REL_TARGET)}   SVCW COMPUTE_REL_TARGET
0x062    {br(C_FAULT, rel10(0x062, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x063    {svcw_small(LOAD_RM32)}   SVCW LOAD_RM32
0x064    {br(C_FAULT, rel10(0x064, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x065    {ext_word()}   EXT
0x066    {svcw_ext(PUSH32)}   SVCW PUSH32
0x067    {br(C_FAULT, rel10(0x067, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x068    {ext_word()}   EXT
0x069    {svcw_ext(VALIDATE_NEAR_TRANSFER)}   SVCW VALIDATE_NEAR_TRANSFER
0x06A    {br(C_FAULT, rel10(0x06A, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x06B    {endi(CM_CALL)}   ENDI CM_CALL (0x{CM_CALL:03X})
0x070    {ext_word()}   ENTRY_RET_NEAR: EXT
0x071    {svcw_ext(POP32)}   SVCW POP32
0x072    {br(C_FAULT, rel10(0x072, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x073    {ext_word()}   EXT
0x074    {svcw_ext(VALIDATE_NEAR_TRANSFER)}   SVCW VALIDATE_NEAR_TRANSFER
0x075    {br(C_FAULT, rel10(0x075, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x076    {stage(STAGE_STACK_ADJ, REG_T4)}   STAGE STACK_ADJ, T4
0x077    {endi(CM_RET)}   ENDI CM_RET (0x{CM_RET:03X})
0x080    {svcw_small(FETCH_DISP8)}   ENTRY_JCC: SVCW FETCH_DISP8
0x081    {br(C_FAULT, rel10(0x081, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x082    {ext_word()}   EXT
0x083    {svcw_ext(CONDITION_EVAL)}   SVCW CONDITION_EVAL
0x084    {br(C_FAULT, rel10(0x084, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x085    {br(C_T3Z, rel10(0x085, 0x08D))}   BR C_T3Z, jcc_not_taken
0x086    {ext_word()}   EXT
0x087    {svcw_ext(COMPUTE_REL_TARGET)}   SVCW COMPUTE_REL_TARGET
0x088    {br(C_FAULT, rel10(0x088, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x089    {ext_word()}   EXT
0x08A    {svcw_ext(VALIDATE_NEAR_TRANSFER)}   SVCW VALIDATE_NEAR_TRANSFER
0x08B    {br(C_FAULT, rel10(0x08B, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x08C    {endi(CM_JMP)}   ENDI CM_JMP (taken, 0x{CM_JMP:03X})
0x08D    {endi(CM_NOP_EIP)}   jcc_not_taken: ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x090    {svcw_small(FETCH_IMM8)}   ENTRY_INT: SVCW FETCH_IMM8
0x091    {br(C_FAULT, rel10(0x091, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x092    {ext_word()}   EXT
0x093    {svcw_ext(INT_ENTER)}   SVCW INT_ENTER
0x094    {br(C_FAULT, rel10(0x094, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x095    {endi(CM_INT)}   ENDI CM_INT (0x{CM_INT:03X})
0x0A0    {ext_word()}   ENTRY_IRET: EXT
0x0A1    {svcw_ext(IRET_FLOW)}   SVCW IRET_FLOW
0x0A2    {br(C_FAULT, rel10(0x0A2, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x0A3    {endi(CM_IRET)}   ENDI CM_IRET (0x{CM_IRET:03X})
"""
(build / "ucode.lst").write_text(listing, encoding="utf-8")

print("Wrote bootstrap ucode.hex, dispatch.hex, ucode.lst, dispatch.lst")
print(f"  CM_JMP  = 0x{CM_JMP:03X}")
print(f"  CM_CALL = 0x{CM_CALL:03X}")
print(f"  CM_RET  = 0x{CM_RET:03X}")
print(f"  ENTRY_CALL_NEAR at dispatch[0x09] -> uPC 0x060")
print(f"  ENTRY_RET_NEAR  at dispatch[0x0B] -> uPC 0x070")
print(f"  ENTRY_JCC       at dispatch[0x0D] -> uPC 0x080")
print(f"  CM_INT  = 0x{CM_INT:03X}")
print(f"  CM_IRET = 0x{CM_IRET:03X}")
print(f"  ENTRY_INT       at dispatch[0x0E] -> uPC 0x090 (Pass 2 INT_ENTER)")
print(f"  ENTRY_IRET      at dispatch[0x0F] -> uPC 0x0A0 (Pass 3 IRET_FLOW)")
