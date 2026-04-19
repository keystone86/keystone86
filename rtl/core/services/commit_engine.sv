// Keystone86 / Aegis
// rtl/core/commit_engine.sv
//
// Rung 2/3 commit behavior:
//   - Commit-visible redirect happens only at ENDI.
//   - CM_FLUSHQ always generates a flush pulse.
//   - Once ENDI consumes a pending handoff, that handoff must not be
//     restaged during the active ENDI cycle or the immediately following cycle.

module commit_engine (
    input  logic        clk,
    input  logic        reset_n,

    input  logic        endi_req,
    input  logic [9:0]  endi_mask,
    output logic        endi_done,

    input  logic        raise_req,
    input  logic [3:0]  raise_fc,
    input  logic [31:0] raise_fe,

    input  logic        pc_gpr_en,
    input  logic [2:0]  pc_gpr_idx,
    input  logic [31:0] pc_gpr_val,

    input  logic        pc_eip_en,
    input  logic [31:0] pc_eip_val,

    input  logic        pc_target_en,
    input  logic [31:0] pc_target_val,

    input  logic        pc_ret_addr_en,
    input  logic [31:0] pc_ret_addr_val,

    input  logic        pc_ret_imm_en,
    input  logic [15:0] pc_ret_imm_val,

    input  logic [31:0] indirect_call_target,
    input  logic        indirect_call_target_valid,

    output logic [31:0] eip,
    output logic [31:0] esp,
    output logic        mode_prot,
    output logic        cs_d_bit,

    output logic        flush_req,
    output logic [31:0] flush_addr,

    output logic        stk_wr_en,
    output logic [31:0] stk_wr_addr,
    output logic [31:0] stk_wr_data,

    output logic        stk_rd_req,
    output logic [31:0] stk_rd_addr,
    input  logic [31:0] stk_rd_data,
    input  logic        stk_rd_ready,

    output logic        fault_pending,
    output logic [3:0]  fault_class,
    output logic [31:0] fault_error
);

    localparam logic [31:0] RESET_FETCH_ADDR = 32'hFFFFFFF0;
    localparam logic [31:0] RESET_ESP        = 32'h000FFFF0;

    logic [31:0] eip_r;
    logic [31:0] esp_r;
    logic        fault_pending_r;
    logic [3:0]  fault_class_r;
    logic [31:0] fault_error_r;

    logic        pc_eip_en_r;
    logic [31:0] pc_eip_val_r;
    logic        pc_target_en_r;
    logic [31:0] pc_target_val_r;
    logic        pc_ret_addr_en_r;
    logic [31:0] pc_ret_addr_val_r;
    logic        pc_ret_imm_en_r;
    logic [15:0] pc_ret_imm_val_r;

    logic        ret_wait_r;
    logic        ret_imm_en_saved;
    logic [15:0] ret_imm_val_saved;

    logic        endi_req_d;
    logic        reset_flush_done;

    logic        eff_pc_eip_en;
    logic [31:0] eff_pc_eip_val;
    logic        eff_pc_target_en;
    logic [31:0] eff_pc_target_val;
    logic        eff_pc_ret_addr_en;
    logic [31:0] eff_pc_ret_addr_val;
    logic        eff_pc_ret_imm_en;
    logic [15:0] eff_pc_ret_imm_val;

    logic        endi_launch_pulse;
    logic        endi_busy_or_cleanup;

    assign eip           = eip_r;
    assign esp           = esp_r;
    assign mode_prot     = 1'b0;
    assign cs_d_bit      = 1'b0;
    assign fault_pending = fault_pending_r;
    assign fault_class   = fault_class_r;
    assign fault_error   = fault_error_r;

    assign eff_pc_eip_en       = pc_eip_en | pc_eip_en_r;
    assign eff_pc_eip_val      = pc_eip_en ? pc_eip_val : pc_eip_val_r;
    assign eff_pc_target_en    = pc_target_en | pc_target_en_r;
    assign eff_pc_target_val   = pc_target_en ? pc_target_val : pc_target_val_r;
    assign eff_pc_ret_addr_en  = pc_ret_addr_en | pc_ret_addr_en_r;
    assign eff_pc_ret_addr_val = pc_ret_addr_en ? pc_ret_addr_val : pc_ret_addr_val_r;
    assign eff_pc_ret_imm_en   = pc_ret_imm_en | pc_ret_imm_en_r;
    assign eff_pc_ret_imm_val  = pc_ret_imm_en ? pc_ret_imm_val : pc_ret_imm_val_r;

    assign endi_launch_pulse   = endi_req && !endi_req_d;

    // Suppress restaging while ENDI is active and for one cleanup cycle after.
    assign endi_busy_or_cleanup = endi_req | endi_req_d;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            eip_r             <= RESET_FETCH_ADDR;
            esp_r             <= RESET_ESP;
            fault_pending_r   <= 1'b0;
            fault_class_r     <= 4'h0;
            fault_error_r     <= 32'h0;

            pc_eip_en_r       <= 1'b0;
            pc_eip_val_r      <= 32'h0;
            pc_target_en_r    <= 1'b0;
            pc_target_val_r   <= 32'h0;
            pc_ret_addr_en_r  <= 1'b0;
            pc_ret_addr_val_r <= 32'h0;
            pc_ret_imm_en_r   <= 1'b0;
            pc_ret_imm_val_r  <= 16'h0;

            ret_wait_r        <= 1'b0;
            ret_imm_en_saved  <= 1'b0;
            ret_imm_val_saved <= 16'h0;

            endi_req_d        <= 1'b0;
            reset_flush_done  <= 1'b0;

            flush_req         <= 1'b0;
            flush_addr        <= RESET_FETCH_ADDR;
            endi_done         <= 1'b0;

            stk_wr_en         <= 1'b0;
            stk_wr_addr       <= 32'h0;
            stk_wr_data       <= 32'h0;
            stk_rd_req        <= 1'b0;
            stk_rd_addr       <= 32'h0;
        end else begin
            flush_req  <= 1'b0;
            endi_done  <= 1'b0;
            stk_wr_en  <= 1'b0;
            stk_rd_req <= 1'b0;

            endi_req_d <= endi_req;

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

            // Only stage when ENDI is neither active nor in the immediate
            // cleanup cycle after retire.
            if (!endi_busy_or_cleanup) begin
                if (pc_eip_en) begin
                    pc_eip_en_r  <= 1'b1;
                    pc_eip_val_r <= pc_eip_val;
                end
                if (pc_target_en) begin
                    pc_target_en_r  <= 1'b1;
                    pc_target_val_r <= pc_target_val;
                end
                if (pc_ret_addr_en) begin
                    pc_ret_addr_en_r  <= 1'b1;
                    pc_ret_addr_val_r <= pc_ret_addr_val;
                end
                if (pc_ret_imm_en) begin
                    pc_ret_imm_en_r  <= 1'b1;
                    pc_ret_imm_val_r <= pc_ret_imm_val;
                end
            end

            if (ret_wait_r) begin
                if (stk_rd_ready) begin
                    ret_wait_r        <= 1'b0;
                    eip_r             <= stk_rd_data;
                    esp_r             <= esp_r + 32'h4 +
                                         (ret_imm_en_saved ? {16'h0, ret_imm_val_saved} : 32'h0);
                    flush_req         <= 1'b1;
                    flush_addr        <= stk_rd_data;

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_ret_addr_en_r  <= 1'b0;
                    pc_ret_addr_val_r <= 32'h0;
                    pc_ret_imm_en_r   <= 1'b0;
                    pc_ret_imm_val_r  <= 16'h0;
                    ret_imm_en_saved  <= 1'b0;
                    ret_imm_val_saved <= 16'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end
            end else if (endi_launch_pulse) begin
                if (endi_mask[4] && !fault_pending_r) begin
                    if (eff_pc_ret_addr_en) begin
                        stk_wr_en   <= 1'b1;
                        stk_wr_addr <= esp_r - 32'h4;
                        stk_wr_data <= eff_pc_ret_addr_val;
                        esp_r       <= esp_r - 32'h4;

                        if (eff_pc_target_en) begin
                            eip_r      <= eff_pc_target_val;
                            flush_req  <= 1'b1;
                            flush_addr <= eff_pc_target_val;
                        end else if (indirect_call_target_valid) begin
                            eip_r      <= indirect_call_target;
                            flush_req  <= 1'b1;
                            flush_addr <= indirect_call_target;
                        end else begin
                            eip_r      <= eff_pc_eip_val;
                            flush_req  <= 1'b1;
                            flush_addr <= eff_pc_eip_val;
                        end

                        pc_eip_en_r       <= 1'b0;
                        pc_eip_val_r      <= 32'h0;
                        pc_target_en_r    <= 1'b0;
                        pc_target_val_r   <= 32'h0;
                        pc_ret_addr_en_r  <= 1'b0;
                        pc_ret_addr_val_r <= 32'h0;
                        pc_ret_imm_en_r   <= 1'b0;
                        pc_ret_imm_val_r  <= 16'h0;

                        if (endi_mask[8]) begin
                            fault_pending_r <= 1'b0;
                            fault_class_r   <= 4'h0;
                            fault_error_r   <= 32'h0;
                        end

                        endi_done <= 1'b1;
                    end else begin
                        stk_rd_req        <= 1'b1;
                        stk_rd_addr       <= esp_r;
                        ret_wait_r        <= 1'b1;
                        ret_imm_en_saved  <= eff_pc_ret_imm_en;
                        ret_imm_val_saved <= eff_pc_ret_imm_val;
                    end
                end else if (endi_mask[9] && !endi_mask[4] && !fault_pending_r) begin
                    if (eff_pc_target_en) begin
                        eip_r      <= eff_pc_target_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_target_val;
                    end else if (eff_pc_eip_en) begin
                        eip_r      <= eff_pc_eip_val;
                        flush_req  <= 1'b1;
                        flush_addr <= eff_pc_eip_val;
                    end else begin
                        flush_req  <= 1'b1;
                        flush_addr <= eip_r;
                    end

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_ret_addr_en_r  <= 1'b0;
                    pc_ret_addr_val_r <= 32'h0;
                    pc_ret_imm_en_r   <= 1'b0;
                    pc_ret_imm_val_r  <= 16'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end else if (endi_mask[1] && !endi_mask[9] && !endi_mask[4]
                             && eff_pc_eip_en && !fault_pending_r) begin
                    eip_r <= eff_pc_eip_val;

                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_ret_addr_en_r  <= 1'b0;
                    pc_ret_addr_val_r <= 32'h0;
                    pc_ret_imm_en_r   <= 1'b0;
                    pc_ret_imm_val_r  <= 16'h0;

                    if (endi_mask[8]) begin
                        fault_pending_r <= 1'b0;
                        fault_class_r   <= 4'h0;
                        fault_error_r   <= 32'h0;
                    end

                    endi_done <= 1'b1;
                end else begin
                    pc_eip_en_r       <= 1'b0;
                    pc_eip_val_r      <= 32'h0;
                    pc_target_en_r    <= 1'b0;
                    pc_target_val_r   <= 32'h0;
                    pc_ret_addr_en_r  <= 1'b0;
                    pc_ret_addr_val_r <= 32'h0;
                    pc_ret_imm_en_r   <= 1'b0;
                    pc_ret_imm_val_r  <= 16'h0;

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