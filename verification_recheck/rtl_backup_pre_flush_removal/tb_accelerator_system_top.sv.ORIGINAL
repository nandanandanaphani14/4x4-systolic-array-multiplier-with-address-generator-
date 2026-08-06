`timescale 1ns/1ps
//=====================================================================
// tb_accelerator_system_top  --  DUT: accelerator_system_top  LEVEL 3
//
// The testbench acts purely as the Host Interface: it loads matrices,
// pulses start, waits for done, and reads results.  During a run it never
// drives an address or a strobe -- the FSM and AGU do all sequencing.
//
// Sections
//   T1  clean job, golden C = A x W, read output_mem back
//   T2  adversarial: hammer both host write ports with garbage while busy;
//       results bit-identical + out_base isolation preserved
//   T3  act_base points at a second activation block
//   T4  short 3-vector job; neighbouring output word left untouched
//   T5  directed 4x4 (A) x 4x4 (W) = 4x4 (C) matrix multiplication
//=====================================================================
module tb_accelerator_system_top;
  localparam int ROWS=4, COLS=4, DATA_W=8, PSUM_W=32;
  localparam int A_ADDR_W=8, W_ADDR_W=2, O_ADDR_W=8, VEC_CNT_W=8;

  logic clk=0, rst_n;
  logic start; logic [VEC_CNT_W-1:0] num_vectors;
  logic [A_ADDR_W-1:0] act_base; logic [O_ADDR_W-1:0] out_base;
  logic host_a_we; logic [A_ADDR_W-1:0] host_a_addr; logic [ROWS*DATA_W-1:0] host_a_wdata;
  logic host_w_we; logic [W_ADDR_W-1:0] host_w_addr; logic [COLS*DATA_W-1:0] host_w_wdata;
  logic [O_ADDR_W-1:0] host_o_addr; logic [COLS*PSUM_W-1:0] o_rdata;
  logic [2:0] phase; logic busy, done;
  logic signed [PSUM_W-1:0] result [0:COLS-1];
  always #5 clk = ~clk;

  accelerator_system_top #(.ROWS(ROWS), .COLS(COLS), .DATA_W(DATA_W), .PSUM_W(PSUM_W),
    .A_ADDR_W(A_ADDR_W), .W_ADDR_W(W_ADDR_W), .O_ADDR_W(O_ADDR_W), .VEC_CNT_W(VEC_CNT_W)) dut (
    .clk(clk), .rst_n(rst_n), .start(start), .num_vectors(num_vectors),
    .act_base(act_base), .out_base(out_base),
    .host_a_we(host_a_we), .host_a_addr(host_a_addr), .host_a_wdata(host_a_wdata),
    .host_w_we(host_w_we), .host_w_addr(host_w_addr), .host_w_wdata(host_w_wdata),
    .host_o_addr(host_o_addr), .o_rdata(o_rdata),
    .phase(phase), .busy(busy), .done(done), .result(result));

  `include "tb_common.svh"

  // reference models of what the host wrote
  int Wt [0:ROWS-1][0:COLS-1];
  int rA [0:255][0:ROWS-1];

  task automatic host_ww(int addr, int w0, int w1, int w2, int w3);
    @(negedge clk);
    host_w_we=1; host_w_addr=addr[1:0];
    host_w_wdata={8'(w3),8'(w2),8'(w1),8'(w0)};
    Wt[addr][0]=w0; Wt[addr][1]=w1; Wt[addr][2]=w2; Wt[addr][3]=w3;
    @(negedge clk); host_w_we=0;
  endtask

  task automatic host_wa(int addr, int a0, int a1, int a2, int a3);
    @(negedge clk);
    host_a_we=1; host_a_addr=addr[7:0];
    host_a_wdata={8'(a3),8'(a2),8'(a1),8'(a0)};
    rA[addr][0]=a0; rA[addr][1]=a1; rA[addr][2]=a2; rA[addr][3]=a3;
    @(negedge clk); host_a_we=0;
  endtask

  function automatic int goldenC(int a_addr, int c);
    int s; s=0;
    for (int r=0;r<ROWS;r++) s += rA[a_addr][r]*Wt[r][c];
    return s;
  endfunction

  task automatic run_job(int nv, int ab, int ob);
    @(negedge clk); start=1; num_vectors=nv[VEC_CNT_W-1:0];
    act_base=ab[A_ADDR_W-1:0]; out_base=ob[O_ADDR_W-1:0];
    @(negedge clk); start=0;
    while (!done) @(negedge clk);
    @(negedge clk);                     // settle into IDLE
  endtask

  task automatic rd_out(int addr, output logic [COLS*PSUM_W-1:0] d);
    @(negedge clk); host_o_addr=addr[7:0];
    @(posedge clk); @(negedge clk); #1; d=o_rdata;
  endtask

  // continuously slam garbage into both host write ports (used during a run)
  task automatic hammer_start();
    host_w_we=1; host_w_addr=0; host_w_wdata=32'hDEAD_BEEF;
    host_a_we=1; host_a_addr=0; host_a_wdata=32'hBAAD_F00D;
  endtask
  task automatic hammer_stop();
    host_w_we=0; host_a_we=0;
  endtask

  logic [COLS*PSUM_W-1:0] rd, rd2;
  int i, c, r, mismatch;

  initial begin
    TB = "tb_accelerator_system_top";
    $display("=====================================================================");
    $display(" %s  --  DUT: accelerator_system_top (LEVEL 3)", TB);
    $display("=====================================================================");
    $display(" Host pulses start / waits done / reads results; FSM+AGU sequence all.");
    $display("");
    $display(" TEST PLAN");
    $display("   T1  clean job, golden C = A x W, read output_mem back");
    $display("   T2  adversarial host writes while busy -> results unchanged");
    $display("   T3  act_base selects a second activation block");
    $display("   T4  short 3-vector job; neighbour output word untouched");
    $display("   T5  directed 4x4 (A) x 4x4 (W) = 4x4 (C) matrix multiply");
    $display("=====================================================================");

    start=0; num_vectors=0; act_base=0; out_base=0;
    host_a_we=0; host_w_we=0; host_a_addr=0; host_w_addr=0; host_o_addr=0;
    host_a_wdata=0; host_w_wdata=0;
    rst_n=0; repeat(3) @(negedge clk); #1 rst_n=1;

    // ---------------- T1 ----------------
    sec_begin("T1", "clean job, golden read-back");
    for (r=0;r<ROWS;r++) host_ww(r, $signed(8'($urandom)), $signed(8'($urandom)),
                                     $signed(8'($urandom)), $signed(8'($urandom)));
    for (i=0;i<6;i++) host_wa(i, $signed(8'($urandom)), $signed(8'($urandom)),
                                 $signed(8'($urandom)), $signed(8'($urandom)));
    run_job(6, 0, 8'h20);
    $display("    job done in phase sequence; reading output_mem[0x20..]:");
    for (i=0;i<6;i++) begin
      rd_out(8'h20+i, rd);
      $display("    out[0x%02h] = %6d %6d %6d %6d (exp %6d %6d %6d %6d)", 8'h20+i,
               $signed(rd[0*32+:32]), $signed(rd[1*32+:32]), $signed(rd[2*32+:32]), $signed(rd[3*32+:32]),
               goldenC(i,0), goldenC(i,1), goldenC(i,2), goldenC(i,3));
      for (c=0;c<COLS;c++) ck($sformatf("T1_out[%0d][%0d]", i, c), $signed(rd[c*32+:32]), goldenC(i,c));
    end
    sec_end();

    // ---------------- T2 ----------------
    sec_begin("T2", "adversarial host writes while busy");
    // capture run-1 outputs already in memory; now run identical job with hammering
    fork
      run_job(6, 0, 8'h40);         // out to a fresh block
      begin
        // hammer only while busy
        @(negedge clk);
        while (!busy) @(negedge clk);
        while (busy) begin hammer_start(); @(negedge clk); end
        hammer_stop();
      end
    join
    mismatch=0;
    for (i=0;i<6;i++) begin
      rd_out(8'h40+i, rd);
      for (c=0;c<COLS;c++) begin
        ck($sformatf("T2_out[%0d][%0d]", i, c), $signed(rd[c*32+:32]), goldenC(i,c));
        if ($signed(rd[c*32+:32]) !== goldenC(i,c)) mismatch++;
      end
    end
    $display("    hammered 0xDEADBEEF/0xBAADF00D into both write ports all job: mismatches=%0d", mismatch);
    // out_base isolation: T1 block at 0x20 must be unchanged
    for (i=0;i<6;i++) begin
      rd_out(8'h20+i, rd);
      for (c=0;c<COLS;c++) ck($sformatf("T2_iso[%0d][%0d]", i, c), $signed(rd[c*32+:32]), goldenC(i,c));
    end
    $display("    earlier output block (0x20) is still intact -> out_base isolation holds");
    sec_end();

    // ---------------- T3 ----------------
    sec_begin("T3", "act_base selects a second activation block");
    for (i=0;i<4;i++) host_wa(8'h80+i, $signed(8'($urandom)), $signed(8'($urandom)),
                                        $signed(8'($urandom)), $signed(8'($urandom)));
    run_job(4, 8'h80, 8'h60);
    for (i=0;i<4;i++) begin
      rd_out(8'h60+i, rd);
      for (c=0;c<COLS;c++) ck($sformatf("T3_out[%0d][%0d]", i, c), $signed(rd[c*32+:32]), goldenC(8'h80+i,c));
    end
    $display("    act_base=0x80 produced that block's product into out_base=0x60");
    sec_end();

    // ---------------- T4 ----------------
    sec_begin("T4", "short 3-vector job; neighbour word untouched");
    // sample the word at 0x73 BEFORE the run
    rd_out(8'h73, rd);
    for (i=0;i<3;i++) host_wa(8'h10+i, $signed(8'($urandom)), $signed(8'($urandom)),
                                        $signed(8'($urandom)), $signed(8'($urandom)));
    run_job(3, 8'h10, 8'h70);
    for (i=0;i<3;i++) begin
      rd_out(8'h70+i, rd2);
      for (c=0;c<COLS;c++) ck($sformatf("T4_out[%0d][%0d]", i, c), $signed(rd2[c*32+:32]), goldenC(8'h10+i,c));
    end
    rd_out(8'h73, rd2);
    ck("T4_neighbour_untouched", rd2, rd);
    $display("    exactly 3 words written (0x70..0x72); 0x73 unchanged before/after");
    sec_end();

    // ---------------- T5 : directed 4x4 x 4x4 ----------------
    sec_begin("T5", "directed 4x4 (A) x 4x4 (W) = 4x4 (C)");
    // W (row r, col c)
    host_ww(0,  1,  2,  3,  4);
    host_ww(1,  5,  6,  7,  8);
    host_ww(2,  9, 10, 11, 12);
    host_ww(3, 13, 14, 15, 16);
    // A (row i = activation vector i, index r) stored at a_mem[0xC0+i]
    host_wa(8'hC0, 1, 0, 0, 0);
    host_wa(8'hC1, 0, 1, 0, 0);
    host_wa(8'hC2, 0, 0, 1, 0);
    host_wa(8'hC3, 1, 1, 1, 1);
    $display("    A (4x4):                    W (4x4):");
    $display("      [ 1 0 0 0 ]                 [  1  2  3  4 ]");
    $display("      [ 0 1 0 0 ]                 [  5  6  7  8 ]");
    $display("      [ 0 0 1 0 ]                 [  9 10 11 12 ]");
    $display("      [ 1 1 1 1 ]                 [ 13 14 15 16 ]");
    run_job(4, 8'hC0, 8'hA0);
    $display("    C = A x W (read from output_mem[0xA0..0xA3]):");
    for (i=0;i<4;i++) begin
      rd_out(8'hA0+i, rd);
      $display("      C[%0d] = %4d %4d %4d %4d   (exp %4d %4d %4d %4d)", i,
               $signed(rd[0*32+:32]), $signed(rd[1*32+:32]), $signed(rd[2*32+:32]), $signed(rd[3*32+:32]),
               goldenC(8'hC0+i,0), goldenC(8'hC0+i,1), goldenC(8'hC0+i,2), goldenC(8'hC0+i,3));
      for (c=0;c<COLS;c++) ck($sformatf("T5_C[%0d][%0d]", i, c), $signed(rd[c*32+:32]), goldenC(8'hC0+i,c));
    end
    $display("    row 0..2 reproduce W rows 0..2; row 3 = column sums (28 32 36 40).");
    sec_end();

    // ---------------- T6 : general 4x4 x 4x4 ----------------
    sec_begin("T6", "general 4x4 (A) x 4x4 (W) = 4x4 (C)");
    host_ww(0,  1,  2, -1,  3);
    host_ww(1,  0, -2,  4,  1);
    host_ww(2,  5,  1,  2, -3);
    host_ww(3, -1,  3,  0,  2);
    host_wa(8'hD0,  2, -1,  3,  0);
    host_wa(8'hD1,  1,  4, -2,  5);
    host_wa(8'hD2, -3,  2,  1,  1);
    host_wa(8'hD3,  0,  1,  2, -4);
    $display("    A (4x4):                    W (4x4):");
    $display("      [  2 -1  3  0 ]             [  1  2 -1  3 ]");
    $display("      [  1  4 -2  5 ]             [  0 -2  4  1 ]");
    $display("      [ -3  2  1  1 ]             [  5  1  2 -3 ]");
    $display("      [  0  1  2 -4 ]             [ -1  3  0  2 ]");
    run_job(4, 8'hD0, 8'hB0);
    $display("    C = A x W (read from output_mem[0xB0..0xB3]):");
    for (i=0;i<4;i++) begin
      rd_out(8'hB0+i, rd);
      $display("      C[%0d] = %4d %4d %4d %4d   (exp %4d %4d %4d %4d)", i,
               $signed(rd[0*32+:32]), $signed(rd[1*32+:32]), $signed(rd[2*32+:32]), $signed(rd[3*32+:32]),
               goldenC(8'hD0+i,0), goldenC(8'hD0+i,1), goldenC(8'hD0+i,2), goldenC(8'hD0+i,3));
      for (c=0;c<COLS;c++) ck($sformatf("T6_C[%0d][%0d]", i, c), $signed(rd[c*32+:32]), goldenC(8'hD0+i,c));
    end
    $display("    expected C = [17 9 0 -4][-14 7 11 23][1 -6 13 -8][14 -12 8 -13]");
    sec_end();

    report_summary();
    $finish;
  end
endmodule
