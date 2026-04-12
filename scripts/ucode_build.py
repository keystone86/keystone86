from pathlib import Path

build = Path("microcode/build")
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
# Microcode ROM
# --------------------------------------------------------------------
# Encoding (Appendix A Section 7.1):
#   bits[31:28] = UOP_CLASS
#   bits[27:22] = TARGET
#   bits[9:0]   = IMM10
#
# UOP_CLASS:  RAISE=0xC  ENDI=0xE
# FC_UD = 0x6
#
# Commit masks (Appendix A Section 3.8):
#   CM_EIP       = bit 1  = 0x002
#   CM_CLR03     = bit 6  = 0x040
#   CM_CLR47     = bit 7  = 0x080
#   CM_CLRF      = bit 8  = 0x100
#   CM_FAULT_END = CM_CLR03                     = 0x040
#   CM_NOP       = CM_CLR03|CM_CLR47|CM_CLRF    = 0x1C0
#   CM_NOP_EIP   = CM_NOP|CM_EIP                = 0x1C2  <- Rung 1

CM_EIP       = 0x002
CM_CLR03     = 0x040
CM_CLR47     = 0x080
CM_CLRF      = 0x100
CM_FAULT_END = CM_CLR03
CM_NOP       = CM_CLR03 | CM_CLR47 | CM_CLRF
CM_NOP_EIP   = CM_NOP | CM_EIP     # Rung 1: NOP + visible EIP advancement

def endi(mask):
    return f"{0xE0000000 | mask:08X}"

def raise_fc(fc):
    return f"{0xC0000000 | (fc << 22):08X}"

rom = ["00000000"] * 4096

rom[0x000] = endi(CM_FAULT_END)  # SUB_FAULT_HANDLER: ENDI CM_FAULT_END
rom[0x010] = raise_fc(0x6)       # ENTRY_NULL: RAISE FC_UD
rom[0x011] = endi(CM_FAULT_END)  # ENDI CM_FAULT_END

# Rung 1: NOP and PREFIX_ONLY now use CM_NOP_EIP to commit EIP visibly
rom[0x020] = endi(CM_NOP_EIP)    # ENTRY_NOP_XCHG_AX: ENDI CM_NOP|CM_EIP
rom[0x030] = endi(CM_NOP_EIP)    # ENTRY_PREFIX_ONLY: ENDI CM_NOP|CM_EIP
rom[0x040] = endi(CM_NOP)        # ENTRY_RESET: ENDI CM_NOP (no EIP commit at reset)

(build / "ucode.hex").write_text("\n".join(rom) + "\n", encoding="utf-8")

listing = f"""; Keystone86 / Aegis bootstrap microcode listing (Rung 1)
; ENTRY_NOP_XCHG_AX and ENTRY_PREFIX_ONLY now use CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
; so architectural EIP advances by 1 after every NOP.
address  encoding     source
0x000    {endi(CM_FAULT_END)}   SUB_FAULT_HANDLER: ENDI CM_FAULT_END
0x010    {raise_fc(0x6)}   ENTRY_NULL: RAISE FC_UD
0x011    {endi(CM_FAULT_END)}   ENDI CM_FAULT_END
0x020    {endi(CM_NOP_EIP)}   ENTRY_NOP_XCHG_AX: ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x030    {endi(CM_NOP_EIP)}   ENTRY_PREFIX_ONLY: ENDI CM_NOP|CM_EIP (0x{CM_NOP_EIP:03X})
0x040    {endi(CM_NOP)}   ENTRY_RESET: ENDI CM_NOP
"""
(build / "ucode.lst").write_text(listing, encoding="utf-8")

print("Wrote Rung 1 bootstrap ucode.hex, dispatch.hex, ucode.lst, dispatch.lst")
print(f"  CM_NOP_EIP = 0x{CM_NOP_EIP:03X} (CM_NOP|CM_EIP)")
print(f"  ENTRY_NOP_XCHG_AX ENDI word = {endi(CM_NOP_EIP)}")
print(f"  ENTRY_PREFIX_ONLY ENDI word = {endi(CM_NOP_EIP)}")
