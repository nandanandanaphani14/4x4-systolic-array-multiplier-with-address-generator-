`timescale 1ns / 1ps
//=====================================================================
// wrapper_full_system.sv  --  module accelerator_system_top
//
// ABSTRACTION LEVEL 3 of 3 (the entire design)
//
//   level 1  array_buf_top          skew + array + de-skew
//   level 2  accelerator_top        level 1 + the three SRAMs
//   level 3  accelerator_system_top level 2 + control FSM + AGU  <-- this
//
// Each level lives in its own file and none replaces another.  This one
// instantiates accelerator_top, so the datapath here is byte-for-byte
// the datapath verified by tb_accelerator_top.
//
//---------------------------------------------------------------------
// This is the block diagram, one instance per box
//---------------------------------------------------------------------
//   Host / Testbench Interface   -> the ports of this module
//   Control Unit (FSM)           -> u_controller   (controller.sv)
//   Address Generator            -> u_agu          (agu.sv)
//   Activation / Weight / Output
//     Memory, Skew Buffer,
//     PE Array, De-Skew Buffer,
//     Output Processing          -> u_datapath     (accelerator_top)
//   done / valid (status)        -> busy, done, phase
//
//---------------------------------------------------------------------
// Ownership of the shared SRAM address ports
//---------------------------------------------------------------------
// Every SRAM is single-port, so exactly one master may drive it:
//   busy = 0  the host owns all three ports (preload matrices, read
//             results back)
//   busy = 1  the AGU owns all three ports; host writes are masked off
//             so a stray host strobe cannot corrupt a running job
//
//---------------------------------------------------------------------
// Using it
//---------------------------------------------------------------------
//   1. hold rst_n low, then release
//   2. while !busy: write the activation vectors and weight rows
//      through the host_* ports (word formats in wrapper_mem_arr_buf.sv)
//   3. pulse `start` with num_vectors / act_base / out_base valid
//   4. wait for the `done` pulse
//   5. while !busy: read results through host_o_addr / o_rdata
//=====================================================================
module accelerator_system_top #(
    parameter int ROWS      = 4,
    parameter int COLS      = 4,
    parameter int DATA_W    = 8,
    parameter int PSUM_W    = 32,
    parameter int A_ADDR_W  = 8,
    parameter int W_ADDR_W  = 2,
    parameter int O_ADDR_W  = 8,
    parameter int VEC_CNT_W = 8,
    parameter int A_WORD_W  = ROWS * DATA_W,    //  32
    parameter int W_WORD_W  = COLS * DATA_W,    //  32
    parameter int O_WORD_W  = COLS * PSUM_W,    // 128
    // Datapath depth: activation address issued -> result written.
    // Must match accelerator_top; see wrapper_mem_arr_buf.sv.
    parameter int STORE_LATENCY = 1 + ROWS + COLS - 2 + 1,
    parameter int FLUSH_CYCLES  = ROWS + 2
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ---- host command interface -------------------------------------
    input  logic                  start,
    input  logic [VEC_CNT_W-1:0]  num_vectors,
    input  logic [A_ADDR_W-1:0]   act_base,
    input  logic [O_ADDR_W-1:0]   out_base,

    // ---- host memory access, honoured only while !busy ---------------
    input  logic                  host_a_we,
    input  logic [A_ADDR_W-1:0]   host_a_addr,
    input  logic [A_WORD_W-1:0]   host_a_wdata,
    input  logic                  host_w_we,
    input  logic [W_ADDR_W-1:0]   host_w_addr,
    input  logic [W_WORD_W-1:0]   host_w_wdata,
    // output_mem is written only by the datapath's packing logic, so the
    // host side of it is read-only: an address in, a word out
    input  logic [O_ADDR_W-1:0]   host_o_addr,
    output logic [O_WORD_W-1:0]   o_rdata,

    // ---- status ------------------------------------------------------
    output logic [2:0]            phase,
    output logic                  busy,
    output logic                  done,

    // ---- live result bus, for observation -----------------------------
    output logic signed [PSUM_W-1:0] result [0:COLS-1]
);

    //-----------------------------------------------------------------
    // Control Unit (FSM)
    //-----------------------------------------------------------------
    logic wload_phase, flush_phase, compute_phase, drain_phase;

    controller #(
        .ROWS          (ROWS),
        .COLS          (COLS),
        .VEC_CNT_W     (VEC_CNT_W),
        .FLUSH_CYCLES  (FLUSH_CYCLES),
        .STORE_LATENCY (STORE_LATENCY)
    ) u_controller (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .num_vectors   (num_vectors),
        .wload_phase   (wload_phase),
        .flush_phase   (flush_phase),
        .compute_phase (compute_phase),
        .drain_phase   (drain_phase),
        .phase         (phase),
        .busy          (busy),
        .done          (done)
    );

    //-----------------------------------------------------------------
    // Address Generator
    //-----------------------------------------------------------------
    logic [W_ADDR_W-1:0] agu_w_addr;
    logic                agu_w_rd_en;
    logic                agu_wload;
    logic [A_ADDR_W-1:0] agu_act_addr;
    logic                agu_act_rd_en;
    logic                agu_valid_in;
    logic [O_ADDR_W-1:0] agu_out_addr;
    logic                agu_out_we;

    agu #(
        .ROWS          (ROWS),
        .COLS          (COLS),
        .A_ADDR_W      (A_ADDR_W),
        .W_ADDR_W      (W_ADDR_W),
        .O_ADDR_W      (O_ADDR_W),
        .STORE_LATENCY (STORE_LATENCY)
    ) u_agu (
        .clk           (clk),
        .rst_n         (rst_n),
        .wload_phase   (wload_phase),
        .compute_phase (compute_phase),
        .act_base      (act_base),
        .out_base      (out_base),
        .w_addr        (agu_w_addr),
        .w_rd_en       (agu_w_rd_en),
        .wload         (agu_wload),
        .act_addr      (agu_act_addr),
        .act_rd_en     (agu_act_rd_en),
        .valid_in      (agu_valid_in),
        .out_addr      (agu_out_addr),
        .out_we        (agu_out_we)
    );

    //-----------------------------------------------------------------
    // Port arbitration: AGU while busy, host while idle
    //-----------------------------------------------------------------
    logic                a_we_mux,  w_we_mux,  o_we_mux;
    logic [A_ADDR_W-1:0] a_addr_mux;
    logic [W_ADDR_W-1:0] w_addr_mux;
    logic [O_ADDR_W-1:0] o_addr_mux;
    logic [A_WORD_W-1:0] a_wdata_mux;
    logic [W_WORD_W-1:0] w_wdata_mux;

    always_comb begin : port_arbitration
        if (busy) begin
            a_we_mux    = 1'b0;              // no host writes during a job
            a_addr_mux  = agu_act_addr;
            a_wdata_mux = '0;

            w_we_mux    = 1'b0;
            w_addr_mux  = agu_w_addr;
            w_wdata_mux = '0;

            o_we_mux    = agu_out_we;
            o_addr_mux  = agu_out_addr;
        end
        else begin
            a_we_mux    = host_a_we;
            a_addr_mux  = host_a_addr;
            a_wdata_mux = host_a_wdata;

            w_we_mux    = host_w_we;
            w_addr_mux  = host_w_addr;
            w_wdata_mux = host_w_wdata;

            o_we_mux    = 1'b0;              // host side is read-only
            o_addr_mux  = host_o_addr;
        end
    end

    //-----------------------------------------------------------------
    // Level 2 datapath: memories + skew + array + de-skew + packing.
    // The AGU issues wload / valid_in alongside their addresses and
    // accelerator_top re-times both by one clock internally.
    //-----------------------------------------------------------------
    accelerator_top #(
        .ROWS     (ROWS),
        .COLS     (COLS),
        .DATA_W   (DATA_W),
        .PSUM_W   (PSUM_W),
        .A_ADDR_W (A_ADDR_W),
        .W_ADDR_W (W_ADDR_W),
        .O_ADDR_W (O_ADDR_W)
    ) u_datapath (
        .clk      (clk),
        .rst_n    (rst_n),
        .a_we     (a_we_mux),
        .a_addr   (a_addr_mux),
        .a_wdata  (a_wdata_mux),
        .w_we     (w_we_mux),
        .w_addr   (w_addr_mux),
        .w_wdata  (w_wdata_mux),
        .wload    (agu_wload),
        .valid_in (agu_valid_in),
        .o_we     (o_we_mux),
        .o_addr   (o_addr_mux),
        .o_rdata  (o_rdata),
        .result   (result)
    );

endmodule
