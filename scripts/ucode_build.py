from pathlib import Path

build = Path('microcode/build')
build.mkdir(parents=True, exist_ok=True)

dispatch_lines = ['; Bootstrap dispatch table', '; 256 entries, 12-bit uPC addresses', '']
for i in range(256):
    if i == 0x00:
        val = 0x010
    elif i == 0x12:
        val = 0x030
    elif i == 0x13:
        val = 0x020
    elif i == 0xFF:
        val = 0x040
    else:
        val = 0x010
    dispatch_lines.append(f'{val:03X}')
(build / 'dispatch.hex').write_text('\n'.join(dispatch_lines) + '\n', encoding='utf-8')

rom = ['00000000'] * 0x041
rom[0x000] = '0000E040'
rom[0x010] = '0000C600'
rom[0x011] = '0000E040'
rom[0x020] = '0000E3C0'
rom[0x030] = '0000E3C0'
rom[0x040] = '0000E3C0'
(build / 'ucode.hex').write_text('\n'.join(rom) + '\n', encoding='utf-8')

listing = '''; Keystone86 / Aegis bootstrap microcode listing
address  encoding     source
0x000    0xE040       SUB_FAULT_HANDLER: ENDI CM_FAULT_END
0x010    0xC600       ENTRY_NULL: RAISE FC_UD
0x011    0xE040       ENDI CM_FAULT_END
0x020    0xE3C0       ENTRY_NOP_XCHG_AX: ENDI CM_NOP
0x030    0xE3C0       ENTRY_PREFIX_ONLY: ENDI CM_NOP
0x040    0xE3C0       ENTRY_RESET: ENDI CM_NOP
'''
(build / 'ucode.lst').write_text(listing, encoding='utf-8')

print('Wrote concrete bootstrap ucode.hex, dispatch.hex, and ucode.lst')
