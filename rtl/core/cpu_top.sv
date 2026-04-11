module cpu_top (
    input  logic        clk,
    input  logic        reset_n,
    output logic [31:0] addr,
    input  logic [31:0] din,
    output logic [31:0] dout,
    output logic        rd,
    output logic        wr,
    output logic        io,
    output logic [3:0]  byteen,
    input  logic        ready,
    input  logic        intr,
    input  logic        nmi,
    output logic        inta
);
    // Integration shell only.
endmodule
