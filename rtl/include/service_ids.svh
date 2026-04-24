`ifndef KEYSTONE86_SERVICE_IDS_SVH
`define KEYSTONE86_SERVICE_IDS_SVH

`define FETCH_IMM8                 8'h01
`define FETCH_IMM16                8'h02
`define FETCH_IMM32                8'h03
`define FETCH_DISP8                8'h04
`define FETCH_DISP16               8'h05
`define FETCH_DISP32               8'h06
`define EA_CALC_16                 8'h10
`define EA_CALC_32                 8'h11
`define LOAD_RM8                   8'h20
`define LOAD_RM16                  8'h21
`define LOAD_RM32                  8'h22
`define STORE_RM8                  8'h23
`define STORE_RM16                 8'h24
`define STORE_RM32                 8'h25
`define LOAD_REG_META              8'h26
`define STORE_REG_META             8'h27
`define ALU_ADD8                   8'h30
`define ALU_ADD16                  8'h31
`define ALU_ADD32                  8'h32
`define ALU_SUB8                   8'h33
`define ALU_SUB16                  8'h34
`define ALU_SUB32                  8'h35
`define ALU_LOGIC8                 8'h36
`define ALU_LOGIC16                8'h37
`define ALU_LOGIC32                8'h38
`define ALU_CMP8                   8'h39
`define ALU_CMP16                  8'h3A
`define ALU_CMP32                  8'h3B
`define PUSH16                     8'h40
`define PUSH32                     8'h41
`define POP16                      8'h42
`define POP32                      8'h43
`define VALIDATE_NEAR_TRANSFER     8'h44
`define COMPUTE_REL_TARGET         8'h46
`define CONDITION_EVAL             8'h47
`define INT_ENTER                  8'h62
`define IRET_FLOW                  8'h63
`define COMMIT_GPR                 8'h80
`define COMMIT_EIP                 8'h81
`define COMMIT_EFLAGS              8'h82
`define COMMIT_STACK               8'h84
`define END_INSTRUCTION            8'h85

`endif
