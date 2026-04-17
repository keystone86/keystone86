// LEGACY COMPATIBILITY HEADER — do not use in new RTL source files.
// The authoritative source for these constants is rtl/include/keystone86_pkg.sv.
// RTL modules must use: import keystone86_pkg::*;
// This file is retained for external tooling compatibility only.
`ifndef KEYSTONE86_ENTRY_IDS_SVH
`define KEYSTONE86_ENTRY_IDS_SVH

`define ENTRY_NULL         8'h00
`define ENTRY_MOV          8'h01
`define ENTRY_ALU_RM_R     8'h02
`define ENTRY_ALU_R_RM     8'h03
`define ENTRY_ALU_RM_IMM   8'h04
`define ENTRY_PUSH         8'h05
`define ENTRY_POP          8'h06
`define ENTRY_JMP_NEAR     8'h07
`define ENTRY_CALL_NEAR    8'h09
`define ENTRY_RET_NEAR     8'h0B
`define ENTRY_JCC          8'h0D
`define ENTRY_INT          8'h0E
`define ENTRY_IRET         8'h0F
`define ENTRY_PREFIX_ONLY  8'h12
`define ENTRY_NOP_XCHG_AX  8'h13
`define ENTRY_INC_DEC_REG  8'h14
`define ENTRY_TEST         8'h15
`define ENTRY_LEA          8'h16
`define ENTRY_FLAGS_SIMPLE 8'h17
`define ENTRY_RESET        8'hFF

`endif
