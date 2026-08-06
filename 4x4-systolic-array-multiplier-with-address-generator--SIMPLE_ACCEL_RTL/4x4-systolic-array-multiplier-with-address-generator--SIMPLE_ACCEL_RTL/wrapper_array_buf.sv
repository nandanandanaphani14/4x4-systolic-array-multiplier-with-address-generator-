`timescale 1ns / 1ps
//=====================================================================
// wrapper_array_buf.sv  --  module array_buf_top
//
// ABSTRACTION LEVEL 1 of 3 (compute fabric only)
//
//   level 1  array_buf_top          skew + array + de-skew      <-- this file
//   level 2  accelerator_top        level 1 + the three SRAMs
//   level 3  accelerator_system_top level 2 + control FSM + AGU
//
// Each level lives in its own file and none replaces another.
//
// This level closes the datapath from a dense activation vector to an
// aligned result vector.  There is no memory and no sequencing: the
// caller presents one dense vector per clock and reads `result` back a
// fixed number of clocks later.
//
//---------------------------------------------------------------------
// Latency
//---------------------------------------------------------------------
//   A dense vector consumed at posedge n appears on `result` immediately
//   after posedge  n + ROWS + COLS - 2   (= n + 6 for the 4x4 array):
//       ROWS-1  register stages down the PE column
//       + c     horizontal travel to column c
//       + COLS-1-c  de-skew delay, which cancels the +c
//   The exported localparam RESULT_LATENCY states this for testbenches.
//
//---------------------------------------------------------------------
// Weight loading
//---------------------------------------------------------------------
//   While wload=1 the vertical bus is a downward shift register, so the
//   FIRST weight row presented on psum_in_top lands in the BOTTOM array
//   row.  Drive W[ROWS-1] first and W[0] last.
//=====================================================================
module array_buf_top #(
    parameter int ROWS   = 4,
    parameter int COLS   = 4,
    parameter int DATA_W = 8,      // must be 8: systolic_array ports are fixed
    parameter int PSUM_W = 32      // must be 32: systolic_array ports are fixed
)(
    input  logic clk,
    input  logic rst_n,

    // Phase control: 1 = shift weights down the array, 0 = compute
    input  logic wload,

    // West edge - one dense (un-skewed) activation vector per clock
    input  logic signed [DATA_W-1:0] dense_a_in     [0:ROWS-1],
    input  logic                     dense_valid_in [0:ROWS-1],

    // North edge - weight row during wload, zeros during compute
    input  logic signed [PSUM_W-1:0] psum_in_top    [0:COLS-1],

    // South edge, after de-skew - one aligned result vector per clock
    output logic signed [PSUM_W-1:0] result         [0:COLS-1],

    // South edge, before de-skew - exposed for observability only
    output logic signed [PSUM_W-1:0] psum_raw       [0:COLS-1]
);

    // Cycles from "dense vector consumed" to "result valid"
    localparam int RESULT_LATENCY = ROWS + COLS - 2;

    logic signed [DATA_W-1:0] skew_a [0:ROWS-1];
    logic                     skew_v [0:ROWS-1];

    //-----------------------------------------------------------------
    // West edge: turn the dense vector into a diagonal wavefront
    //-----------------------------------------------------------------
    input_skew_buffer #(
        .ROWS  (ROWS),
        .WIDTH (DATA_W)
    ) u_input_skew (
        .clk            (clk),
        .rst_n          (rst_n),
        .dense_a_in     (dense_a_in),
        .dense_valid_in (dense_valid_in),
        .skew_a_out     (skew_a),
        .skew_valid_out (skew_v)
    );

    //-----------------------------------------------------------------
    // The 4x4 weight-stationary PE fabric
    //-----------------------------------------------------------------
    systolic_array #(
        .ROWS (ROWS),
        .COLS (COLS)
    ) u_array (
        .clk             (clk),
        .rst_n           (rst_n),
        .wload           (wload),
        .a_in_left       (skew_a),
        .valid_in_left   (skew_v),
        .psum_in_top     (psum_in_top),
        .psum_out_bottom (psum_raw)
    );

    //-----------------------------------------------------------------
    // South edge: undo the column-to-column staircase
    //-----------------------------------------------------------------
    output_deskew_buffer #(
        .COLS  (COLS),
        .WIDTH (PSUM_W)
    ) u_output_deskew (
        .clk         (clk),
        .rst_n       (rst_n),
        .psum_in     (psum_raw),
        .aligned_out (result)
    );

endmodule
