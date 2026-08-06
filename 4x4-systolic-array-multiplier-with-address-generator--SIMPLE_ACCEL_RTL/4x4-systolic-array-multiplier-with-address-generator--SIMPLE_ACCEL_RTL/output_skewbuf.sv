module output_deskew_buffer #(
    parameter COLS  = 4,
    parameter WIDTH = 32
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic signed [WIDTH-1:0] psum_in        [0:COLS-1],
    output logic signed [WIDTH-1:0] aligned_out    [0:COLS-1]
);
    genvar c;
    generate
        for (c = 0; c < COLS; c = c + 1) begin : gen_output_deskew
            delay_pipe #(
                .WIDTH(WIDTH),
                .DELAY(COLS-1-c)
            ) u_psum_delay (
                .clk  (clk),
                .rst_n(rst_n),
                .din  (psum_in[c]),
                .dout (aligned_out[c])
            );
        end
    endgenerate
endmodule