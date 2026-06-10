// Keystone86 / Aegis
// keystone86_pkg.sv — Complete shared parameter package
// Auto-generated from Appendix A Field Dictionary (frozen spec)
// DO NOT EDIT MANUALLY — regenerate via: make codegen
//
// This file is the AUTHORITATIVE RTL source for all shared constants.
// All RTL modules must use: import keystone86_pkg::*;
//
// The legacy *.svh files in this directory (entry_ids.svh, fault_defs.svh,
// commit_defs.svh, field_defs.svh, service_ids.svh) contain the same
// constants as backtick macros. They are retained for compatibility with
// external tooling only. RTL source files must NOT use `include for these —
// use this package import instead.
//
// See docs/implementation/coding_rules/source_of_truth.md for the full
// authoritative-source map.

package keystone86_pkg;

    // ----------------------------------------------------------------
    // ENTRY IDENTIFIERS (Appendix A Section 4)
    // ----------------------------------------------------------------
    localparam logic [7:0] ENTRY_NULL             = 8'h00;
    localparam logic [7:0] ENTRY_MOV              = 8'h01;
    localparam logic [7:0] ENTRY_ALU_RM_R         = 8'h02;
    localparam logic [7:0] ENTRY_ALU_R_RM         = 8'h03;
    localparam logic [7:0] ENTRY_ALU_RM_IMM       = 8'h04;
    localparam logic [7:0] ENTRY_PUSH             = 8'h05;
    localparam logic [7:0] ENTRY_POP              = 8'h06;
    localparam logic [7:0] ENTRY_JMP_NEAR         = 8'h07;
    localparam logic [7:0] ENTRY_CALL_NEAR        = 8'h09;
    localparam logic [7:0] ENTRY_RET_NEAR         = 8'h0B;
    localparam logic [7:0] ENTRY_JCC              = 8'h0D;
    localparam logic [7:0] ENTRY_INT              = 8'h0E;
    localparam logic [7:0] ENTRY_IRET             = 8'h0F;
    localparam logic [7:0] ENTRY_PREFIX_ONLY      = 8'h12;
    localparam logic [7:0] ENTRY_NOP_XCHG_AX      = 8'h13;
    localparam logic [7:0] ENTRY_INC_DEC_REG      = 8'h14;
    localparam logic [7:0] ENTRY_TEST             = 8'h15;
    localparam logic [7:0] ENTRY_LEA              = 8'h16;
    localparam logic [7:0] ENTRY_FLAGS_SIMPLE     = 8'h17;
    localparam logic [7:0] ENTRY_RESET            = 8'hFF;  // startup only

    // ----------------------------------------------------------------
    // SERVICE IDENTIFIERS (Appendix A Section 5)
    // ----------------------------------------------------------------
    localparam logic [7:0] SVC_NULL                 = 8'h00;
    // Fetch
    localparam logic [7:0] FETCH_IMM8                 = 8'h01;
    localparam logic [7:0] FETCH_IMM16                = 8'h02;
    localparam logic [7:0] FETCH_IMM32                = 8'h03;
    localparam logic [7:0] FETCH_DISP8                = 8'h04;
    localparam logic [7:0] FETCH_DISP16               = 8'h05;
    localparam logic [7:0] FETCH_DISP32               = 8'h06;
    // Address
    localparam logic [7:0] EA_CALC_16                 = 8'h10;
    localparam logic [7:0] EA_CALC_32                 = 8'h11;
    // Operand
    localparam logic [7:0] LOAD_RM8                   = 8'h20;
    localparam logic [7:0] LOAD_RM16                  = 8'h21;
    localparam logic [7:0] LOAD_RM32                  = 8'h22;
    localparam logic [7:0] STORE_RM8                  = 8'h23;
    localparam logic [7:0] STORE_RM16                 = 8'h24;
    localparam logic [7:0] STORE_RM32                 = 8'h25;
    localparam logic [7:0] LOAD_REG_META              = 8'h26;
    localparam logic [7:0] STORE_REG_META             = 8'h27;
    // ALU
    localparam logic [7:0] ALU_ADD8                   = 8'h30;
    localparam logic [7:0] ALU_ADD16                  = 8'h31;
    localparam logic [7:0] ALU_ADD32                  = 8'h32;
    localparam logic [7:0] ALU_SUB8                   = 8'h33;
    localparam logic [7:0] ALU_SUB16                  = 8'h34;
    localparam logic [7:0] ALU_SUB32                  = 8'h35;
    localparam logic [7:0] ALU_LOGIC8                 = 8'h36;
    localparam logic [7:0] ALU_LOGIC16                = 8'h37;
    localparam logic [7:0] ALU_LOGIC32                = 8'h38;
    localparam logic [7:0] ALU_CMP8                   = 8'h39;
    localparam logic [7:0] ALU_CMP16                  = 8'h3A;
    localparam logic [7:0] ALU_CMP32                  = 8'h3B;
    // Stack/flow
    localparam logic [7:0] PUSH16                     = 8'h40;
    localparam logic [7:0] PUSH32                     = 8'h41;
    localparam logic [7:0] POP16                      = 8'h42;
    localparam logic [7:0] POP32                      = 8'h43;
    localparam logic [7:0] VALIDATE_NEAR_TRANSFER     = 8'h44;
    localparam logic [7:0] COMPUTE_REL_TARGET         = 8'h46;
    localparam logic [7:0] CONDITION_EVAL             = 8'h47;
    localparam logic [7:0] INT_ENTER                  = 8'h62;
    localparam logic [7:0] IRET_FLOW                  = 8'h63;
    // Commit
    localparam logic [7:0] COMMIT_GPR                 = 8'h80;
    localparam logic [7:0] COMMIT_EIP                 = 8'h81;
    localparam logic [7:0] COMMIT_EFLAGS              = 8'h82;
    localparam logic [7:0] COMMIT_STACK               = 8'h84;
    localparam logic [7:0] END_INSTRUCTION            = 8'h85;

    // ----------------------------------------------------------------
    // SERVICE RESULT CODES (Appendix A Section 6.2)
    // ----------------------------------------------------------------
    localparam logic [1:0] SR_OK    = 2'h0;
    localparam logic [1:0] SR_WAIT  = 2'h1;
    localparam logic [1:0] SR_FAULT = 2'h2;

    // ----------------------------------------------------------------
    // FAULT CLASS CODES (Appendix A Section 6.1)
    // ----------------------------------------------------------------
    localparam logic [3:0] FC_NONE  = 4'h0;
    localparam logic [3:0] FC_GP    = 4'h1;
    localparam logic [3:0] FC_SS    = 4'h2;
    localparam logic [3:0] FC_NP    = 4'h3;
    localparam logic [3:0] FC_PF    = 4'h4;
    localparam logic [3:0] FC_TS    = 4'h5;
    localparam logic [3:0] FC_UD    = 4'h6;
    localparam logic [3:0] FC_DE    = 4'h7;
    localparam logic [3:0] FC_NM    = 4'h8;
    localparam logic [3:0] FC_AC    = 4'h9;
    localparam logic [3:0] FC_INT   = 4'hA;
    localparam logic [3:0] FC_DF    = 4'hB;
    localparam logic [3:0] FC_BR    = 4'hC;
    localparam logic [3:0] FC_OF    = 4'hD;

    // ----------------------------------------------------------------
    // COMMIT MASK BITS (Appendix A Section 3.8)
    // ----------------------------------------------------------------
    localparam logic [9:0] CM_GPR       = 10'b0000000001;
    localparam logic [9:0] CM_EIP       = 10'b0000000010;
    localparam logic [9:0] CM_EFLAGS    = 10'b0000000100;
    localparam logic [9:0] CM_SEG       = 10'b0000001000;
    localparam logic [9:0] CM_STACK     = 10'b0000010000;
    localparam logic [9:0] CM_MISC      = 10'b0000100000;
    localparam logic [9:0] CM_CLR03     = 10'b0001000000;
    localparam logic [9:0] CM_CLR47     = 10'b0010000000;
    localparam logic [9:0] CM_CLRF      = 10'b0100000000;
    localparam logic [9:0] CM_FLUSHQ    = 10'b1000000000;
    // Standard combined masks (Appendix A Section 3.9)
    localparam logic [9:0] CM_ALU_REG   = CM_GPR | CM_EFLAGS | CM_CLR03 | CM_CLR47 | CM_CLRF;
    localparam logic [9:0] CM_MOV_REG   = CM_GPR | CM_CLR03 | CM_CLR47 | CM_CLRF;
    localparam logic [9:0] CM_JMP       = CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ;
    localparam logic [9:0] CM_CALL      = CM_STACK | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ;
    localparam logic [9:0] CM_RET       = CM_STACK | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ;
    localparam logic [9:0] CM_INT       = CM_SEG | CM_STACK | CM_EFLAGS | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ;
    localparam logic [9:0] CM_IRET      = CM_SEG | CM_STACK | CM_EFLAGS | CM_EIP | CM_CLR03 | CM_CLR47 | CM_CLRF | CM_FLUSHQ;
    localparam logic [9:0] CM_FLAGS     = CM_EFLAGS | CM_CLR03 | CM_CLR47 | CM_CLRF;
    localparam logic [9:0] CM_NOP       = CM_CLR03 | CM_CLR47 | CM_CLRF;
    localparam logic [9:0] CM_FAULT_END = CM_CLR03;
    localparam logic [9:0] CM_STACK_ONLY = CM_STACK | CM_CLR03 | CM_CLR47 | CM_CLRF;

    // ----------------------------------------------------------------
    // STAGE FIELD SELECTORS (Appendix A Section 3.7)
    // ----------------------------------------------------------------
    localparam logic [5:0] STAGE_GPR          = 6'h00;
    localparam logic [5:0] STAGE_EIP          = 6'h01;
    localparam logic [5:0] STAGE_EFLAGS       = 6'h02;
    localparam logic [5:0] STAGE_SEG          = 6'h03;
    localparam logic [5:0] STAGE_STACK        = 6'h04;
    localparam logic [5:0] STAGE_MISC         = 6'h05;
    localparam logic [5:0] STAGE_STACK_ADJ    = 6'h06;
    localparam logic [5:0] STAGE_EFLAGS_MASK  = 6'h07;

    // ----------------------------------------------------------------
    // ALU OPERATION SELECTORS (Appendix A Section 2.6)
    // ----------------------------------------------------------------
    localparam logic [3:0] ALU_ADD      = 4'h0;
    localparam logic [3:0] ALU_SUB      = 4'h5;
    localparam logic [3:0] ALU_CMP      = 4'h7;

    // ----------------------------------------------------------------
    // MICROINSTRUCTION CLASSES (Appendix A Section 7.2)
    // ----------------------------------------------------------------
    localparam logic [3:0] UOP_NOP      = 4'h0;
    localparam logic [3:0] UOP_BR       = 4'h4;
    localparam logic [3:0] UOP_MOV      = 4'h5;
    localparam logic [3:0] UOP_EXTRACT  = 4'h7;
    localparam logic [3:0] UOP_SVCW     = 4'h9;
    localparam logic [3:0] UOP_STAGE    = 4'hA;
    localparam logic [3:0] UOP_RAISE    = 4'hC;
    localparam logic [3:0] UOP_ENDI     = 4'hE;
    localparam logic [3:0] UOP_EXT      = 4'hF;

    // ----------------------------------------------------------------
    // METADATA EXTRACT FIELDS (Appendix A Section 7.6)
    // ----------------------------------------------------------------
    localparam logic [9:0] MF_ENTRY_ID      = 10'h000;
    localparam logic [9:0] M_ENTRY_ID       = MF_ENTRY_ID;
    localparam logic [9:0] MF_OPSZ          = 10'h001;
    localparam logic [9:0] M_OPSZ           = MF_OPSZ;
    localparam logic [9:0] MF_ADDRSZ        = 10'h002;
    localparam logic [9:0] M_ADDRSZ         = MF_ADDRSZ;
    localparam logic [9:0] MF_MODRM_CLASS   = 10'h003;
    localparam logic [9:0] M_MODRM_CLASS    = MF_MODRM_CLASS;
    localparam logic [9:0] MF_IMM_CLASS     = 10'h004;
    localparam logic [9:0] M_IMM_CLASS      = MF_IMM_CLASS;
    localparam logic [9:0] MF_DISP_CLASS    = 10'h005;
    localparam logic [9:0] M_DISP_CLASS     = MF_DISP_CLASS;
    localparam logic [9:0] MF_OPCODE_CLASS  = 10'h006;
    localparam logic [9:0] M_OPCODE_CLASS   = MF_OPCODE_CLASS;
    localparam logic [9:0] MF_ALU_OP        = 10'h007;
    localparam logic [9:0] M_ALU_OP         = MF_ALU_OP;
    localparam logic [9:0] MF_IS_CMP        = 10'h008;
    localparam logic [9:0] M_IS_CMP         = MF_IS_CMP;
    localparam logic [9:0] MF_REG_DST       = 10'h009;
    localparam logic [9:0] M_REG_DST        = MF_REG_DST;
    localparam logic [9:0] MF_REG_SRC       = 10'h00A;
    localparam logic [9:0] M_REG_SRC        = MF_REG_SRC;
    localparam logic [9:0] MF_REG_RM        = 10'h00B;
    localparam logic [9:0] M_REG_RM         = MF_REG_RM;
    localparam logic [9:0] MF_SIB_SCALE     = 10'h00C;
    localparam logic [9:0] M_SIB_SCALE      = MF_SIB_SCALE;
    localparam logic [9:0] MF_SIB_INDEX     = 10'h00D;
    localparam logic [9:0] M_SIB_INDEX      = MF_SIB_INDEX;
    localparam logic [9:0] MF_SIB_BASE      = 10'h00E;
    localparam logic [9:0] M_SIB_BASE       = MF_SIB_BASE;
    localparam logic [9:0] MF_COND_CODE     = 10'h00F;
    localparam logic [9:0] M_COND_CODE      = MF_COND_CODE;
    localparam logic [9:0] MF_FLAG_BIT      = 10'h010;
    localparam logic [9:0] M_FLAG_BIT       = MF_FLAG_BIT;
    localparam logic [9:0] MF_FLAG_VAL      = 10'h011;
    localparam logic [9:0] M_FLAG_VAL       = MF_FLAG_VAL;
    localparam logic [9:0] MF_NEXT_EIP      = 10'h012;
    localparam logic [9:0] M_NEXT_EIP       = MF_NEXT_EIP;
    localparam logic [9:0] MF_FC_TO_VECTOR  = 10'h013;
    localparam logic [9:0] M_FC_TO_VECTOR   = MF_FC_TO_VECTOR;
    localparam logic [9:0] MF_PREFIX1       = 10'h014;
    localparam logic [9:0] M_PREFIX1        = MF_PREFIX1;
    localparam logic [9:0] MF_PREFIX2       = 10'h015;
    localparam logic [9:0] M_PREFIX2        = MF_PREFIX2;

    // ----------------------------------------------------------------
    // MICROINSTRUCTION REGISTER NAMESPACE (Appendix A Section 7.4)
    // ----------------------------------------------------------------
    localparam logic [3:0] REG_T0       = 4'h0;
    localparam logic [3:0] REG_T1       = 4'h1;
    localparam logic [3:0] REG_T2       = 4'h2;
    localparam logic [3:0] REG_T3       = 4'h3;
    localparam logic [3:0] REG_T4       = 4'h4;
    localparam logic [3:0] REG_T5       = 4'h5;
    localparam logic [3:0] REG_T6       = 4'h6;
    localparam logic [3:0] REG_T7       = 4'h7;
    localparam logic [3:0] REG_S0       = 4'h8;
    localparam logic [3:0] REG_S1       = 4'h9;
    localparam logic [3:0] REG_SR       = 4'hA;
    localparam logic [3:0] REG_FC       = 4'hB;
    localparam logic [3:0] REG_FE       = 4'hC;
    localparam logic [3:0] REG_D0L      = 4'hD;
    localparam logic [3:0] REG_D0H      = 4'hE;
    localparam logic [3:0] REG_SPECIAL  = 4'hF;

    // ----------------------------------------------------------------
    // CONDITION CODES (Appendix A Section 7.3)
    // ----------------------------------------------------------------
    localparam logic [3:0] C_ALWAYS   = 4'h0;
    localparam logic [3:0] C_OK       = 4'h1;
    localparam logic [3:0] C_WAIT     = 4'h2;
    localparam logic [3:0] C_FAULT    = 4'h3;
    localparam logic [3:0] C_T0Z      = 4'h4;
    localparam logic [3:0] C_T0NZ     = 4'h5;
    localparam logic [3:0] C_W16      = 4'h6;
    localparam logic [3:0] C_W32      = 4'h7;
    localparam logic [3:0] C_REAL     = 4'h8;
    localparam logic [3:0] C_PROT     = 4'h9;
    localparam logic [3:0] C_REP      = 4'hA;
    localparam logic [3:0] C_W8       = 4'hB;
    localparam logic [3:0] C_T3Z      = 4'hC;
    localparam logic [3:0] C_T3NZ     = 4'hD;
    localparam logic [3:0] C_ADDR16   = 4'hE;
    localparam logic [3:0] C_ADDR32   = 4'hF;

    // ----------------------------------------------------------------
    // MICROSEQUENCER STATES
    // ----------------------------------------------------------------
    localparam logic [1:0] MSEQ_FETCH_DECODE  = 2'h0;
    localparam logic [1:0] MSEQ_EXECUTE       = 2'h1;
    localparam logic [1:0] MSEQ_WAIT_SERVICE  = 2'h2;
    localparam logic [1:0] MSEQ_FAULT_HOLD    = 2'h3;

endpackage
