module delay_pipe #(
    parameter WIDTH = 8,
    parameter DELAY = 1
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout
);
    generate
        if (DELAY == 0) begin : gen_no_delay
            assign dout = din;
        end
        else begin : gen_with_delay
            logic [WIDTH-1:0] pipe [0:DELAY-1];
            integer i;

            always_ff @(posedge clk) begin
                if (!rst_n) begin
                    for (i = 0; i < DELAY; i = i + 1)
                        pipe[i] <= '0;
                end
                else begin
                    pipe[0] <= din;
                    for (i = 1; i < DELAY; i = i + 1)
                        pipe[i] <= pipe[i-1];
                end
            end

            assign dout = pipe[DELAY-1];
        end
    endgenerate
endmodule