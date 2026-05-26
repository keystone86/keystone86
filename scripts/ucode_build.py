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
    elif i == 0x01:
        # Rung 6 Pass 6F-2 bounded MOV: existing immediate/register,
        # direct-disp32, non-SIB, and base-only-SIB coverage plus the
        # default-32 ModRM.mod=00 ModRM.r/m=100 SIB.index=100 SIB.base=101
        # no-base-SIB disp32 special case with EA=disp32. No index read path,
        # scale arithmetic, 0x67, EA_CALC_16, or Rung 7 behavior.
        val = 0x100
        meaning = "ENTRY_MOV"
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
CM_GPR       = 0x001
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
CM_MOV_REG   = CM_GPR | CM_CLR03 | CM_CLR47 | CM_CLRF

FETCH_IMM8             = 0x01
FETCH_IMM16            = 0x02
FETCH_IMM32            = 0x03
FETCH_DISP8            = 0x04
FETCH_DISP16           = 0x05
FETCH_DISP32           = 0x06
EA_CALC_32             = 0x11
LOAD_RM8               = 0x20
LOAD_RM16              = 0x21
LOAD_RM32              = 0x22
STORE_RM8              = 0x23
STORE_RM16             = 0x24
STORE_RM32             = 0x25
LOAD_REG_META          = 0x26
STORE_REG_META         = 0x27
PUSH32                 = 0x41
POP32                  = 0x43
COMPUTE_REL_TARGET     = 0x46
VALIDATE_NEAR_TRANSFER = 0x44
CONDITION_EVAL         = 0x47
INT_ENTER              = 0x62
IRET_FLOW              = 0x63
STAGE_STACK_ADJ        = 0x06
STAGE_GPR              = 0x00
REG_T2                 = 0x2
REG_T3                 = 0x3
REG_T4                 = 0x4
REG_SPECIAL            = 0xF
FC_INT                 = 0xA
MF_OPCODE_CLASS        = 0x06
MF_MODRM_CLASS         = 0x03
MF_IMM_CLASS           = 0x04
MF_REG_DST             = 0x09
MF_REG_RM              = 0x0B
MF_FC_TO_VECTOR        = 0x13

C_ALWAYS = 0x0
C_OK     = 0x1
C_WAIT   = 0x2
C_FAULT  = 0x3
C_W16    = 0x6
C_W8     = 0xB
C_T3Z    = 0xC
C_T3NZ   = 0xD

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

def extract(dst: int, field: int) -> str:
    return f"{0x70000000 | ((dst & 0xF) << 14) | (field & 0x3FF):08X}"

def rel10(from_addr: int, to_addr: int) -> int:
    delta = to_addr - (from_addr + 1)
    if delta < -512 or delta > 511:
        raise ValueError(f"BR target out of range: from 0x{from_addr:03X} to 0x{to_addr:03X}")
    return delta

rom = ["00000000"] * 4096

# --------------------------------------------------------------------
# Baseline entries
# --------------------------------------------------------------------
rom[0x000] = extract(REG_T4, MF_FC_TO_VECTOR)  # SUB_FAULT_HANDLER
rom[0x001] = ext_word()
rom[0x002] = svcw_ext(INT_ENTER)
rom[0x003] = endi(CM_FAULT_END)
rom[0x010] = raise_fc(0x6)       # ENTRY_NULL
rom[0x011] = br(C_ALWAYS, rel10(0x011, 0x000))

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

