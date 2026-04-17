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
    localparam logic [7:0] ENTRY_NULL          = 8'h00;
    localparam logic [7:0] ENTRY_MOV           = 8'h01;
    localparam logic [7:0] ENTRY_ALU_RM_R      = 8'h02;
    localparam logic [7:0] ENTRY_ALU_R_RM      = 8'h03;
    localparam logic [7:0] ENTRY_ALU_RM_IMM    = 8'h04;
    localparam logic [7:0] ENTRY_PUSH          = 8'h05;
    localparam logic [7:0] ENTRY_POP           = 8'h06;
    localparam logic [7:0] ENTRY_JMP_NEAR      = 8'h07;
    localparam logic [7:0] ENTRY_JMP_FAR       = 8'h08;  // phase 2
    localparam logic [7:0] ENTRY_CALL_NEAR     = 8'h09;
    localparam logic [7:0] ENTRY_CALL_FAR      = 8'h0A;  // phase 2
    localparam logic [7:0] ENTRY_RET_NEAR      = 8'h0B;
    localparam logic [7:0] ENTRY_RET_FAR       = 8'h0C;  // phase 2
    localparam logic [7:0] ENTRY_JCC           = 8'h0D;
    localparam logic [7:0] ENTRY_INT           = 8'h0E;
    localparam logic [7:0] ENTRY_IRET          = 8'h0F;
    localparam logic [7:0] ENTRY_SEG_LOAD      = 8'h10;  // phase 2
    localparam logic [7:0] ENTRY_MISC_SYSTEM   = 8'h11;  // phase 2
    localparam logic [7:0] ENTRY_PREFIX_ONLY   = 8'h12;
    localparam logic [7:0] ENTRY_NOP_XCHG_AX   = 8'h13;
    localparam logic [7:0] ENTRY_INC_DEC_REG   = 8'h14;
    localparam logic [7:0] ENTRY_TEST          = 8'h15;
    localparam logic [7:0] ENTRY_LEA           = 8'h16;
    localparam logic [7:0] ENTRY_FLAGS_SIMPLE  = 8'h17;
    localparam logic [7:0] ENTRY_STRING_BASIC  = 8'h18;  // phase 3
    localparam logic [7:0] ENTRY_RESET         = 8'hFF;  // startup only

    // ----------------------------------------------------------------
    // SERVICE IDENTIFIERS (Appendix A Section 5)
    // ----------------------------------------------------------------
    localparam logic [7:0] SVC_NULL                 = 8'h00;
    // Fetch
    localparam logic [7:0] FETCH_IMM8               = 8'h01;
    localparam logic [7:0] FETCH_IMM16              = 8'h02;
    localparam logic [7:0] FETCH_IMM32              = 8'h03;
    localparam logic [7:0] FETCH_DISP8              = 8'h04;
    localparam logic [7:0] FETCH_DISP16             = 8'h05;
    localparam logic [7:0] FETCH_DISP32             = 8'h06;
    localparam logic [7:0] DECODE_MODRM_CLASS       = 8'h07;
    // Address
    localparam logic [7:0] EA_CALC_16               = 8'h10;
    localparam logic [7:0] EA_CALC_32               = 8'h11;
    localparam logic [7:0] SEG_DEFAULT_SELECT       = 8'h12;  // phase 2
    localparam logic [7:0] LINEARIZE_OFFSET         = 8'h13;  // phase 2
    // Operand
    localparam logic [7:0] LOAD_RM8                 = 8'h20;
    localparam logic [7:0] LOAD_RM16                = 8'h21;
    localparam logic [7:0] LOAD_RM32                = 8'h22;
    localparam logic [7:0] STORE_RM8                = 8'h23;
    localparam logic [7:0] STORE_RM16               = 8'h24;
    localparam logic [7:0] STORE_RM32               = 8'h25;
    localparam logic [7:0] LOAD_REG_META            = 8'h26;
    localparam logic [7:0] STORE_REG_META           = 8'h27;
    // ALU
    localparam logic [7:0] ALU_ADD8                 = 8'h30;
    localparam logic [7:0] ALU_ADD16                = 8'h31;
    localparam logic [7:0] ALU_ADD32                = 8'h32;
    localparam logic [7:0] ALU_SUB8                 = 8'h33;
    localparam logic [7:0] ALU_SUB16                = 8'h34;
    localparam logic [7:0] ALU_SUB32                = 8'h35;
    localparam logic [7:0] ALU_LOGIC8               = 8'h36;
    localparam logic [7:0] ALU_LOGIC16              = 8'h37;
    localparam logic [7:0] ALU_LOGIC32              = 8'h38;
    localparam logic [7:0] ALU_CMP8                 = 8'h39;
    localparam logic [7:0] ALU_CMP16                = 8'h3A;
    localparam logic [7:0] ALU_CMP32                = 8'h3B;
    localparam logic [7:0] SHIFT_ROT                = 8'h3C;  // phase 2
    localparam logic [7:0] MUL_IMUL                 = 8'h3D;  // phase 2
    localparam logic [7:0] DIV_IDIV                 = 8'h3E;  // phase 2
    localparam logic [7:0] FLAGS_FROM_T3            = 8'h3F;
    // Stack/flow
    localparam logic [7:0] PUSH16                   = 8'h40;
    localparam logic [7:0] PUSH32                   = 8'h41;
    localparam logic [7:0] POP16                    = 8'h42;
    localparam logic [7:0] POP32                    = 8'h43;
    localparam logic [7:0] VALIDATE_NEAR_TRANSFER   = 8'h44;
    localparam logic [7:0] VALIDATE_FAR_TRANSFER    = 8'h45;  // phase 2
    localparam logic [7:0] COMPUTE_REL_TARGET       = 8'h46;
    localparam logic [7:0] CONDITION_EVAL           = 8'h47;
    // Descriptor (phase 2)
    localparam logic [7:0] LOAD_DESCRIPTOR          = 8'h50;
    localparam logic [7:0] CHECK_SEG_ACCESS         = 8'h51;
    localparam logic [7:0] CHECK_DESCRIPTOR_PRESENT = 8'h52;
    localparam logic [7:0] CHECK_CODE_SEG_TRANSFER  = 8'h53;
    localparam logic [7:0] CHECK_STACK_SEG_TRANSFER = 8'h54;
    localparam logic [7:0] LOAD_SEG_VISIBLE         = 8'h55;
    localparam logic [7:0] LOAD_SEG_HIDDEN          = 8'h56;
    localparam logic [7:0] COMMIT_SEG_CACHE         = 8'h57;
    // Interrupt/flow
    localparam logic [7:0] PREPARE_CALL_GATE        = 8'h60;  // phase 3
    localparam logic [7:0] PREPARE_TASK_SWITCH      = 8'h61;  // phase 3
    localparam logic [7:0] INT_ENTER                = 8'h62;
    localparam logic [7:0] IRET_FLOW                = 8'h63;
    localparam logic [7:0] FAR_RETURN_VALIDATE      = 8'h64;  // phase 2
    localparam logic [7:0] FAR_RETURN_OUTER_VALIDATE= 8'h65;  // phase 3
    // Memory (phase 2/3)
    localparam logic [7:0] PAGE_XLATE_FETCH         = 8'h70;
    localparam logic [7:0] PAGE_XLATE_READ          = 8'h71;
    localparam logic [7:0] PAGE_XLATE_WRITE         = 8'h72;
    localparam logic [7:0] MEM_READ8                = 8'h73;
    localparam logic [7:0] MEM_READ16               = 8'h74;
    localparam logic [7:0] MEM_READ32               = 8'h75;
    localparam logic [7:0] MEM_WRITE8               = 8'h76;
    localparam logic [7:0] MEM_WRITE16              = 8'h77;
    localparam logic [7:0] MEM_WRITE32              = 8'h78;
    // Commit
    localparam logic [7:0] COMMIT_GPR               = 8'h80;
    localparam logic [7:0] COMMIT_EIP               = 8'h81;
    localparam logic [7:0] COMMIT_EFLAGS            = 8'h82;
    localparam logic [7:0] COMMIT_SEG               = 8'h83;  // phase 2
    localparam logic [7:0] COMMIT_STACK             = 8'h84;
    localparam logic [7:0] END_INSTRUCTION          = 8'h85;

    // ----------------------------------------------------------------
    // SERVICE RESULT CODES (Appendix A Section 6.2)
    // ----------------------------------------------------------------
    localparam logic [1:0] SR_OK    = 2'h0;
    localparam logic [1:0] SR_WAIT  = 2'h1;
    localparam logic [1:0] SR_FAULT = 2'h2;

    // ----------------------------------------------------------------
    // FAULT CLASS CODES (Appendix A Section 6.1)
    // ----------------------------------------------------------------
    localparam logic [3:0] FC_NONE = 4'h0;
    localparam logic [3:0] FC_GP   = 4'h1;
    localparam logic [3:0] FC_SS   = 4'h2;
    localparam logic [3:0] FC_NP   = 4'h3;
    localparam logic [3:0] FC_PF   = 4'h4;
    localparam logic [3:0] FC_TS   = 4'h5;
    localparam logic [3:0] FC_UD   = 4'h6;
    localparam logic [3:0] FC_DE   = 4'h7;
    localparam logic [3:0] FC_NM   = 4'h8;
    localparam logic [3:0] FC_AC   = 4'h9;
    localparam logic [3:0] FC_INT  = 4'hA;
    localparam logic [3:0] FC_DF   = 4'hB;
    localparam logic [3:0] FC_BR   = 4'hC;
    localparam logic [3:0] FC_OF   = 4'hD;

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
    localparam logic [9:0] CM_STACK_ONLY= CM_STACK | CM_CLR03 | CM_CLR47 | CM_CLRF;

    // ----------------------------------------------------------------
    // STAGE FIELD SELECTORS (Appendix A Section 3.7)
    // ----------------------------------------------------------------
    localparam logic [5:0] STAGE_GPR         = 6'h00;
    localparam logic [5:0] STAGE_EIP         = 6'h01;
    localparam logic [5:0] STAGE_EFLAGS      = 6'h02;
    localparam logic [5:0] STAGE_SEG         = 6'h03;
    localparam logic [5:0] STAGE_STACK       = 6'h04;
    localparam logic [5:0] STAGE_MISC        = 6'h05;
    localparam logic [5:0] STAGE_STACK_ADJ   = 6'h06;
    localparam logic [5:0] STAGE_EFLAGS_MASK = 6'h07;

    // ----------------------------------------------------------------
    // MICROINSTRUCTION REGISTER NAMESPACE (Appendix A Section 7.4)
    // ----------------------------------------------------------------
    localparam logic [3:0] REG_T0      = 4'h0;
    localparam logic [3:0] REG_T1      = 4'h1;
    localparam logic [3:0] REG_T2      = 4'h2;
    localparam logic [3:0] REG_T3      = 4'h3;
    localparam logic [3:0] REG_T4      = 4'h4;
    localparam logic [3:0] REG_T5      = 4'h5;
    localparam logic [3:0] REG_T6      = 4'h6;
    localparam logic [3:0] REG_T7      = 4'h7;
    localparam logic [3:0] REG_S0      = 4'h8;
    localparam logic [3:0] REG_S1      = 4'h9;
    localparam logic [3:0] REG_SR      = 4'hA;
    localparam logic [3:0] REG_FC      = 4'hB;
    localparam logic [3:0] REG_FE      = 4'hC;
    localparam logic [3:0] REG_D0L     = 4'hD;
    localparam logic [3:0] REG_D0H     = 4'hE;
    localparam logic [3:0] REG_SPECIAL = 4'hF;

    // ----------------------------------------------------------------
    // CONDITION CODES (Appendix A Section 7.3)
    // ----------------------------------------------------------------
    localparam logic [3:0] C_ALWAYS = 4'h0;
    localparam logic [3:0] C_OK     = 4'h1;
    localparam logic [3:0] C_WAIT   = 4'h2;
    localparam logic [3:0] C_FAULT  = 4'h3;
    localparam logic [3:0] C_T0Z    = 4'h4;
    localparam logic [3:0] C_T0NZ   = 4'h5;
    localparam logic [3:0] C_W16    = 4'h6;
    localparam logic [3:0] C_W32    = 4'h7;
    localparam logic [3:0] C_REAL   = 4'h8;
    localparam logic [3:0] C_PROT   = 4'h9;
    localparam logic [3:0] C_REP    = 4'hA;
    localparam logic [3:0] C_W8     = 4'hB;
    localparam logic [3:0] C_T3Z    = 4'hC;
    localparam logic [3:0] C_T3NZ   = 4'hD;
    localparam logic [3:0] C_ADDR16 = 4'hE;
    localparam logic [3:0] C_ADDR32 = 4'hF;

    // ----------------------------------------------------------------
    // MICROSEQUENCER STATES
    // ----------------------------------------------------------------
    localparam logic [1:0] MSEQ_FETCH_DECODE  = 2'h0;
    localparam logic [1:0] MSEQ_EXECUTE       = 2'h1;
    localparam logic [1:0] MSEQ_WAIT_SERVICE  = 2'h2;
    localparam logic [1:0] MSEQ_FAULT_HOLD    = 2'h3;

endpackage
