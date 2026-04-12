from pathlib import Path

build = Path("microcode/build")
build.mkdir(parents=True, exist_ok=True)

# --------------------------------------------------------------------
# Dispatch table
# 256 entries, 12-bit uPC values
# dispatch.hex: strict machine-readable input for $readmemh
# dispatch.lst: human-readable annotated listing
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
# 4096 entries, 32-bit words
# ucode.hex: strict machine-readable input for $readmemh
# ucode.lst: human-readable annotated listing
# --------------------------------------------------------------------
rom = ["00000000"] * 4096

# Bootstrap routines
#
# Encoding used by microsequencer.sv:
#   bits [31:28] = UOP_CLASS
#   bits [27:22] = TARGET
#   bits [21:18] = COND
#   bits [17:14] = DST
#   bits [13:10] = SRC
#   bits [9:0]   = IMM10
#
# UOP_CLASS values in use:
#   RAISE = 0xC
#   ENDI  = 0xE
#
# Fault class:
#   FC_UD = 0x6
#
# Commit masks:
#   CM_FAULT_END = 0x040
#   CM_NOP       = 0x1C0

rom[0x000] = "E0000040"  # SUB_FAULT_HANDLER: ENDI CM_FAULT_END
rom[0x010] = "C1800000"  # ENTRY_NULL: RAISE FC_UD
rom[0x011] = "E0000040"  # ENDI CM_FAULT_END
rom[0x020] = "E00001C0"  # ENTRY_NOP_XCHG_AX: ENDI CM_NOP
rom[0x030] = "E00001C0"  # ENTRY_PREFIX_ONLY: ENDI CM_NOP
rom[0x040] = "E00001C0"  # ENTRY_RESET: ENDI CM_NOP

(build / "ucode.hex").write_text("\n".join(rom) + "\n", encoding="utf-8")

listing = """; Keystone86 / Aegis bootstrap microcode listing
address  encoding     source
0x000    0xE0000040   SUB_FAULT_HANDLER: ENDI CM_FAULT_END
0x010    0xC1800000   ENTRY_NULL: RAISE FC_UD
0x011    0xE0000040   ENDI CM_FAULT_END
0x020    0xE00001C0   ENTRY_NOP_XCHG_AX: ENDI CM_NOP
0x030    0xE00001C0   ENTRY_PREFIX_ONLY: ENDI CM_NOP
0x040    0xE00001C0   ENTRY_RESET: ENDI CM_NOP
"""
(build / "ucode.lst").write_text(listing, encoding="utf-8")

print("Wrote concrete bootstrap ucode.hex, dispatch.hex, ucode.lst, and dispatch.lst")