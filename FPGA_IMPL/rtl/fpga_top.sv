`timescale 1ns/1ps
//=====================================================================
// fpga_top.sv  --  ZedBoard console harness for the 4x4 systolic accelerator
//
// Peripheral-free bring-up: enter a 4x4 int8 weight matrix and a 4x4 int8
// activation matrix one BYTE at a time on the 8 slide switches, run the
// accelerator at full clock speed, latch the 4x4 int32 result, and read it
// back one byte at a time on the 8 LEDs.  No external connectors are used.
//
// It instantiates accelerator_system_top UNMODIFIED and only adds:
//   * button debouncers (5 push-buttons -> single-cycle pulses)
//   * a loader FSM that drives the host_* memory ports while !busy
//   * start control + done detection
//   * a result-capture reader and an LED display multiplexer
//
// I/O (see zedboard_accelerator.xdc)
//   clk            100 MHz on-board oscillator (GCLK, pin Y9)
//   sw[7:0]        one signed int8 byte of data (also the read index in READ)
//   btnc  COMMIT   latch sw into the current field and advance
//   btnu  START    kick off the accelerator job
//   btnd  RESET    return to the start of the load sequence
//   btnl / btnr    (reserved for future navigation)
//   led[7:0]       echoes sw while loading; shows the selected result byte in READ
//
// Demo shape (fixed): NVEC = 4  ->  a full 4x4 x 4x4 = 4x4 matrix multiply.
//   16 weight bytes (row-major W[r][c]) then 16 activation bytes (A[i][r]).
//   Result buffer = 4 words x 16 bytes = 64 bytes, indexed by sw[5:0].
//=====================================================================
module fpga_top (
    input  logic       clk,
    input  logic [7:0] sw,
    input  logic       btnc,   // commit
    input  logic       btnu,   // start
    input  logic       btnd,   // reset
    input  logic       btnl,   // reserved
    input  logic       btnr,   // reserved
    output logic [7:0] led
);
    //-----------------------------------------------------------------
    // Power-on reset: hold rst_n low until the counter saturates.
    // The declaration initializer is a synthesizable power-up value on
    // Xilinx 7-series (FFs configure to a known state at load).
    //-----------------------------------------------------------------
    logic [15:0] por = '0;
    logic        rst_n;
    always_ff @(posedge clk)
        if (!(&por)) por <= por + 1'b1;
    assign rst_n = &por;

    //-----------------------------------------------------------------
    // Button debouncers -> one-cycle pulse on a clean press
    //-----------------------------------------------------------------
    logic p_commit, p_start, p_reset;
    debounce u_dc (.clk(clk), .rst_n(rst_n), .noisy(btnc), .pulse(p_commit));
    debounce u_ds (.clk(clk), .rst_n(rst_n), .noisy(btnu), .pulse(p_start));
    debounce u_dr (.clk(clk), .rst_n(rst_n), .noisy(btnd), .pulse(p_reset));

    //-----------------------------------------------------------------
    // Accelerator (LEVEL 3) - instantiated unmodified
    //-----------------------------------------------------------------
    localparam int NVEC = 4;

    logic        start;
    logic [7:0]  num_vectors, act_base, out_base;
    logic        host_a_we; logic [7:0]  host_a_addr; logic [31:0]  host_a_wdata;
    logic        host_w_we; logic [1:0]  host_w_addr; logic [31:0]  host_w_wdata;
    logic [7:0]  host_o_addr; logic [127:0] o_rdata;
    logic [2:0]  phase; logic busy, done;
    logic signed [31:0] result [0:3];

    accelerator_system_top u_acc (
        .clk(clk), .rst_n(rst_n),
        .start(start), .num_vectors(num_vectors), .act_base(act_base), .out_base(out_base),
        .host_a_we(host_a_we), .host_a_addr(host_a_addr), .host_a_wdata(host_a_wdata),
        .host_w_we(host_w_we), .host_w_addr(host_w_addr), .host_w_wdata(host_w_wdata),
        .host_o_addr(host_o_addr), .o_rdata(o_rdata),
        .phase(phase), .busy(busy), .done(done), .result(result)
    );

    //-----------------------------------------------------------------
    // Byte buffers entered from the switches
    //-----------------------------------------------------------------
    logic [7:0] wbuf [0:15];   // 16 weight bytes,   row-major W[r][c]
    logic [7:0] abuf [0:15];   // 16 activation bytes, A[i][r]
    logic [127:0] obuf [0:3];  // 4 captured 128-bit output words

    function automatic logic [31:0] w_word(input int r);
        return {wbuf[4*r+3], wbuf[4*r+2], wbuf[4*r+1], wbuf[4*r+0]};
    endfunction
    function automatic logic [31:0] a_word(input int i);
        return {abuf[4*i+3], abuf[4*i+2], abuf[4*i+1], abuf[4*i+0]};
    endfunction

    //-----------------------------------------------------------------
    // Console FSM
    //-----------------------------------------------------------------
    typedef enum logic [2:0] {S_ENTER_W, S_ENTER_A, S_READY, S_WRITE, S_RUN, S_CAPTURE, S_READ} state_t;
    state_t st;
    logic [4:0] cnt;     // byte / word index (0..15)
    logic [2:0] rdstep;  // sub-steps for read latency

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            st <= S_ENTER_W; cnt <= '0; rdstep <= '0;
            start <= 1'b0; num_vectors <= NVEC[7:0]; act_base <= '0; out_base <= '0;
            host_a_we <= 1'b0; host_w_we <= 1'b0; host_a_addr <= '0; host_w_addr <= '0;
            host_a_wdata <= '0; host_w_wdata <= '0; host_o_addr <= '0;
        end
        else begin
            start <= 1'b0; host_a_we <= 1'b0; host_w_we <= 1'b0;   // default: pulses low

            if (p_reset) begin st <= S_ENTER_W; cnt <= '0; end
            else case (st)
                //--------------------------------------------------
                S_ENTER_W: if (p_commit) begin
                    wbuf[cnt[3:0]] <= sw;
                    if (cnt == 5'd15) begin cnt <= '0; st <= S_ENTER_A; end
                    else cnt <= cnt + 1'b1;
                end
                //--------------------------------------------------
                S_ENTER_A: if (p_commit) begin
                    abuf[cnt[3:0]] <= sw;
                    if (cnt == 5'd15) begin cnt <= '0; st <= S_READY; end
                    else cnt <= cnt + 1'b1;
                end
                //--------------------------------------------------
                S_READY: if (p_start) begin cnt <= '0; st <= S_WRITE; end
                //--------------------------------------------------
                // stream buffers into the SRAMs while !busy (8 writes)
                S_WRITE: begin
                    if (cnt < 5'd4) begin
                        host_w_we <= 1'b1; host_w_addr <= cnt[1:0]; host_w_wdata <= w_word(cnt[1:0]);
                    end else begin
                        host_a_we <= 1'b1; host_a_addr <= (cnt - 5'd4); host_a_wdata <= a_word(cnt - 5'd4);
                    end
                    if (cnt == 5'd7) begin cnt <= '0; st <= S_RUN; start <= 1'b1;
                        num_vectors <= NVEC[7:0]; act_base <= '0; out_base <= '0;
                    end else cnt <= cnt + 1'b1;
                end
                //--------------------------------------------------
                S_RUN: if (done) begin cnt <= '0; rdstep <= '0; st <= S_CAPTURE; end
                //--------------------------------------------------
                // read output_mem[0..3] into obuf (1-cycle read latency)
                S_CAPTURE: begin
                    host_o_addr <= cnt[3:0];
                    case (rdstep)
                        3'd0: rdstep <= 3'd1;                 // address issued
                        3'd1: rdstep <= 3'd2;                 // wait read latency
                        default: begin
                            obuf[cnt[1:0]] <= o_rdata;        // capture
                            rdstep <= '0;
                            if (cnt == 5'd3) st <= S_READ; else cnt <= cnt + 1'b1;
                        end
                    endcase
                end
                //--------------------------------------------------
                S_READ: /* display handled combinationally below */ ;
                default: st <= S_ENTER_W;
            endcase
        end
    end

    //-----------------------------------------------------------------
    // LED multiplexer
    //   loading  : echo the switches so the operator sees the value entered
    //   read     : sw[5:4] selects the result word, sw[3:0] the byte within it
    //-----------------------------------------------------------------
    always_comb begin
        unique case (st)
            S_READ:  led = obuf[sw[5:4]][ {sw[3:0], 3'b000} +: 8 ];
            S_RUN,
            S_WRITE,
            S_CAPTURE: led = {5'b0, phase};                // show FSM phase during a run
            default: led = sw;                             // echo while entering
        endcase
    end
endmodule


//=====================================================================
// debounce  --  synchronise + debounce a push-button, emit a 1-cycle
// pulse on a clean press.  DB_BITS sets the stability window
// (2^DB_BITS clocks ~ 2.6 ms at 100 MHz for DB_BITS=18).
//=====================================================================
module debounce #(parameter int DB_BITS = 18) (
    input  logic clk,
    input  logic rst_n,
    input  logic noisy,
    output logic pulse
);
    logic s0, s1, level;
    logic [DB_BITS-1:0] cnt;
    always_ff @(posedge clk) begin
        if (!rst_n) begin s0<=0; s1<=0; level<=0; cnt<='0; pulse<=0; end
        else begin
            s0 <= noisy; s1 <= s0;                 // 2-FF synchroniser
            pulse <= 1'b0;
            if (s1 == level) cnt <= '0;             // stable: reset the window
            else begin
                cnt <= cnt + 1'b1;                  // changing: accumulate
                if (&cnt) begin
                    level <= s1;
                    if (s1) pulse <= 1'b1;           // rising edge only
                end
            end
        end
    end
endmodule
