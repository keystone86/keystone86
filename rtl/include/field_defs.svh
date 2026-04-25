`ifndef KEYSTONE86_FIELD_DEFS_SVH
`define KEYSTONE86_FIELD_DEFS_SVH

// Registers
`define REG_T0       4'h0
`define REG_T1       4'h1
`define REG_T2       4'h2
`define REG_T3       4'h3
`define REG_T4       4'h4
`define REG_T5       4'h5
`define REG_T6       4'h6
`define REG_T7       4'h7
`define REG_S0       4'h8
`define REG_S1       4'h9
`define REG_SR       4'hA
`define REG_FC       4'hB
`define REG_FE       4'hC
`define REG_D0L      4'hD
`define REG_D0H      4'hE
`define REG_SPECIAL  4'hF

// Metadata extract fields
`define MF_ENTRY_ID    10'h000
`define MF_OPSZ        10'h001
`define MF_ADDRSZ      10'h002
`define MF_MODRM_CLASS 10'h003
`define MF_IMM_CLASS   10'h004
`define MF_DISP_CLASS  10'h005
`define MF_OPCODE_CLASS 10'h006
`define MF_ALU_OP      10'h007
`define MF_IS_CMP      10'h008
`define MF_REG_DST     10'h009
`define MF_REG_SRC     10'h00A
`define MF_REG_RM      10'h00B
`define MF_SIB_SCALE   10'h00C
`define MF_SIB_INDEX   10'h00D
`define MF_SIB_BASE    10'h00E
`define MF_COND_CODE   10'h00F
`define MF_FLAG_BIT    10'h010
`define MF_FLAG_VAL    10'h011
`define MF_NEXT_EIP    10'h012
`define MF_FC_TO_VECTOR 10'h013
`define MF_PREFIX1     10'h014
`define MF_PREFIX2     10'h015

// Conditions
`define C_ALWAYS   4'h0
`define C_OK       4'h1
`define C_WAIT     4'h2
`define C_FAULT    4'h3
`define C_T0Z      4'h4
`define C_T0NZ     4'h5
`define C_W16      4'h6
`define C_W32      4'h7
`define C_REAL     4'h8
`define C_PROT     4'h9
`define C_REP      4'hA
`define C_W8       4'hB
`define C_T3Z      4'hC
`define C_T3NZ     4'hD
`define C_ADDR16   4'hE
`define C_ADDR32   4'hF

`endif
