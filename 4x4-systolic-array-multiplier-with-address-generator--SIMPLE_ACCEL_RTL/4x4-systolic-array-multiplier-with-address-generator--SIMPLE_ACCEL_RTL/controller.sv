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
//   IDLE     wait for `start`; latch num_vectors and load_weights
//   WLOAD    ROWS cycles - shift the weight matrix into the array.
//            SKIPPED ENTIRELY when load_weights = 0.
//   COMPUTE  num_vectors cycles - one activation vector per clock
//   DRAIN    STORE_LATENCY cycles - the last result is still in flight
//            through skew / array / de-skew / output packing
//   DONE     one cycle, `done` pulses, then back to IDLE
//
// num_vectors = 0 is legal and skips COMPUTE entirely, so a bad command
// cannot hang the machine.
//
//---------------------------------------------------------------------
// Job length
//---------------------------------------------------------------------
//   load_weights = 1 :  ROWS + N + STORE_LATENCY + 1  =  N + 13
//   load_weights = 0 :         N + STORE_LATENCY + 1  =  N +  9
//   For the 4x4 case (N = 4) that is 17 and 13 clocks respectively,
//   measured from the edge that samples `start` to the `done` pulse.
//   Add one cycle for the IDLE turnaround to get the issue interval.
//
//---------------------------------------------------------------------
// Why there is no FLUSH phase
//---------------------------------------------------------------------
//   Earlier revisions inserted FLUSH_CYCLES = ROWS + 2 cycles between
//   WLOAD and COMPUTE.  It existed because WLOAD leaves weight bytes
//   sitting in every psum_q register on their way down the column
//   (MAC.sv drives psum_out = weight_q while wload is high, and
//   psum_q <= psum_in with valid low), and those bytes have to leave the
//   array before they can be mistaken for results.
//
//   They never could be.  The junk drains out of the bottom of the array
//   at one row per cycle and reaches the output write port well before
//   the AGU's write-strobe pipe - which is STORE_LATENCY deep and keyed
//   off compute_phase - raises its first out_we.  Accumulation is never
//   at risk either: a PE's psum_q is only ever an OUTPUT of the adder,
//   never an input (adder_out = psum_in + product), so stale content is
//   overwritten, not accumulated into.  FLUSH was therefore margin, not
//   function, and has been removed.  See the analysis in
//   context_mkdwn/12_dataflow_and_timing.md.
//
//---------------------------------------------------------------------
// Handshake
//---------------------------------------------------------------------
//   `start` is sampled only in IDLE and is ignored while busy.
//   `load_weights` is sampled at the same edge as `start`.
//   `busy` is high for WLOAD..DRAIN, and is what the top level uses to
//   hand the shared SRAM address ports from the host to the AGU.
//   `done` is a single-cycle pulse; busy is already low when it fires.
//=====================================================================
module controller #(
    parameter int ROWS           = 4,
    parameter int COLS           = 4,
    parameter int VEC_CNT_W      = 8,
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
    // 1 = shift the weight matrix into the array first (WLOAD);
    // 0 = the array already holds the right weights, go straight to
    //     COMPUTE.  Sampled with `start`.
    input  logic                 load_weights,

    // ---- phase enables to the address generator ---------------------
    output logic                 wload_phase,
    output logic                 compute_phase,
    output logic                 drain_phase,

    // ---- status back to the host ------------------------------------
    output logic [2:0]           phase,
    output logic                 busy,
    output logic                 done
);

    localparam logic [2:0] PH_IDLE    = 3'd0;
    localparam logic [2:0] PH_WLOAD   = 3'd1;
    localparam logic [2:0] PH_COMPUTE = 3'd2;
    localparam logic [2:0] PH_DRAIN   = 3'd3;
    localparam logic [2:0] PH_DONE    = 3'd4;

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
                        if (load_weights)
                            state <= PH_WLOAD;
                        else
                            // an empty command must not stall in COMPUTE
                            state <= (num_vectors == '0) ? PH_DRAIN : PH_COMPUTE;
                    end
                end

                PH_WLOAD: begin
                    if (cnt == VEC_CNT_W'(ROWS-1)) begin
                        cnt   <= '0;
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
    assign compute_phase = (state == PH_COMPUTE);
    assign drain_phase   = (state == PH_DRAIN);
    assign busy          = (state != PH_IDLE) && (state != PH_DONE);
    assign done          = (state == PH_DONE);

endmodule
