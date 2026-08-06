`timescale 1ns / 1ps
//=====================================================================
// wrapper_mem_arr_buf.sv  --  module accelerator_top
//
// ABSTRACTION LEVEL 2 of 3 (datapath + memories, host sequenced)
//
//   level 1  array_buf_top          skew + array + de-skew
//   level 2  accelerator_top        level 1 + the three SRAMs   <-- this file
//   level 3  accelerator_system_top level 2 + control FSM + AGU
//
// Each level lives in its own file and none replaces another.  This one
// instantiates array_buf_top rather than re-wiring the fabric, so the
// two levels can never drift apart.
//
//---------------------------------------------------------------------
// Word formats
//---------------------------------------------------------------------
//   a_mem      32 bits = 4 x int8, lane r  = activation for array ROW r
//   weight_mem 32 bits = 4 x int8, lane c  = weight for array COLUMN c;
//                                  address r holds weight row r
//   output_mem 128 bits = 4 x int32, lane c = result of array COLUMN c
//
//---------------------------------------------------------------------
// Control alignment rule
//---------------------------------------------------------------------
//   Every SRAM here has one clock of read latency.  To keep the host
//   interface simple, `wload` and `valid_in` are issued in the SAME
//   cycle as the address they belong to, and this wrapper re-times them
//   internally by one clock so they line up with the returning data.
//
//---------------------------------------------------------------------
// Latency
//---------------------------------------------------------------------
//   a_addr driven for posedge n  ->  `result` valid just after posedge
//   n + 1 + (ROWS+COLS-2) = n + 7  for the 4x4 array.
//   To capture that word, o_we must be high at posedge n + 8.
//   Exported as RESULT_LATENCY / STORE_LATENCY for testbenches.
//
//   Each SRAM has a single address port shared by reads and writes, so
//   a write cycle is not a read cycle.  Reads return pre-write data on
//   an address collision.
//=====================================================================
module accelerator_top #(
    parameter int ROWS     = 4,
    parameter int COLS     = 4,
    parameter int DATA_W   = 8,
    parameter int PSUM_W   = 32,
    parameter int A_ADDR_W = 8,
    parameter int W_ADDR_W = 2,
    parameter int O_ADDR_W = 8,
    parameter int A_WORD_W = ROWS * DATA_W,    //  32
    parameter int W_WORD_W = COLS * DATA_W,    //  32
    parameter int O_WORD_W = COLS * PSUM_W     // 128
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---- activation memory port (shared read/write address) ---------
    input  logic                  a_we,
    input  logic [A_ADDR_W-1:0]   a_addr,
    input  logic [A_WORD_W-1:0]   a_wdata,

    // ---- weight memory port (shared read/write address) -------------
    input  logic                  w_we,
    input  logic [W_ADDR_W-1:0]   w_addr,
    input  logic [W_WORD_W-1:0]   w_wdata,

    // ---- phase control, issued alongside the address ----------------
    input  logic                  wload,
    input  logic                  valid_in,

    // ---- output memory port (shared read/write address) -------------
    input  logic                  o_we,
    input  logic [O_ADDR_W-1:0]   o_addr,
    output logic [O_WORD_W-1:0]   o_rdata,

    // ---- live result bus, ahead of the output SRAM ------------------
    output logic signed [PSUM_W-1:0] result [0:COLS-1]
);

    localparam int RESULT_LATENCY = 1 + ROWS + COLS - 2;   // addr -> result
    localparam int STORE_LATENCY  = RESULT_LATENCY + 1;    // addr -> o_we

    logic [A_WORD_W-1:0] a_rdata;
    logic [W_WORD_W-1:0] w_rdata;
    logic [O_WORD_W-1:0] o_wdata;

    //-----------------------------------------------------------------
    // Re-time the control strobes to match SRAM read latency
    //-----------------------------------------------------------------
    logic wload_q;
    logic valid_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wload_q <= 1'b0;
            valid_q <= 1'b0;
        end
        else begin
            wload_q <= wload;
            valid_q <= valid_in;
        end
    end

    //-----------------------------------------------------------------
    // Memories
    //-----------------------------------------------------------------
    a_mem #(
        .DATA_W (A_WORD_W),
        .ADDR_W (A_ADDR_W)
    ) u_a_mem (
        .clk   (clk),
        .we    (a_we),
        .addr  (a_addr),
        .wdata (a_wdata),
        .rdata (a_rdata)
    );

    weight_mem #(
        .DATA_W (W_WORD_W),
        .ADDR_W (W_ADDR_W)
    ) u_weight_mem (
        .clk   (clk),
        .we    (w_we),
        .addr  (w_addr),
        .wdata (w_wdata),
        .rdata (w_rdata)
    );

    output_mem #(
        .DATA_W (O_WORD_W),
        .ADDR_W (O_ADDR_W)
    ) u_output_mem (
        .clk   (clk),
        .we    (o_we),
        .addr  (o_addr),
        .wdata (o_wdata),
        .rdata (o_rdata)
    );

    //-----------------------------------------------------------------
    // a_mem word -> one int8 per array row
    //-----------------------------------------------------------------
    logic signed [DATA_W-1:0] dense_a [0:ROWS-1];
    logic                     dense_v [0:ROWS-1];

    always_comb begin : unpack_activations
        for (int r = 0; r < ROWS; r++) begin
            dense_a[r] = signed'(a_rdata[r*DATA_W +: DATA_W]);
            dense_v[r] = valid_q;
        end
    end

    //-----------------------------------------------------------------
    // weight_mem word -> north edge during wload, zeros during compute
    //-----------------------------------------------------------------
    logic signed [PSUM_W-1:0] psum_top [0:COLS-1];

    always_comb begin : drive_array_top
        for (int c = 0; c < COLS; c++)
            psum_top[c] = wload_q ? PSUM_W'(signed'(w_rdata[c*DATA_W +: DATA_W]))
                                  : '0;
    end

    //-----------------------------------------------------------------
    // Level 1 compute fabric
    //-----------------------------------------------------------------
    logic signed [PSUM_W-1:0] psum_raw [0:COLS-1];

    array_buf_top #(
        .ROWS   (ROWS),
        .COLS   (COLS),
        .DATA_W (DATA_W),
        .PSUM_W (PSUM_W)
    ) u_fabric (
        .clk            (clk),
        .rst_n          (rst_n),
        .wload          (wload_q),
        .dense_a_in     (dense_a),
        .dense_valid_in (dense_v),
        .psum_in_top    (psum_top),
        .result         (result),
        .psum_raw       (psum_raw)
    );

    //-----------------------------------------------------------------
    // Output processing: pack the COLS aligned results into one SRAM
    // word, lane c = column c
    //-----------------------------------------------------------------
    always_comb begin : pack_output
        for (int c = 0; c < COLS; c++)
            o_wdata[c*PSUM_W +: PSUM_W] = result[c];
    end

endmodule
