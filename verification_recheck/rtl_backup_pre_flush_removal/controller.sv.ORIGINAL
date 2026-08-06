`timescale 1ns / 1ps
//=====================================================================
// controller.sv  --  module controller
//
// The "Control Unit (FSM)" block of the architecture diagram.  It owns
// the phase sequence only; every address is produced downstream by the
// address generator (agu.sv), which this FSM enables.
//
//---------------------------------------------------------------------
// Phase sequence
//---------------------------------------------------------------------
//   IDLE     wait for `start`; latch num_vectors
//   WLOAD    ROWS cycles - shift the weight matrix into the array
//   FLUSH    FLUSH_CYCLES cycles - let the weight values that were
//            pushed into the psum registers drain out of the bottom
//   COMPUTE  num_vectors cycles - one activation vector per clock
//   DRAIN    STORE_LATENCY cycles - the last result is still in flight
//            through skew / array / de-skew / output packing
//   DONE     one cycle, `done` pulses, then back to IDLE
//
// num_vectors = 0 is legal and skips COMPUTE entirely, so a bad command
// cannot hang the machine.
//
//---------------------------------------------------------------------
// Handshake
//---------------------------------------------------------------------
//   `start` is sampled only in IDLE and is ignored while busy.
//   `busy` is high for WLOAD..DRAIN, and is what the top level uses to
//   hand the shared SRAM address ports from the host to the AGU.
//   `done` is a single-cycle pulse; busy is already low when it fires.
//=====================================================================
module controller #(
    parameter int ROWS           = 4,
    parameter int COLS           = 4,
    parameter int VEC_CNT_W      = 8,
    // Cycles inserted between the last weight row and the first
    // activation vector.  ROWS is enough to empty the psum column;
    // the +2 keeps the result bus visibly quiet in waveforms.
    parameter int FLUSH_CYCLES   = ROWS + 2,
    // Cycles from "activation address issued" to "its result has been
    // written into the output SRAM".  Must match the datapath; see
    // wrapper_mem_arr_buf.sv.
    parameter int STORE_LATENCY  = 1 + ROWS + COLS - 2 + 1
)(
    input  logic                 clk,
    input  logic                 rst_n,

    // ---- host command interface -------------------------------------
    input  logic                 start,
    input  logic [VEC_CNT_W-1:0] num_vectors,

    // ---- phase enables to the address generator ---------------------
    output logic                 wload_phase,
    output logic                 flush_phase,
    output logic                 compute_phase,
    output logic                 drain_phase,

    // ---- status back to the host ------------------------------------
    output logic [2:0]           phase,
    output logic                 busy,
    output logic                 done
);

    localparam logic [2:0] PH_IDLE    = 3'd0;
    localparam logic [2:0] PH_WLOAD   = 3'd1;
    localparam logic [2:0] PH_FLUSH   = 3'd2;
    localparam logic [2:0] PH_COMPUTE = 3'd3;
    localparam logic [2:0] PH_DRAIN   = 3'd4;
    localparam logic [2:0] PH_DONE    = 3'd5;

    logic [2:0]           state;
    logic [VEC_CNT_W-1:0] cnt;
    logic [VEC_CNT_W-1:0] vec_n;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= PH_IDLE;
            cnt   <= '0;
            vec_n <= '0;
        end
        else begin
            case (state)
                PH_IDLE: begin
                    cnt <= '0;
                    if (start) begin
                        vec_n <= num_vectors;
                        state <= PH_WLOAD;
                    end
                end

                PH_WLOAD: begin
                    if (cnt == VEC_CNT_W'(ROWS-1)) begin
                        cnt   <= '0;
                        state <= PH_FLUSH;
                    end
                    else cnt <= cnt + 1'b1;
                end

                PH_FLUSH: begin
                    if (cnt == VEC_CNT_W'(FLUSH_CYCLES-1)) begin
                        cnt   <= '0;
                        // an empty command must not stall in COMPUTE
                        state <= (vec_n == '0) ? PH_DRAIN : PH_COMPUTE;
                    end
                    else cnt <= cnt + 1'b1;
                end

                PH_COMPUTE: begin
                    if (cnt == (vec_n - 1'b1)) begin
                        cnt   <= '0;
                        state <= PH_DRAIN;
                    end
                    else cnt <= cnt + 1'b1;
                end

                PH_DRAIN: begin
                    if (cnt == VEC_CNT_W'(STORE_LATENCY-1)) begin
                        cnt   <= '0;
                        state <= PH_DONE;
                    end
                    else cnt <= cnt + 1'b1;
                end

                PH_DONE: begin
                    cnt   <= '0;
                    state <= PH_IDLE;
                end

                default: state <= PH_IDLE;
            endcase
        end
    end

    assign phase         = state;
    assign wload_phase   = (state == PH_WLOAD);
    assign flush_phase   = (state == PH_FLUSH);
    assign compute_phase = (state == PH_COMPUTE);
    assign drain_phase   = (state == PH_DRAIN);
    assign busy          = (state != PH_IDLE) && (state != PH_DONE);
    assign done          = (state == PH_DONE);

endmodule