# --------------------------------------------------------------------
# Rung 6 Pass 6F-2: ENTRY_MOV immediate, register-register, bounded
# memory-source direct-disp32/base-only/base+disp8/base+disp32, bounded
# register-source memory-destination direct-disp32/base-only/base+disp8/
# base+disp32, and bounded immediate-to-memory direct-disp32/base-only/
# base+disp8/base+disp32/base-only-SIB/no-base-SIB-disp32 slices at 0x100.
#
# B0-B7, B8-BF, and 66+B8-BF keep the proven immediate path with width
# dispatch. 88/89/8A/8B and 66+89/8B use LOAD_REG_META/STORE_REG_META only
# after decoder has accepted ModRM.mod=11. 8A/8B and 66+8B memory-source forms
# use EA_CALC_32 and LOAD_RM8/16/32, then publish through the same CM_MOV_REG
# commit boundary. 88/89 and 66+89 memory-destination forms use EA_CALC_32,
# LOAD_REG_META, and STORE_RM8/16/32 before ENDI CM_NOP|CM_EIP. C6/C7 /0 and
# 66+C7 /0 memory forms use FETCH_IMM8/16/32, EA_CALC_32, and STORE_RM8/16/32
# before ENDI CM_NOP|CM_EIP. The accepted memory subset is direct absolute
# disp32, Pass 6E-1 default-32 base-only no-displacement r/m!=100/101,
# Pass 6E-2 default-32 mod=01 non-SIB signed disp8, and Pass 6E-3 default-32
# mod=10 non-SIB signed disp32, plus Pass 6F-1 base-only SIB forms with
# SIB.index=100 and Pass 6F-2 mod=00 SIB.index=100 SIB.base=101 no-base
# disp32.
# C6/C7 /0 and 66+C7 /0 ModRM.mod=11 forms use FETCH_IMM8/16/32, STAGE_GPR,
# and ENDI CM_MOV_REG without memory services.
# Other memory forms remain on ENTRY_NULL and are not routed here.
# --------------------------------------------------------------------
rom[0x100] = extract(REG_T3, MF_OPCODE_CLASS)
rom[0x101] = br(C_T3Z, rel10(0x101, 0x120))
rom[0x102] = extract(REG_T3, MF_IMM_CLASS)
rom[0x103] = br(C_T3Z, rel10(0x103, 0x150))
rom[0x104] = extract(REG_T3, MF_MODRM_CLASS)
rom[0x105] = br(C_T3Z, rel10(0x105, 0x108))
rom[0x106] = br(C_ALWAYS, rel10(0x106, 0x180))
rom[0x108] = br(C_W8, rel10(0x108, 0x10E))
rom[0x109] = br(C_W16, rel10(0x109, 0x112))
rom[0x10A] = svcw_small(FETCH_IMM32)
rom[0x10B] = br(C_FAULT, rel10(0x10B, 0x000))
rom[0x10C] = stage(STAGE_GPR, REG_T4)
rom[0x10D] = endi(CM_MOV_REG)
rom[0x10E] = svcw_small(FETCH_IMM8)
rom[0x10F] = br(C_FAULT, rel10(0x10F, 0x000))
rom[0x110] = stage(STAGE_GPR, REG_T4)
rom[0x111] = endi(CM_MOV_REG)
rom[0x112] = svcw_small(FETCH_IMM16)
rom[0x113] = br(C_FAULT, rel10(0x113, 0x000))
rom[0x114] = stage(STAGE_GPR, REG_T4)
rom[0x115] = endi(CM_MOV_REG)

rom[0x120] = extract(REG_T3, MF_MODRM_CLASS)
rom[0x121] = br(C_T3Z, rel10(0x121, 0x136))
rom[0x122] = svcw_small(EA_CALC_32)
rom[0x123] = br(C_FAULT, rel10(0x123, 0x000))
rom[0x124] = svcw_small(LOAD_REG_META)
rom[0x125] = br(C_FAULT, rel10(0x125, 0x000))
rom[0x126] = br(C_W8, rel10(0x126, 0x130))
rom[0x127] = br(C_W16, rel10(0x127, 0x133))
rom[0x128] = svcw_small(STORE_RM32)
rom[0x129] = br(C_FAULT, rel10(0x129, 0x000))
rom[0x12A] = endi(CM_NOP_EIP)
rom[0x130] = svcw_small(STORE_RM8)
rom[0x131] = br(C_FAULT, rel10(0x131, 0x000))
rom[0x132] = endi(CM_NOP_EIP)
rom[0x133] = svcw_small(STORE_RM16)
rom[0x134] = br(C_FAULT, rel10(0x134, 0x000))
rom[0x135] = endi(CM_NOP_EIP)
rom[0x136] = svcw_small(LOAD_REG_META)
rom[0x137] = br(C_FAULT, rel10(0x137, 0x000))
rom[0x138] = svcw_small(STORE_REG_META)
rom[0x139] = br(C_FAULT, rel10(0x139, 0x000))
rom[0x13A] = endi(CM_MOV_REG)

