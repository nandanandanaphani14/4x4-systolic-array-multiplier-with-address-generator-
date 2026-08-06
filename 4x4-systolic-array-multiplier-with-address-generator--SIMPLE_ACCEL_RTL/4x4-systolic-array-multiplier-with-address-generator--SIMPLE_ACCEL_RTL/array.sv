`timescale 1ns / 1ps

module systolic_array #(
    parameter ROWS = 4,
    parameter COLS = 4
)(
    input  logic               clk,
    input  logic               rst_n,
    
    // Global Array Phase Control
    input  logic               wload, 
    
    // Left Boundary (Activations streaming from Input Skew Buffer)
    input  logic signed [7:0]  a_in_left     [0:ROWS-1],
    input  logic               valid_in_left [0:ROWS-1],
    
    // Top Boundary (Weights or Initial Zeros streaming from SRAM)
    input  logic signed [31:0] psum_in_top   [0:COLS-1],
    
    // Bottom Boundary (Completed Dot Products going to Output De-skew Buffer)
    output logic signed [31:0] psum_out_bottom [0:COLS-1]
);

    // Internal interconnect wires
    logic signed [7:0]  a_net     [0:ROWS-1][0:COLS];
    logic               valid_net [0:ROWS-1][0:COLS];
    logic signed [31:0] psum_net  [0:ROWS][0:COLS-1];

    genvar r, c;
    generate
        // 1. Bind Left and Top Boundaries to internal nets
        for (r = 0; r < ROWS; r++) begin : left_bind
            assign a_net[r][0]     = a_in_left[r];
            assign valid_net[r][0] = valid_in_left[r];
        end
        
        for (c = 0; c < COLS; c++) begin : top_bind
            assign psum_net[0][c]  = psum_in_top[c];
        end

        // 2. Instantiate PE Grid
        for (r = 0; r < ROWS; r++) begin : row_gen
            for (c = 0; c < COLS; c++) begin : col_gen
                processing_element pe_inst (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .wload      (wload),
                    
                    // Horizontal links
                    .valid_in   (valid_net[r][c]),
                    .a_in       (a_net[r][c]),
                    .valid_out  (valid_net[r][c+1]),
                    .a_out      (a_net[r][c+1]),
                    
                    // Vertical links
                    .psum_in    (psum_net[r][c]),
                    .psum_out   (psum_net[r+1][c])
                );
            end
        end
        
        // 3. Bind Bottom Boundary to outputs
        for (c = 0; c < COLS; c++) begin : bottom_bind
            assign psum_out_bottom[c] = psum_net[ROWS][c];
        end
    endgenerate

endmodule