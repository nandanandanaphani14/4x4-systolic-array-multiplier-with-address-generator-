`timescale 1ns/1ps
//=====================================================================
// vio_debug_top.sv  --  VIO + ILA debug harness for the 4x4 systolic
//                       accelerator (Method 2, ZedBoard xc7z020clg484-1)
//
// The ONLY external pin is the 100 MHz PL oscillator (Y9).  Every input
// to the accelerator comes from a Vivado VIO core over JTAG, and every
// output goes back to the same VIO dashboard.  An ILA captures the run
// cycle-by-cycle.  accelerator_system_top is instantiated UNMODIFIED.
//
// Why the extra logic?  Two mismatches between "a human clicking a
// dashboard" and "a 100 MHz pipeline":
//
//   1. VIO probe_out is a LEVEL, held until you click again (~ms).  The
//      accelerator wants single-cycle PULSES on start / host_*_we.  If
//      `start` were held high the FSM would relaunch the 17-cycle job
//      thousands of times per click and the ILA would retrigger forever.
//      -> oneshot() converts every 0->1 dashboard edge into ONE clock.
//
//   2. `done` is a single-cycle pulse (10 ns).  VIO samples at human
//      rate and will never see it.  -> done_sticky latches it; it is
//      cleared automatically by the next start pulse.
//
// IP you must generate alongside this file (exact settings in VIO_ILA.pdf):
//   vio_0 : 6 probe_in, 11 probe_out   (widths in the instance below)
//   ila_0 : 10 probes, depth 1024      (widths in the instance below)
//=====================================================================
module vio_debug_top (
    input logic clk                       // 100 MHz PL oscillator, pin Y9
);
    //-----------------------------------------------------------------
    // Power-on reset: hold rst_n low for 65536 clocks (~655 us).
    // The declaration initializer is a synthesizable power-up value on
    // Xilinx 7-series -- FFs configure to a known state at bitstream load.
    //-----------------------------------------------------------------
    logic [15:0] por = '0;
    logic        rst_n;
    always_ff @(posedge clk)
        if (!(&por)) por <= por + 1'b1;
    assign rst_n = &por;

    //-----------------------------------------------------------------
    // VIO probe_out -> levels driven from the Hardware Manager dashboard
    //-----------------------------------------------------------------
    logic        vio_start_lvl;      // probe_out0
    logic [7:0]  vio_num_vectors;    // probe_out1
    logic [7:0]  vio_act_base;       // probe_out2
    logic [7:0]  vio_out_base;       // probe_out3
    logic [31:0] vio_w_wdata;        // probe_out4
    logic [1:0]  vio_w_addr;         // probe_out5
    logic        vio_w_we_lvl;       // probe_out6
    logic [31:0] vio_a_wdata;        // probe_out7
    logic [7:0]  vio_a_addr;         // probe_out8
    logic        vio_a_we_lvl;       // probe_out9
    logic [7:0]  vio_o_addr;         // probe_out10

    //-----------------------------------------------------------------
    // Level -> single-cycle pulse (see header note 1)
    //-----------------------------------------------------------------
    logic start_p, w_we_p, a_we_p;
    oneshot u_os_start (.clk(clk), .rst_n(rst_n), .lvl(vio_start_lvl), .pulse(start_p));
    oneshot u_os_wwe   (.clk(clk), .rst_n(rst_n), .lvl(vio_w_we_lvl),  .pulse(w_we_p));
    oneshot u_os_awe   (.clk(clk), .rst_n(rst_n), .lvl(vio_a_we_lvl),  .pulse(a_we_p));

    //-----------------------------------------------------------------
    // The accelerator (LEVEL 3) -- instantiated unmodified
    //-----------------------------------------------------------------
    logic [127:0]       o_rdata;
    logic [2:0]         phase;
    logic               busy, done;
    logic signed [31:0] result [0:3];

    accelerator_system_top u_acc (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start_p),
        .num_vectors  (vio_num_vectors),
        .act_base     (vio_act_base),
        .out_base     (vio_out_base),
        .host_a_we    (a_we_p),
        .host_a_addr  (vio_a_addr),
        .host_a_wdata (vio_a_wdata),
        .host_w_we    (w_we_p),
        .host_w_addr  (vio_w_addr),
        .host_w_wdata (vio_w_wdata),
        .host_o_addr  (vio_o_addr),
        .o_rdata      (o_rdata),
        .phase        (phase),
        .busy         (busy),
        .done         (done),
        .result       (result)
    );

    //-----------------------------------------------------------------
    // Sticky done + completed-job counter (see header note 2).
    // done_count is the cheapest possible "did it actually run?" probe:
    // if it increments by exactly 1 per start click, the FSM is healthy.
    //-----------------------------------------------------------------
    logic        done_sticky;
    logic [15:0] done_count;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            done_sticky <= 1'b0;
            done_count  <= '0;
        end else begin
            if      (start_p) done_sticky <= 1'b0;   // arm for the new job
            else if (done)    done_sticky <= 1'b1;   // latch the 10 ns pulse
            if (done) done_count <= done_count + 1'b1;
        end
    end

    // `result` is an unpacked array; flatten it so VIO/ILA can probe it.
    logic [127:0] result_flat;
    assign result_flat = {result[3], result[2], result[1], result[0]};

    //-----------------------------------------------------------------
    // VIO  (generate as "vio_0" -- settings in VIO_ILA.pdf section 5)
    //-----------------------------------------------------------------
    vio_0 u_vio (
        .clk        (clk),
        // ---- inputs to the dashboard ----
        .probe_in0  (busy),            // 1
        .probe_in1  (done_sticky),     // 1
        .probe_in2  (phase),           // 3
        .probe_in3  (o_rdata),         // 128
        .probe_in4  (result_flat),     // 128
        .probe_in5  (done_count),      // 16
        // ---- outputs from the dashboard ----
        .probe_out0 (vio_start_lvl),   // 1
        .probe_out1 (vio_num_vectors), // 8   initial value 0x04
        .probe_out2 (vio_act_base),    // 8
        .probe_out3 (vio_out_base),    // 8
        .probe_out4 (vio_w_wdata),     // 32
        .probe_out5 (vio_w_addr),      // 2
        .probe_out6 (vio_w_we_lvl),    // 1
        .probe_out7 (vio_a_wdata),     // 32
        .probe_out8 (vio_a_addr),      // 8
        .probe_out9 (vio_a_we_lvl),    // 1
        .probe_out10(vio_o_addr)       // 8
    );

    //-----------------------------------------------------------------
    // ILA  (generate as "ila_0" -- settings in VIO_ILA.pdf section 6)
    // Trigger on probe0 (start_p) == 1 to catch the whole job: 17 cycles
    // when the weight matrix is loaded, 13 when it is reused.
    // phase encoding: 0 IDLE, 1 WLOAD, 2 COMPUTE, 3 DRAIN, 4 DONE.
    //-----------------------------------------------------------------
    ila_0 u_ila (
        .clk    (clk),
        .probe0 (start_p),      // 1   <- trigger on this
        .probe1 (busy),         // 1
        .probe2 (done),         // 1
        .probe3 (phase),        // 3
        .probe4 (w_we_p),       // 1
        .probe5 (a_we_p),       // 1
        .probe6 (vio_a_addr),   // 8
        .probe7 (o_rdata),      // 128
        .probe8 (result_flat),  // 128
        .probe9 (done_count)    // 16
    );
endmodule


//=====================================================================
// oneshot -- convert a VIO probe_out level into a single-clock pulse on
// its rising edge.  Without this, a held-high `start` relaunches the
// 17-cycle job ~4 million times per second and the ILA never settles.
//=====================================================================
module oneshot (
    input  logic clk,
    input  logic rst_n,
    input  logic lvl,
    output logic pulse
);
    logic lvl_q;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lvl_q <= 1'b0;
            pulse <= 1'b0;
        end else begin
            lvl_q <= lvl;
            pulse <= lvl & ~lvl_q;
        end
    end
endmodule
