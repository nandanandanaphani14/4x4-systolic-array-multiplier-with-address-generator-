module input_skew_buffer #(
    parameter ROWS  = 4,
    parameter WIDTH = 8
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic signed [WIDTH-1:0] dense_a_in     [0:ROWS-1],
    input  logic                    dense_valid_in [0:ROWS-1],
    output logic signed [WIDTH-1:0] skew_a_out     [0:ROWS-1],
    output logic                    skew_valid_out [0:ROWS-1]
);
    genvar r;
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_input_skew
            delay_pipe #(
                .WIDTH(WIDTH),
                .DELAY(r)
            ) u_a_delay (
                .clk  (clk),
                .rst_n(rst_n),
                .din  (dense_a_in[r]),
                .dout (skew_a_out[r])
            );

            delay_pipe #(
                .WIDTH(1),
                .DELAY(r)
            ) u_v_delay (
                .clk  (clk),
                .rst_n(rst_n),
                .din  (dense_valid_in[r]),
                .dout (skew_valid_out[r])
            );
        end
    endgenerate
endmodule