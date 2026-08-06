`timescale 1ns / 1ps

module a_mem #(
    parameter DATA_W = 32,
    parameter ADDR_W = 8,
    parameter DEPTH  = (1 << ADDR_W)
)(
    input  logic              clk,
    input  logic              we,
    input  logic [ADDR_W-1:0] addr,
    input  logic [DATA_W-1:0] wdata,
    output logic [DATA_W-1:0] rdata
);
    logic [DATA_W-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we)
            mem[addr] <= wdata;
        rdata <= mem[addr];
    end
endmodule