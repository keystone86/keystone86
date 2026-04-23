# Rung 0

## Bootstrap microcode seed

The initial ROM seed fixes:
- `SUB_FAULT_HANDLER`
- `ENTRY_NULL`
- `ENTRY_NOP_XCHG_AX`
- `ENTRY_PREFIX_ONLY`
- `ENTRY_RESET`

Generated bootstrap artifacts:
- `build/microcode/dispatch.hex`
- `build/microcode/ucode.hex`
- `build/microcode/ucode.lst`

Validation:
```bash
make ucode
make ucode-bootstrap-check
```
