# Roadmap

## Generation Aegis

### Milestone A0
- repository scaffold
- frozen constitutional spec imported
- Appendix A codegen scaffold
- CI/check pipeline bootstrap

### Milestone A1
- rung 0 bring-up complete
- reset path verified
- ENTRY_NULL and ENTRY_NOP_XCHG_AX working
- prefetch/decode loop stable

### Milestone A2
- near control-flow proof set complete
- ENTRY_JMP_NEAR
- ENTRY_CALL_NEAR
- ENTRY_RET_NEAR
- ENTRY_JCC

### Milestone A3
- bounded real-mode INT/IRET/#UD proof verified/documented as Rung 5
- latest record: `docs/implementation/rung5_verification.md`
- documentation closeout: `79cef97 docs: record committed rung5 verification`

Rung 5 does not claim protected-mode interrupt behavior. Rung 6 remains blocked
until Rung 5 is explicitly accepted and Rung 6 is started under the proven
workflow.

### Milestone A4
- MOV family

### Milestone A5
- ALU family

### Milestone A6
- remaining phase-1 instructions
- compliance and system milestones