rom[0x150] = extract(REG_T3, MF_MODRM_CLASS)
rom[0x151] = br(C_T3Z, rel10(0x151, 0x160))
rom[0x152] = svcw_small(EA_CALC_32)
rom[0x153] = br(C_FAULT, rel10(0x153, 0x000))
rom[0x154] = br(C_W8, rel10(0x154, 0x165))
rom[0x155] = br(C_W16, rel10(0x155, 0x16A))
rom[0x156] = svcw_small(LOAD_RM32)
rom[0x157] = br(C_FAULT, rel10(0x157, 0x000))
rom[0x158] = stage(STAGE_GPR, REG_T4)
rom[0x159] = endi(CM_MOV_REG)
rom[0x160] = svcw_small(LOAD_REG_META)
rom[0x161] = br(C_FAULT, rel10(0x161, 0x000))
rom[0x162] = svcw_small(STORE_REG_META)
rom[0x163] = br(C_FAULT, rel10(0x163, 0x000))
rom[0x164] = endi(CM_MOV_REG)
rom[0x165] = svcw_small(LOAD_RM8)
rom[0x166] = br(C_FAULT, rel10(0x166, 0x000))
rom[0x167] = stage(STAGE_GPR, REG_T4)
rom[0x168] = endi(CM_MOV_REG)
rom[0x16A] = svcw_small(LOAD_RM16)
rom[0x16B] = br(C_FAULT, rel10(0x16B, 0x000))
rom[0x16C] = stage(STAGE_GPR, REG_T4)
rom[0x16D] = endi(CM_MOV_REG)

rom[0x180] = br(C_W8, rel10(0x180, 0x18A))
rom[0x181] = br(C_W16, rel10(0x181, 0x194))
rom[0x182] = svcw_small(FETCH_IMM32)
rom[0x183] = br(C_FAULT, rel10(0x183, 0x000))
rom[0x184] = svcw_small(EA_CALC_32)
rom[0x185] = br(C_FAULT, rel10(0x185, 0x000))
rom[0x186] = svcw_small(STORE_RM32)
rom[0x187] = br(C_FAULT, rel10(0x187, 0x000))
rom[0x188] = endi(CM_NOP_EIP)
rom[0x18A] = svcw_small(FETCH_IMM8)
rom[0x18B] = br(C_FAULT, rel10(0x18B, 0x000))
rom[0x18C] = svcw_small(EA_CALC_32)
rom[0x18D] = br(C_FAULT, rel10(0x18D, 0x000))
rom[0x18E] = svcw_small(STORE_RM8)
rom[0x18F] = br(C_FAULT, rel10(0x18F, 0x000))
rom[0x190] = endi(CM_NOP_EIP)
rom[0x194] = svcw_small(FETCH_IMM16)
rom[0x195] = br(C_FAULT, rel10(0x195, 0x000))
rom[0x196] = svcw_small(EA_CALC_32)
rom[0x197] = br(C_FAULT, rel10(0x197, 0x000))
rom[0x198] = svcw_small(STORE_RM16)
rom[0x199] = br(C_FAULT, rel10(0x199, 0x000))
rom[0x19A] = endi(CM_NOP_EIP)

(build / "ucode.hex").write_text("\n".join(rom) + "\n", encoding="utf-8")

