`timescale 1ns/1ps
//=====================================================================
// tb_controller  --  DUT: controller (controller.sv)
//
// Phase lengths are measured by COUNTING clocks with each enable high,
// not by inspecting the state encoding.  Expected lengths:
//   WLOAD=ROWS=4  FLUSH=ROWS+2=6  COMPUTE=num_vectors  DRAIN=8  DONE=1
//   total job = num_vectors + 19
// Also: phase enables mutually exclusive; start ignored while busy;
// done a single-cycle pulse with busy already low; num_vectors=0 no hang.
//=====================================================================
module tb_controller;
  localparam int ROWS=4, COLS=4, VEC_CNT_W=8;
  localparam int FLUSH=ROWS+2, DRAIN=1+ROWS+COLS-2+1;   // 6, 8
  logic clk=0, rst_n, start;
  logic [VEC_CNT_W-1:0] num_vectors;
  logic wload_phase, flush_phase, compute_phase, drain_phase;
  logic [2:0] phase; logic busy, done;
  always #5 clk = ~clk;

  controller #(.ROWS(ROWS), .COLS(COLS), .VEC_CNT_W(VEC_CNT_W)) dut (
    .clk(clk), .rst_n(rst_n), .start(start), .num_vectors(num_vectors),
    .wload_phase(wload_phase), .flush_phase(flush_phase),
    .compute_phase(compute_phase), .drain_phase(drain_phase),
    .phase(phase), .busy(busy), .done(done));

  `include "tb_common.svh"

  int onehot_viol = 0, busy_at_done = 0;

  // Run one job, counting each phase; enforce mutual exclusion + done rules.
  task automatic run_job(int nv, output int w, output int f, output int cm,
                         output int d, output int total);
    int nhot;
    @(negedge clk); start=1; num_vectors=nv[VEC_CNT_W-1:0];
    @(negedge clk); start=0;             // start high across exactly one posedge
    w=0; f=0; cm=0; d=0; total=0;
    forever begin
      #1;
      nhot = wload_phase + flush_phase + compute_phase + drain_phase;
      if (nhot > 1) onehot_viol++;
      if (wload_phase)   w++;
      if (flush_phase)   f++;
      if (compute_phase) cm++;
      if (drain_phase)   d++;
      if (busy || done)  total++;
      if (done) begin
        if (busy) busy_at_done++;         // busy must be low when done fires
        break;
      end
      @(negedge clk);
    end
    // one more cycle: done must have dropped (single-cycle pulse)
    @(negedge clk); #1;
    if (done) errors++;                   // would mean done held > 1 cycle
  endtask

  int w,f,cm,d,total;
  int nv_list [0:6];

  initial begin
    TB = "tb_controller";
    nv_list[0]=0; nv_list[1]=1; nv_list[2]=3; nv_list[3]=4;
    nv_list[4]=6; nv_list[5]=8; nv_list[6]=16;
    $display("=====================================================================");
    $display(" %s  --  DUT: controller (controller.sv)", TB);
    $display("=====================================================================");
    $display(" Expected: WLOAD=%0d FLUSH=%0d COMPUTE=nv DRAIN=%0d DONE=1  total=nv+19",
             ROWS, FLUSH, DRAIN);
    $display("");
    $display(" TEST PLAN");
    $display("   T1  phase lengths + total job length for nv in {0,1,3,4,6,8,16}");
    $display("   T2  start ignored while busy (hammered mid-job)");
    $display("   T3  reset mid-job returns to IDLE; fresh job still works");
    $display("=====================================================================");

    start=0; num_vectors=0; rst_n=0; repeat(3) @(negedge clk); #1 rst_n=1;

    sec_begin("T1", "phase + total lengths, nv in {0,1,3,4,6,8,16}");
    $display("      nv | WLOAD FLUSH COMPUTE DRAIN | total | expect total");
    $display("     ----+--------------------------+-------+-------------");
    for (int k=0;k<7;k++) begin
      run_job(nv_list[k], w, f, cm, d, total);
      $display("     %3d |   %2d    %2d     %3d     %2d  |  %3d  |     %3d",
               nv_list[k], w, f, cm, d, total, nv_list[k]+19);
      ck($sformatf("wload_nv%0d",   nv_list[k]), w,  ROWS);
      ck($sformatf("flush_nv%0d",   nv_list[k]), f,  FLUSH);
      ck($sformatf("compute_nv%0d", nv_list[k]), cm, nv_list[k]);
      ck($sformatf("drain_nv%0d",   nv_list[k]), d,  DRAIN);
      ck($sformatf("total_nv%0d",   nv_list[k]), total, nv_list[k]+19);
    end
    ck("phase_enables_onehot", onehot_viol, 0);
    ck("busy_low_at_done",     busy_at_done, 0);
    $display("    num_vectors=0 reached DONE in 19 cycles - no hang.");
    sec_end();

    sec_begin("T2", "start ignored while busy");
    begin
      int w2,f2,cm2,d2,t2;
      // launch a job, then hammer start every cycle during it
      fork
        run_job(6, w2, f2, cm2, d2, t2);
        begin
          repeat (25) begin @(negedge clk); if (busy) start=1; end
          start=0;
        end
      join
      ck("busy_start_wload",   w2,  ROWS);
      ck("busy_start_flush",   f2,  FLUSH);
      ck("busy_start_compute", cm2, 6);
      ck("busy_start_total",   t2,  6+19);
      $display("    hammered start throughout a 6-vector job: lengths unchanged, no restart");
    end
    sec_end();

    sec_begin("T3", "reset mid-job then a fresh job");
    @(negedge clk); start=1; num_vectors=8; @(negedge clk); start=0;
    repeat (5) @(negedge clk);                 // partway through
    #1 rst_n=0; @(negedge clk); #1;
    ck("reset_to_idle", phase, 3'd0);
    ck("reset_not_busy", busy, 1'b0);
    $display("    asserted reset mid-job: phase=%0d busy=%0b", phase, busy);
    @(negedge clk); #1 rst_n=1;
    run_job(3, w, f, cm, d, total);
    ck("post_reset_total", total, 3+19);
    $display("    fresh 3-vector job after reset: total=%0d (expect %0d)", total, 3+19);
    sec_end();

    report_summary();
    $finish;
  end
endmodule
