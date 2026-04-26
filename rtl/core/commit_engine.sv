// Keystone86 / Aegis
// rtl/core/commit_engine.sv
//
// Current active role:
//   Commit behavior required by the delivered Rung 2 direct-JMP path, the
//   Rung 3 near CALL/RET stack-visible path, and the Rung 4 Jcc architectural
//   flag/EIP visibility path.
//
// Active commit contract:
//   - Redirect becomes architecturally visible only at ENDI.
//   - CM_FLUSHQ must generate a committed flush pulse.
//   - For active redirect paths, flush_addr must be the committed target.
//   - Stack-visible CALL/RET effects are applied only from staged stack_engine
//     records at ENDI.
//   - ENDI launch must be able to consume LIVE pending EIP/target inputs
//     in the same cycle, not only staged *_r copies.
//   - EFLAGS are exposed as committed architectural state for Rung 4
//     CONDITION_EVAL; the condition service reads them but does not modify them.
//   - Rung 5 Pass 2 INT_ENTER stages a bounded real-mode interrupt-entry
//     record. CM_INT applies the staged EIP/CS/FLAGS/ESP values and serializes
//     the 16-bit IP/CS/FLAGS frame bytes at ENDI. Rung 5 Pass 3 IRET_FLOW uses
//     the same bounded interrupt-control record without a frame write, applying
//     the popped EIP/CS/FLAGS/ESP only at ENDI/CM_IRET.
//
// Scope note:
//   This file may contain structural surfaces that later rungs can build on.
//   Current verification claims only the bounded Rung 2 direct-JMP behavior
//   the bounded Rung 3 near CALL/RET behavior, and the bounded Rung 4 Jcc
//   EIP/redirect visibility behavior proven by the active regression.

