`ifndef KEYSTONE86_COMMIT_DEFS_SVH
`define KEYSTONE86_COMMIT_DEFS_SVH

`define STAGE_GPR          6'h00
`define STAGE_EIP          6'h01
`define STAGE_EFLAGS       6'h02
`define STAGE_SEG          6'h03
`define STAGE_STACK        6'h04
`define STAGE_MISC         6'h05
`define STAGE_STACK_ADJ    6'h06
`define STAGE_EFLAGS_MASK  6'h07

`define CM_GPR     10'b0000000001
`define CM_EIP     10'b0000000010
`define CM_EFLAGS  10'b0000000100
`define CM_SEG     10'b0000001000
`define CM_STACK   10'b0000010000
`define CM_MISC    10'b0000100000
`define CM_CLR03   10'b0001000000
`define CM_CLR47   10'b0010000000
`define CM_CLRF    10'b0100000000
`define CM_FLUSHQ  10'b1000000000

`define CM_ALU_REG   (`CM_GPR | `CM_EFLAGS | `CM_CLR03 | `CM_CLR47 | `CM_CLRF)
`define CM_MOV_REG   (`CM_GPR | `CM_CLR03 | `CM_CLR47 | `CM_CLRF)
`define CM_JMP       (`CM_EIP | `CM_CLR03 | `CM_CLR47 | `CM_CLRF | `CM_FLUSHQ)
`define CM_CALL      (`CM_STACK | `CM_EIP | `CM_CLR03 | `CM_CLR47 | `CM_CLRF | `CM_FLUSHQ)
`define CM_RET       (`CM_STACK | `CM_EIP | `CM_CLR03 | `CM_CLR47 | `CM_CLRF | `CM_FLUSHQ)
`define CM_INT       (`CM_SEG | `CM_STACK | `CM_EFLAGS | `CM_EIP | `CM_CLR03 | `CM_CLR47 | `CM_CLRF | `CM_FLUSHQ)
`define CM_IRET      (`CM_SEG | `CM_STACK | `CM_EFLAGS | `CM_EIP | `CM_CLR03 | `CM_CLR47 | `CM_CLRF | `CM_FLUSHQ)
`define CM_FLAGS     (`CM_EFLAGS | `CM_CLR03 | `CM_CLR47 | `CM_CLRF)
`define CM_NOP       (`CM_CLR03 | `CM_CLR47 | `CM_CLRF)
`define CM_FAULT_END (`CM_CLR03)
`define CM_STACK_ONLY (`CM_STACK | `CM_CLR03 | `CM_CLR47 | `CM_CLRF)

`endif
