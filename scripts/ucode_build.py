from pathlib import Path

build = Path("microcode/build")
build.mkdir(parents=True, exist_ok=True)

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
        val = 0x050
        meaning = "ENTRY_JMP_NEAR"
    elif i == 0x09:
        val = 0x060
        meaning = "ENTRY_CALL_NEAR"
    elif i == 0x0B:
        val = 0x070
        meaning = "ENTRY_RET_NEAR"
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
CM_CALL      = CM_STACK | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ
CM_RET       = CM_STACK | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ

FETCH_DISP8            = 0x04
COMPUTE_REL_TARGET     = 0x46
VALIDATE_NEAR_TRANSFER = 0x44

C_ALWAYS = 0x0
C_OK     = 0x1
C_WAIT   = 0x2
C_FAULT  = 0x3

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

def rel10(from_addr: int, to_addr: int) -> int:
    delta = to_addr - (from_addr + 1)
    if delta < -512 or delta > 511:
        raise ValueError(f"BR target out of range: from 0x{from_addr:03X} to 0x{to_addr:03X}")
    return delta & 0x3FF

rom = ["00000000"] * 4096

rom[0x000] = endi(CM_FAULT_END)
rom[0x010] = raise_fc(0x6)
rom[0x011] = endi(CM_FAULT_END)

rom[0x020] = endi(CM_NOP_EIP)
rom[0x030] = endi(CM_NOP_EIP)
rom[0x040] = endi(CM_NOP)

rom[0x050] = svcw_small(FETCH_DISP8)
rom[0x051] = br(C_FAULT, rel10(0x051, 0x000))
rom[0x052] = ext_word()
rom[0x053] = svcw_ext(COMPUTE_REL_TARGET)
rom[0x054] = br(C_FAULT, rel10(0x054, 0x000))
rom[0x055] = ext_word()
rom[0x056] = svcw_ext(VALIDATE_NEAR_TRANSFER)
rom[0x057] = br(C_FAULT, rel10(0x057, 0x000))
rom[0x058] = endi(CM_JMP)

rom[0x060] = endi(CM_CALL)
rom[0x070] = endi(CM_RET)

(build / "ucode.hex").write_text("\n".join(rom) + "\n", encoding="utf-8")

listing = f"""; Keystone86 / Aegis bootstrap microcode listing
; bounded Rung 2 / Rung 3 bootstrap microcode
address  encoding     source
0x000    {endi(CM_FAULT_END)}   SUB_FAULT_HANDLER: ENDI CM_FAULT_END
0x010    {raise_fc(0x6)}   ENTRY_NULL: RAISE FC_UD
0x011    {endi(CM_FAULT_END)}   ENDI CM_FAULT_END
0x020    {endi(CM_NOP_EIP)}   ENTRY_NOP_XCHG_AX: ENDI CM_NOP|CM_EIP
0x030    {endi(CM_NOP_EIP)}   ENTRY_PREFIX_ONLY: ENDI CM_NOP|CM_EIP
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
0x060    {endi(CM_CALL)}   ENTRY_CALL_NEAR: ENDI CM_CALL (0x{CM_CALL:03X})
0x070    {endi(CM_RET)}   ENTRY_RET_NEAR: ENDI CM_RET (0x{CM_RET:03X})
"""
(build / "ucode.lst").write_text(listing, encoding="utf-8")

print("Wrote bootstrap ucode.hex, dispatch.hex, ucode.lst, dispatch.lst")
print(f"  CM_JMP  = 0x{CM_JMP:03X}")
print(f"  CM_CALL = 0x{CM_CALL:03X}")
print(f"  CM_RET  = 0x{CM_RET:03X}")
print("  ENTRY_CALL_NEAR at dispatch[0x09] -> uPC 0x060")
print("  ENTRY_RET_NEAR  at dispatch[0x0B] -> uPC 0x070")