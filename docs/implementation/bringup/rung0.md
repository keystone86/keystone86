# Rung 0

## Bootstrap microcode seed

The initial ROM seed fixes:
- `SUB_FAULT_HANDLER`
- `ENTRY_NULL`
- `ENTRY_NOP_XCHG_AX`
- `ENTRY_PREFIX_ONLY`
- `ENTRY_RESET`

Generated bootstrap artifacts:
- `microcode/build/dispatch.hex`
- `microcode/build/ucode.hex`
- `microcode/build/ucode.lst`

Validation:
```bash
make ucode
make ucode-bootstrap-check
```