module commit_engine (
    input  logic        clk,
    input  logic        reset_n,

    // --- ENDI interface (from microsequencer) ---
    input  logic        endi_req,
    input  logic [9:0]  endi_mask,
    output logic        endi_done,

    // --- Fault interface (from microsequencer) ---
    input  logic        raise_req,
    input  logic [3:0]  raise_fc,
    input  logic [31:0] raise_fe,

    // --- Pending GPR commit (unused in active Rung 2/3 paths) ---
    input  logic        pc_gpr_en,
    input  logic [2:0]  pc_gpr_idx,
    input  logic [31:0] pc_gpr_val,

    // --- Pending fall-through EIP commit ---
    input  logic        pc_eip_en,
    input  logic [31:0] pc_eip_val,

    // --- Pending target EIP commit (JMP/CALL-direct target) ---
    input  logic        pc_target_en,
    input  logic [31:0] pc_target_val,

    // --- Pending stack commit staged by stack_engine ---
    input  logic        pc_stack_en,
    input  logic        pc_stack_write_en,
    input  logic [31:0] pc_stack_addr,
    input  logic [31:0] pc_stack_data,
    input  logic [31:0] pc_stack_esp_val,
    input  logic        pc_stack_adj_en,
    input  logic [31:0] pc_stack_adj_val,

    // --- Pending bounded interrupt-control record staged by interrupt_engine ---
    input  logic        pc_int_en,
    input  logic [31:0] pc_int_eip,
    input  logic [15:0] pc_int_cs,
    input  logic [31:0] pc_int_eflags,
    input  logic [31:0] pc_int_esp,
    input  logic        pc_int_frame_write_en,
    input  logic [31:0] pc_int_frame_addr,
    input  logic [47:0] pc_int_frame_bytes,

    // --- Architectural state outputs ---
    output logic [31:0] eip,
    output logic [31:0] esp,
    output logic [31:0] eflags,
    output logic [15:0] cs,
    output logic        mode_prot,
    output logic        cs_d_bit,

    // --- Prefetch queue flush ---
    output logic        flush_req,
    output logic [31:0] flush_addr,

    // --- Stack write bus ---
    output logic        stk_wr_en,
    output logic [31:0] stk_wr_addr,
    output logic [31:0] stk_wr_data,
    output logic [3:0]  stk_wr_byteen,
    input  logic        stk_wr_done,

    // --- Fault state export ---
    output logic        fault_pending,
    output logic [3:0]  fault_class,
    output logic [31:0] fault_error
);

    localparam logic [31:0] RESET_FETCH_ADDR = 32'hFFFFFFF0;
    localparam logic [31:0] RESET_ESP        = 32'h000FFFF0;

    // Architectural registers
    logic [31:0] eip_r;
    logic [31:0] esp_r;
    logic [31:0] eflags_r;
    logic [15:0] cs_r;
    logic        fault_pending_r;
    logic [3:0]  fault_class_r;
    logic [31:0] fault_error_r;

    // Pending commit staging. Rung 2 actively uses the EIP/target path;
    // Rung 3 also uses the stack record path staged by stack_engine.
    logic        pc_eip_en_r;
    logic [31:0] pc_eip_val_r;
    logic        pc_target_en_r;
    logic [31:0] pc_target_val_r;
    logic        pc_stack_en_r;
    logic        pc_stack_write_en_r;
    logic [31:0] pc_stack_addr_r;
    logic [31:0] pc_stack_data_r;
    logic [31:0] pc_stack_esp_val_r;
    logic        pc_stack_adj_en_r;
    logic [31:0] pc_stack_adj_val_r;
    logic        pc_int_en_r;
    logic [31:0] pc_int_eip_r;
    logic [15:0] pc_int_cs_r;
    logic [31:0] pc_int_eflags_r;
    logic [31:0] pc_int_esp_r;
    logic        pc_int_frame_write_en_r;
    logic [31:0] pc_int_frame_addr_r;
    logic [47:0] pc_int_frame_bytes_r;

    // ENDI rising-edge detection
    logic        endi_req_d;
    logic        reset_flush_done;
    logic        stk_wr_wait_r;
    logic        int_frame_write_r;
    logic [2:0]  int_frame_idx_r;

    // Effective live-or-staged values for ENDI launch. This lets the
    // commit boundary consume the active redirect handoff even if the
    // value is still live on the launch cycle.
    logic        eff_pc_eip_en;
    logic [31:0] eff_pc_eip_val;
    logic        eff_pc_target_en;
    logic [31:0] eff_pc_target_val;
    logic        eff_pc_stack_en;
    logic        eff_pc_stack_write_en;
    logic [31:0] eff_pc_stack_addr;
    logic [31:0] eff_pc_stack_data;
    logic [31:0] eff_pc_stack_esp_val;
    logic        eff_pc_stack_adj_en;
    logic [31:0] eff_pc_stack_adj_val;
    logic        eff_pc_int_en;
    logic [31:0] eff_pc_int_eip;
    logic [15:0] eff_pc_int_cs;
    logic [31:0] eff_pc_int_eflags;
    logic [31:0] eff_pc_int_esp;
    logic        eff_pc_int_frame_write_en;
    logic [31:0] eff_pc_int_frame_addr;
    logic [47:0] eff_pc_int_frame_bytes;

    assign eip           = eip_r;
    assign esp           = esp_r;
    assign eflags        = eflags_r;
    assign cs            = cs_r;
    assign mode_prot     = 1'b0;
    assign cs_d_bit      = 1'b0;
    assign fault_pending = fault_pending_r;
    assign fault_class   = fault_class_r;
    assign fault_error   = fault_error_r;

    assign eff_pc_eip_en       = pc_eip_en | pc_eip_en_r;
    assign eff_pc_eip_val      = pc_eip_en ? pc_eip_val : pc_eip_val_r;
    assign eff_pc_target_en    = pc_target_en | pc_target_en_r;
    assign eff_pc_target_val   = pc_target_en ? pc_target_val : pc_target_val_r;
    assign eff_pc_stack_en       = pc_stack_en | pc_stack_en_r;
    assign eff_pc_stack_write_en = pc_stack_en ? pc_stack_write_en : pc_stack_write_en_r;
    assign eff_pc_stack_addr     = pc_stack_en ? pc_stack_addr : pc_stack_addr_r;
    assign eff_pc_stack_data     = pc_stack_en ? pc_stack_data : pc_stack_data_r;
    assign eff_pc_stack_esp_val  = pc_stack_en ? pc_stack_esp_val : pc_stack_esp_val_r;
    assign eff_pc_stack_adj_en   = pc_stack_adj_en | pc_stack_adj_en_r;
    assign eff_pc_stack_adj_val  = pc_stack_adj_en ? pc_stack_adj_val : pc_stack_adj_val_r;
    assign eff_pc_int_en          = pc_int_en | pc_int_en_r;
    assign eff_pc_int_eip         = pc_int_en ? pc_int_eip : pc_int_eip_r;
    assign eff_pc_int_cs          = pc_int_en ? pc_int_cs : pc_int_cs_r;
    assign eff_pc_int_eflags      = pc_int_en ? pc_int_eflags : pc_int_eflags_r;
    assign eff_pc_int_esp         = pc_int_en ? pc_int_esp : pc_int_esp_r;
    assign eff_pc_int_frame_write_en = pc_int_en ? pc_int_frame_write_en :
                                       pc_int_frame_write_en_r;
    assign eff_pc_int_frame_addr  = pc_int_en ? pc_int_frame_addr : pc_int_frame_addr_r;
    assign eff_pc_int_frame_bytes = pc_int_en ? pc_int_frame_bytes : pc_int_frame_bytes_r;

    function automatic logic [7:0] frame_byte(
        input logic [47:0] frame,
        input logic [2:0]  idx
    );
        case (idx)
            3'd0: return frame[7:0];
            3'd1: return frame[15:8];
            3'd2: return frame[23:16];
            3'd3: return frame[31:24];
            3'd4: return frame[39:32];
            3'd5: return frame[47:40];
            default: return 8'h0;
        endcase
    endfunction

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            eip_r             <= RESET_FETCH_ADDR;
            esp_r             <= RESET_ESP;
            eflags_r          <= 32'h00000002;
            cs_r              <= 16'h0000;
            fault_pending_r   <= 1'b0;
            fault_class_r     <= 4'h0;
            fault_error_r     <= 32'h0;

            pc_eip_en_r       <= 1'b0;
            pc_eip_val_r      <= 32'h0;
            pc_target_en_r    <= 1'b0;
            pc_target_val_r   <= 32'h0;
            pc_stack_en_r       <= 1'b0;
            pc_stack_write_en_r <= 1'b0;
            pc_stack_addr_r     <= 32'h0;
            pc_stack_data_r     <= 32'h0;
            pc_stack_esp_val_r  <= 32'h0;
            pc_stack_adj_en_r   <= 1'b0;
            pc_stack_adj_val_r  <= 32'h0;
            pc_int_en_r          <= 1'b0;
            pc_int_eip_r         <= 32'h0;
            pc_int_cs_r          <= 16'h0;
            pc_int_eflags_r      <= 32'h0;
            pc_int_esp_r         <= 32'h0;
            pc_int_frame_write_en_r <= 1'b0;
            pc_int_frame_addr_r  <= 32'h0;
            pc_int_frame_bytes_r <= 48'h0;

            endi_req_d        <= 1'b0;
            reset_flush_done  <= 1'b0;
            stk_wr_wait_r     <= 1'b0;
            int_frame_write_r  <= 1'b0;
            int_frame_idx_r    <= 3'h0;

            flush_req         <= 1'b0;
            flush_addr        <= RESET_FETCH_ADDR;
            endi_done         <= 1'b0;

            stk_wr_en         <= 1'b0;
            stk_wr_addr       <= 32'h0;
            stk_wr_data       <= 32'h0;
            stk_wr_byteen     <= 4'b0000;
        end else begin
            // Default pulse clears
            flush_req  <= 1'b0;
            endi_done  <= 1'b0;
            stk_wr_en  <= 1'b0;
            stk_wr_byteen <= 4'b0000;

            endi_req_d <= endi_req;

            // Initial authoritative reset flush
            if (!reset_flush_done) begin
                flush_req        <= 1'b1;
                flush_addr       <= RESET_FETCH_ADDR;
                reset_flush_done <= 1'b1;
            end

            if (raise_req) begin
                fault_pending_r <= 1'b1;
                fault_class_r   <= raise_fc;
                fault_error_r   <= raise_fe;
            end

            // Stage pending values for later visibility / fallback use.
            if (pc_eip_en) begin
                pc_eip_en_r  <= 1'b1;
                pc_eip_val_r <= pc_eip_val;
            end

            if (pc_target_en) begin
                pc_target_en_r  <= 1'b1;
                pc_target_val_r <= pc_target_val;
            end

            if (pc_stack_en) begin
                pc_stack_en_r       <= 1'b1;
                pc_stack_write_en_r <= pc_stack_write_en;
                pc_stack_addr_r     <= pc_stack_addr;
                pc_stack_data_r     <= pc_stack_data;
                pc_stack_esp_val_r  <= pc_stack_esp_val;
            end

            if (pc_stack_adj_en) begin
                pc_stack_adj_en_r  <= 1'b1;
                pc_stack_adj_val_r <= pc_stack_adj_val;
            end

            if (pc_int_en) begin
                pc_int_en_r          <= 1'b1;
                pc_int_eip_r         <= pc_int_eip;
                pc_int_cs_r          <= pc_int_cs;
                pc_int_eflags_r      <= pc_int_eflags;
                pc_int_esp_r         <= pc_int_esp;
                pc_int_frame_write_en_r <= pc_int_frame_write_en;
                pc_int_frame_addr_r  <= pc_int_frame_addr;
                pc_int_frame_bytes_r <= pc_int_frame_bytes;
            end

            if (stk_wr_wait_r) begin
                if (stk_wr_done) begin
                    if (int_frame_write_r && (int_frame_idx_r != 3'd5)) begin
                        int_frame_idx_r <= int_frame_idx_r + 3'd1;
                        stk_wr_en       <= 1'b1;
                        stk_wr_addr     <= pc_int_frame_addr_r +
                                           {29'h0, int_frame_idx_r + 3'd1};
                        stk_wr_data     <= {24'h0, frame_byte(pc_int_frame_bytes_r,
                                                              int_frame_idx_r + 3'd1)};
                        stk_wr_byteen   <= 4'b0001;
                    end else begin
                        stk_wr_wait_r     <= 1'b0;
                        int_frame_write_r <= 1'b0;
                        int_frame_idx_r   <= 3'h0;
                        pc_int_en_r       <= 1'b0;
                        pc_int_eip_r      <= 32'h0;
                        pc_int_cs_r       <= 16'h0;
                        pc_int_eflags_r   <= 32'h0;
                        pc_int_esp_r      <= 32'h0;
                        pc_int_frame_write_en_r <= 1'b0;
                        pc_int_frame_addr_r  <= 32'h0;
                        pc_int_frame_bytes_r <= 48'h0;
                        endi_done         <= 1'b1;
                    end
                end
            end
            // ENDI launch edge only
            else if (endi_req && !endi_req_d) begin
                // Bounded Rung 5 #UD delivery commit. SUB_FAULT_HANDLER uses
                // CM_FAULT_END so fault state remains available while
                // INT_ENTER stages the vector-derived handler record. Commit
                // does not choose the vector or classify the fault; it only
                // publishes the already staged interrupt record at ENDI.
                if ((endi_mask == CM_FAULT_END) && eff_pc_int_en &&
                    fault_pending_r) begin
                    eip_r        <= eff_pc_int_eip;
                    cs_r         <= eff_pc_int_cs;
                    eflags_r     <= eff_pc_int_eflags;
                    esp_r        <= eff_pc_int_esp;
                    flush_req    <= 1'b1;
                    flush_addr   <= eff_pc_int_eip;

                    pc_int_en_r          <= 1'b1;
                    pc_int_eip_r         <= eff_pc_int_eip;
                    pc_int_cs_r          <= eff_pc_int_cs;
                    pc_int_eflags_r      <= eff_pc_int_eflags;
                    pc_int_esp_r         <= eff_pc_int_esp;
                    pc_int_frame_write_en_r <= eff_pc_int_frame_write_en;
                    pc_int_frame_addr_r  <= eff_pc_int_frame_addr;
                    pc_int_frame_bytes_r <= eff_pc_int_frame_bytes;

                    if (eff_pc_int_frame_write_en) begin
                        stk_wr_en       <= 1'b1;
                        stk_wr_addr     <= eff_pc_int_frame_addr;
                        stk_wr_data     <= {24'h0, frame_byte(eff_pc_int_frame_bytes, 3'd0)};
                        stk_wr_byteen   <= 4'b0001;
                        stk_wr_wait_r   <= 1'b1;
                        int_frame_write_r <= 1'b1;
                        int_frame_idx_r <= 3'd0;
                    end else begin
                        pc_int_en_r       <= 1'b0;
                        pc_int_eip_r      <= 32'h0;
                        pc_int_cs_r       <= 16'h0;
                        pc_int_eflags_r   <= 32'h0;
                        pc_int_esp_r      <= 32'h0;
                        pc_int_frame_write_en_r <= 1'b0;
                        pc_int_frame_addr_r  <= 32'h0;
                        pc_int_frame_bytes_r <= 48'h0;
                        endi_done         <= 1'b1;
                    end

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_stack_en_r       <= 1'b0;
                    pc_stack_write_en_r <= 1'b0;
                    pc_stack_addr_r     <= 32'h0;
                    pc_stack_data_r     <= 32'h0;
                    pc_stack_esp_val_r  <= 32'h0;
                    pc_stack_adj_en_r   <= 1'b0;
                    pc_stack_adj_val_r  <= 32'h0;

                    fault_pending_r <= 1'b0;
                    fault_class_r   <= 4'h0;
                    fault_error_r   <= 32'h0;
                end
                // Bounded Rung 5 interrupt-control commit. The service stages
                // a generic record; this block only applies fields selected by
                // CM_INT/CM_IRET. INT_ENTER also requests six frame-byte writes,
                // while IRET_FLOW commits only the popped state.
                else if (endi_mask[4] && endi_mask[3] && endi_mask[2] &&
                    endi_mask[1] && eff_pc_int_en && !fault_pending_r) begin
                    eip_r        <= eff_pc_int_eip;
                    cs_r         <= eff_pc_int_cs;
                    eflags_r     <= eff_pc_int_eflags;
                    esp_r        <= eff_pc_int_esp;
                    flush_req    <= 1'b1;
                    flush_addr   <= eff_pc_int_eip;

                    pc_int_en_r          <= 1'b1;
                    pc_int_eip_r         <= eff_pc_int_eip;
                    pc_int_cs_r          <= eff_pc_int_cs;
                    pc_int_eflags_r      <= eff_pc_int_eflags;
                    pc_int_esp_r         <= eff_pc_int_esp;
                    pc_int_frame_write_en_r <= eff_pc_int_frame_write_en;
                    pc_int_frame_addr_r  <= eff_pc_int_frame_addr;
                    pc_int_frame_bytes_r <= eff_pc_int_frame_bytes;

                    if (eff_pc_int_frame_write_en) begin
                        stk_wr_en       <= 1'b1;
                        stk_wr_addr     <= eff_pc_int_frame_addr;
                        stk_wr_data     <= {24'h0, frame_byte(eff_pc_int_frame_bytes, 3'd0)};
                        stk_wr_byteen   <= 4'b0001;
                        stk_wr_wait_r   <= 1'b1;
                        int_frame_write_r <= 1'b1;
                        int_frame_idx_r <= 3'd0;
                    end else begin
                        pc_int_en_r       <= 1'b0;
                        pc_int_eip_r      <= 32'h0;
                        pc_int_cs_r       <= 16'h0;
                        pc_int_eflags_r   <= 32'h0;
                        pc_int_esp_r      <= 32'h0;
                        pc_int_frame_write_en_r <= 1'b0;
                        pc_int_frame_addr_r  <= 32'h0;
                        pc_int_frame_bytes_r <= 48'h0;
                        endi_done         <= 1'b1;
                    end

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_stack_en_r       <= 1'b0;
                    pc_stack_write_en_r <= 1'b0;
                    pc_stack_addr_r     <= 32'h0;
                    pc_stack_data_r     <= 32'h0;
                    pc_stack_esp_val_r  <= 32'h0;
                    pc_stack_adj_en_r   <= 1'b0;
                    pc_stack_adj_val_r  <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end
                end
                // Active Rung 3 stack commit path. Stack services stage the
                // pending record; commit_engine only makes it visible at ENDI.
                else if (endi_mask[4] && !fault_pending_r) begin
                    if (eff_pc_stack_en) begin
                        if (eff_pc_stack_write_en) begin
                            stk_wr_en   <= 1'b1;
                            stk_wr_addr <= eff_pc_stack_addr;
                            stk_wr_data <= eff_pc_stack_data;
                            stk_wr_byteen <= 4'b1111;
                            stk_wr_wait_r <= 1'b1;
                        end

                        esp_r <= eff_pc_stack_esp_val +
                                 (eff_pc_stack_adj_en ? eff_pc_stack_adj_val : 32'h0);
                    end

                    if (eff_pc_target_en) begin
                        eip_r      <= eff_pc_target_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_target_val;
                    end else if (eff_pc_eip_en) begin
                        eip_r      <= eff_pc_eip_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_eip_val;
                    end

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_stack_en_r       <= 1'b0;
                    pc_stack_write_en_r <= 1'b0;
                    pc_stack_addr_r     <= 32'h0;
                    pc_stack_data_r     <= 32'h0;
                    pc_stack_esp_val_r  <= 32'h0;
                    pc_stack_adj_en_r   <= 1'b0;
                    pc_stack_adj_val_r  <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= !(eff_pc_stack_en && eff_pc_stack_write_en);
                end
                // Active Rung 2 JMP / redirect commit path
                else if (endi_mask[9] && !endi_mask[4] && !fault_pending_r) begin
                    if (eff_pc_target_en) begin
                        eip_r      <= eff_pc_target_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_target_val;
                    end else if (eff_pc_eip_en) begin
                        eip_r      <= eff_pc_eip_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_eip_val;
                    end else begin
                        // CM_FLUSHQ still means the queue must restart.
                        flush_req  <= 1'b1;
                        flush_addr <= eip_r;
                    end

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_stack_en_r       <= 1'b0;
                    pc_stack_write_en_r <= 1'b0;
                    pc_stack_addr_r     <= 32'h0;
                    pc_stack_data_r     <= 32'h0;
                    pc_stack_esp_val_r  <= 32'h0;
                    pc_stack_adj_en_r   <= 1'b0;
                    pc_stack_adj_val_r  <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
                // Sequential EIP commit
                else if (endi_mask[1] && !endi_mask[9] && !endi_mask[4]
                         && eff_pc_eip_en && !fault_pending_r) begin
                    eip_r <= eff_pc_eip_val;

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_stack_en_r       <= 1'b0;
                    pc_stack_write_en_r <= 1'b0;
                    pc_stack_addr_r     <= 32'h0;
                    pc_stack_data_r     <= 32'h0;
                    pc_stack_esp_val_r  <= 32'h0;
                    pc_stack_adj_en_r   <= 1'b0;
                    pc_stack_adj_val_r  <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
                // Clear / fault-only path
                else begin
                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_stack_en_r       <= 1'b0;
                    pc_stack_write_en_r <= 1'b0;
                    pc_stack_addr_r     <= 32'h0;
                    pc_stack_data_r     <= 32'h0;
                    pc_stack_esp_val_r  <= 32'h0;
                    pc_stack_adj_en_r   <= 1'b0;
                    pc_stack_adj_val_r  <= 32'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
            end
        end
    end

endmodule
