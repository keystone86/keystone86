// LEGACY COMPATIBILITY HEADER — do not use in new RTL source files.
// The authoritative source for these constants is rtl/include/keystone86_pkg.sv.
// RTL modules must use: import keystone86_pkg::*;
// This file is retained for external tooling compatibility only.
`ifndef KEYSTONE86_FAULT_DEFS_SVH
`define KEYSTONE86_FAULT_DEFS_SVH

`define SR_OK      2'h0
`define SR_WAIT    2'h1
`define SR_FAULT   2'h2

`define FC_NONE    4'h0
`define FC_GP      4'h1
`define FC_SS      4'h2
`define FC_NP      4'h3
`define FC_PF      4'h4
`define FC_TS      4'h5
`define FC_UD      4'h6
`define FC_DE      4'h7
`define FC_NM      4'h8
`define FC_AC      4'h9
`define FC_INT     4'hA
`define FC_DF      4'hB
`define FC_BR      4'hC
`define FC_OF      4'hD

`endif