listing = f"""; Keystone86 / Aegis bootstrap microcode listing
; Rung 2 service-based JMP, Rung 3 service-based CALL/RET, Rung 4 Jcc,
; Rung 5 Pass 2 INT_ENTER path, Pass 3 bounded IRET_FLOW path,
; Pass 4 bounded #UD fault delivery through SUB_FAULT_HANDLER,
; and Rung 6 Pass 6F-2 bounded MOV immediate/register/direct-disp32,
; non-SIB, and base-only-SIB coverage plus the default-32
; ModRM.mod=00 ModRM.r/m=100 SIB.index=100 SIB.base=101
; no-base-SIB disp32 special case with EA=disp32
; no index read path, scale arithmetic, 0x67, EA_CALC_16, or Rung 7
address  encoding     source
0x000    {extract(REG_T4, MF_FC_TO_VECTOR)}   SUB_FAULT_HANDLER: EXTRACT T4, MF_FC_TO_VECTOR
0x001    {ext_word()}   EXT
0x002    {svcw_ext(INT_ENTER)}   SVCW INT_ENTER
0x003    {endi(CM_FAULT_END)}   ENDI CM_FAULT_END
0x010    {raise_fc(0x6)}   ENTRY_NULL: RAISE FC_UD
0x011    {br(C_ALWAYS, rel10(0x011, 0x000))}   BR C_ALWAYS, SUB_FAULT_HANDLER
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
0x100    {extract(REG_T3, MF_OPCODE_CLASS)}   ENTRY_MOV: EXTRACT T3, M_OPCODE_CLASS
0x101    {br(C_T3Z, rel10(0x101, 0x120))}   BR C_T3Z, mov_rm_r
0x102    {extract(REG_T3, MF_IMM_CLASS)}   EXTRACT T3, M_IMM_CLASS
0x103    {br(C_T3Z, rel10(0x103, 0x150))}   BR C_T3Z, mov_r_rm
0x104    {extract(REG_T3, MF_MODRM_CLASS)}   EXTRACT T3, M_MODRM_CLASS
0x105    {br(C_T3Z, rel10(0x105, 0x108))}   BR C_T3Z, mov_imm_reg_dispatch
0x106    {br(C_ALWAYS, rel10(0x106, 0x180))}   BR C_ALWAYS, mov_rm_imm
0x108    {br(C_W8, rel10(0x108, 0x10E))}   mov_imm_reg_dispatch: BR C_W8, mov_imm8
0x109    {br(C_W16, rel10(0x109, 0x112))}   BR C_W16, mov_imm16
0x10A    {svcw_small(FETCH_IMM32)}   SVCW FETCH_IMM32
0x10B    {br(C_FAULT, rel10(0x10B, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x10C    {stage(STAGE_GPR, REG_T4)}   STAGE STAGE_GPR, T4
0x10D    {endi(CM_MOV_REG)}   ENDI CM_MOV_REG (0x{CM_MOV_REG:03X})
0x10E    {svcw_small(FETCH_IMM8)}   mov_imm8: SVCW FETCH_IMM8
0x10F    {br(C_FAULT, rel10(0x10F, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x110    {stage(STAGE_GPR, REG_T4)}   STAGE STAGE_GPR, T4
0x111    {endi(CM_MOV_REG)}   ENDI CM_MOV_REG (0x{CM_MOV_REG:03X})
0x112    {svcw_small(FETCH_IMM16)}   mov_imm16: SVCW FETCH_IMM16
0x113    {br(C_FAULT, rel10(0x113, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x114    {stage(STAGE_GPR, REG_T4)}   STAGE STAGE_GPR, T4
0x115    {endi(CM_MOV_REG)}   ENDI CM_MOV_REG (0x{CM_MOV_REG:03X})
0x120    {extract(REG_T3, MF_MODRM_CLASS)}   mov_rm_r: EXTRACT T3, M_MODRM_CLASS
0x121    {br(C_T3Z, rel10(0x121, 0x136))}   BR C_T3Z, mov_rm_r_reg
0x122    {svcw_small(EA_CALC_32)}   SVCW EA_CALC_32
0x123    {br(C_FAULT, rel10(0x123, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x124    {svcw_small(LOAD_REG_META)}   SVCW LOAD_REG_META
0x125    {br(C_FAULT, rel10(0x125, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x126    {br(C_W8, rel10(0x126, 0x130))}   BR C_W8, mov_mem_store8
0x127    {br(C_W16, rel10(0x127, 0x133))}   BR C_W16, mov_mem_store16
0x128    {svcw_small(STORE_RM32)}   SVCW STORE_RM32
0x129    {br(C_FAULT, rel10(0x129, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x12A    {endi(CM_NOP_EIP)}   ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x130    {svcw_small(STORE_RM8)}   mov_mem_store8: SVCW STORE_RM8
0x131    {br(C_FAULT, rel10(0x131, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x132    {endi(CM_NOP_EIP)}   ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x133    {svcw_small(STORE_RM16)}   mov_mem_store16: SVCW STORE_RM16
0x134    {br(C_FAULT, rel10(0x134, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x135    {endi(CM_NOP_EIP)}   ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x136    {svcw_small(LOAD_REG_META)}   mov_rm_r_reg: SVCW LOAD_REG_META
0x137    {br(C_FAULT, rel10(0x137, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x138    {svcw_small(STORE_REG_META)}   SVCW STORE_REG_META
0x139    {br(C_FAULT, rel10(0x139, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x13A    {endi(CM_MOV_REG)}   ENDI CM_MOV_REG (0x{CM_MOV_REG:03X})
0x150    {extract(REG_T3, MF_MODRM_CLASS)}   mov_r_rm: EXTRACT T3, M_MODRM_CLASS
0x151    {br(C_T3Z, rel10(0x151, 0x160))}   BR C_T3Z, mov_r_rm_reg
0x152    {svcw_small(EA_CALC_32)}   SVCW EA_CALC_32
0x153    {br(C_FAULT, rel10(0x153, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x154    {br(C_W8, rel10(0x154, 0x165))}   BR C_W8, mov_mem_load8
0x155    {br(C_W16, rel10(0x155, 0x16A))}   BR C_W16, mov_mem_load16
0x156    {svcw_small(LOAD_RM32)}   SVCW LOAD_RM32
0x157    {br(C_FAULT, rel10(0x157, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x158    {stage(STAGE_GPR, REG_T4)}   STAGE STAGE_GPR, T4
0x159    {endi(CM_MOV_REG)}   ENDI CM_MOV_REG (0x{CM_MOV_REG:03X})
0x160    {svcw_small(LOAD_REG_META)}   mov_r_rm_reg: SVCW LOAD_REG_META
0x161    {br(C_FAULT, rel10(0x161, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x162    {svcw_small(STORE_REG_META)}   SVCW STORE_REG_META
0x163    {br(C_FAULT, rel10(0x163, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x164    {endi(CM_MOV_REG)}   ENDI CM_MOV_REG (0x{CM_MOV_REG:03X})
0x165    {svcw_small(LOAD_RM8)}   mov_mem_load8: SVCW LOAD_RM8
0x166    {br(C_FAULT, rel10(0x166, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x167    {stage(STAGE_GPR, REG_T4)}   STAGE STAGE_GPR, T4
0x168    {endi(CM_MOV_REG)}   ENDI CM_MOV_REG (0x{CM_MOV_REG:03X})
0x16A    {svcw_small(LOAD_RM16)}   mov_mem_load16: SVCW LOAD_RM16
0x16B    {br(C_FAULT, rel10(0x16B, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x16C    {stage(STAGE_GPR, REG_T4)}   STAGE STAGE_GPR, T4
0x16D    {endi(CM_MOV_REG)}   ENDI CM_MOV_REG (0x{CM_MOV_REG:03X})
0x180    {br(C_W8, rel10(0x180, 0x18A))}   mov_rm_imm: BR C_W8, mov_rm_imm8
0x181    {br(C_W16, rel10(0x181, 0x194))}   BR C_W16, mov_rm_imm16
0x182    {svcw_small(FETCH_IMM32)}   SVCW FETCH_IMM32
0x183    {br(C_FAULT, rel10(0x183, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x184    {svcw_small(EA_CALC_32)}   SVCW EA_CALC_32
0x185    {br(C_FAULT, rel10(0x185, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x186    {svcw_small(STORE_RM32)}   SVCW STORE_RM32
0x187    {br(C_FAULT, rel10(0x187, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x188    {endi(CM_NOP_EIP)}   ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x18A    {svcw_small(FETCH_IMM8)}   mov_rm_imm8: SVCW FETCH_IMM8
0x18B    {br(C_FAULT, rel10(0x18B, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x18C    {svcw_small(EA_CALC_32)}   SVCW EA_CALC_32
0x18D    {br(C_FAULT, rel10(0x18D, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x18E    {svcw_small(STORE_RM8)}   SVCW STORE_RM8
0x18F    {br(C_FAULT, rel10(0x18F, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x190    {endi(CM_NOP_EIP)}   ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x194    {svcw_small(FETCH_IMM16)}   mov_rm_imm16: SVCW FETCH_IMM16
0x195    {br(C_FAULT, rel10(0x195, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x196    {svcw_small(EA_CALC_32)}   SVCW EA_CALC_32
0x197    {br(C_FAULT, rel10(0x197, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x198    {svcw_small(STORE_RM16)}   SVCW STORE_RM16
0x199    {br(C_FAULT, rel10(0x199, 0x000))}   BR C_FAULT, SUB_FAULT_HANDLER
0x19A    {endi(CM_NOP_EIP)}   ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
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
print(f"  CM_MOV_REG = 0x{CM_MOV_REG:03X}")
print(f"  ENTRY_MOV       at dispatch[0x01] -> uPC 0x100 (Rung 6 Pass 6F-2 MOV immediate/register/memory/immediate-to-memory/immediate-to-register/SIB-base/SIB-no-base)")
