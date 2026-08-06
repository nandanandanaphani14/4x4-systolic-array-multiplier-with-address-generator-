`timescale 1ns / 1ps

module processing_element (
    input  logic               clk,
    input  logic               rst_n,
    
    // Control signals
    input  logic               wload,
    input  logic               valid_in,
    
    // Horizontal Activation Stream
    input  logic signed [7:0]  a_in,
    output logic signed [7:0]  a_out,
    output logic               valid_out,
    
    // Vertical Shared Stream (Weights during wload=1, Partial Sums during wload=0)
    input  logic signed [31:0] psum_in,
    output logic signed [31:0] psum_out
);

    // Internal Registers
    logic signed [7:0]  weight_q;
    logic signed [7:0]  a_q;
    logic               valid_q;
    logic signed [31:0] psum_q;

    // Combinational Arithmetic
    logic signed [31:0] product_ext;
    logic signed [31:0] adder_out;

    // MAC operation: Multiply incoming a_in by stored weight
    assign product_ext = 32'(weight_q * a_in); 
    assign adder_out   = psum_in + product_ext;

    // Register Updates
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            weight_q <= '0;
            a_q      <= '0;
            valid_q  <= '0;
            psum_q   <= '0;
        end else begin
            // 1. Weight Stationary Logic
            if (wload) begin
                weight_q <= psum_in[7:0]; // Capture weight from shared psum bus
            end
            
            // 2. Horizontal Pipeline (Activations)
            a_q     <= a_in;
            valid_q <= valid_in;
            
            // 3. Vertical Pipeline (Accumulator with Valid Gating)
            psum_q  <= valid_in ? adder_out : psum_in;
        end
    end

    // Continuous Assignments for Outputs
    assign a_out     = a_q;
    assign valid_out = valid_q;
    
    // Time-multiplexed output: Shift weight down during load, pass sum during compute
    assign psum_out  = wload ? 32'(weight_q) : psum_q;

endmodule