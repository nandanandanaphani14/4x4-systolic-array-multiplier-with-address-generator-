`timescale 1ns / 1ps
//=====================================================================
// agu.sv  --  module agu  (Address Generation Unit)
//
// The "Address Generator" block of the architecture diagram.  It holds
// no policy: the controller says which phase we are in, and the AGU
// produces the three memory addresses plus the datapath strobes that
// belong to that phase.
//
//---------------------------------------------------------------------
// Weight address  (w_addr, during wload_phase)
//---------------------------------------------------------------------
//   Counts DOWN: ROWS-1, ROWS-2, ... 0.  While wload=1 the array's
//   vertical bus is a downward shift register, so the row driven first
//   travels furthest and lands in the BOTTOM array row.  Counting down
//   therefore puts weight row r into array row r.
//
//---------------------------------------------------------------------
// Activation address  (act_addr, during compute_phase)
//---------------------------------------------------------------------
//   Counts UP from act_base, one vector per clock.
//
//---------------------------------------------------------------------
// Output address  (out_addr / out_we)
//---------------------------------------------------------------------
//   A result cannot be written when its activation address is issued -
//   it is still travelling through the SRAM, skew buffer, PE column,
//   de-skew buffer and packing logic.  Rather than recompute that
//   timing, the AGU pushes {enable, address} into a STORE_LATENCY-deep
//   shift register, so the write strobe is structurally guaranteed to
//   arrive with the data it belongs to.  Changing the datapath depth
//   only means changing STORE_LATENCY.
//
//   wload and valid_in are issued in the SAME cycle as their address;
//   accelerator_top re-times them by one clock to cover SRAM latency.
//=====================================================================
module agu #(
    parameter int ROWS          = 4,
    parameter int COLS          = 4,
    parameter int A_ADDR_W      = 8,
    parameter int W_ADDR_W      = 2,
    parameter int O_ADDR_W      = 8,
    parameter int STORE_LATENCY = 1 + ROWS + COLS - 2 + 1
)(
    input  logic                clk,
    input  logic                rst_n,

    // ---- phase enables from the controller --------------------------
    input  logic                wload_phase,
    input  logic                compute_phase,

    // ---- programmable base addresses --------------------------------
    input  logic [A_ADDR_W-1:0] act_base,
    input  logic [O_ADDR_W-1:0] out_base,

    // ---- weight memory ----------------------------------------------
    output logic [W_ADDR_W-1:0] w_addr,
    output logic                w_rd_en,
    output logic                wload,

    // ---- activation memory ------------------------------------------
    output logic [A_ADDR_W-1:0] act_addr,
    output logic                act_rd_en,
    output logic                valid_in,

    // ---- output memory ----------------------------------------------
    output logic [O_ADDR_W-1:0] out_addr,
    output logic                out_we
);

    //-----------------------------------------------------------------
    // Weight row counter: ROWS-1 down to 0, reloaded whenever idle so
    // the very first wload cycle already presents ROWS-1
    //-----------------------------------------------------------------
    logic [W_ADDR_W-1:0] w_cnt;

    always_ff @(posedge clk) begin
        if (!rst_n)           w_cnt <= W_ADDR_W'(ROWS-1);
        else if (!wload_phase) w_cnt <= W_ADDR_W'(ROWS-1);
        else                   w_cnt <= w_cnt - 1'b1;
    end

    assign w_addr  = w_cnt;
    assign w_rd_en = wload_phase;
    assign wload   = wload_phase;

    //-----------------------------------------------------------------
    // Activation vector counter: 0,1,2,... while computing
    //-----------------------------------------------------------------
    logic [A_ADDR_W-1:0] act_cnt;

    always_ff @(posedge clk) begin
        if (!rst_n)              act_cnt <= '0;
        else if (!compute_phase) act_cnt <= '0;
        else                     act_cnt <= act_cnt + 1'b1;
    end

    assign act_addr  = act_base + act_cnt;
    assign act_rd_en = compute_phase;
    assign valid_in  = compute_phase;

    //-----------------------------------------------------------------
    // Write strobe / address, delayed to meet the result at the output
    // SRAM.  Stage i holds what was issued i+1 cycles ago.
    //-----------------------------------------------------------------
    logic                out_we_pipe   [0:STORE_LATENCY-1];
    logic [O_ADDR_W-1:0] out_addr_pipe [0:STORE_LATENCY-1];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < STORE_LATENCY; i++) begin
                out_we_pipe[i]   <= 1'b0;
                out_addr_pipe[i] <= '0;
            end
        end
        else begin
            out_we_pipe[0]   <= compute_phase;
            out_addr_pipe[0] <= out_base + O_ADDR_W'(act_cnt);
            for (int i = 1; i < STORE_LATENCY; i++) begin
                out_we_pipe[i]   <= out_we_pipe[i-1];
                out_addr_pipe[i] <= out_addr_pipe[i-1];
            end
        end
    end

    assign out_we   = out_we_pipe[STORE_LATENCY-1];
    assign out_addr = out_addr_pipe[STORE_LATENCY-1];

endmodule
