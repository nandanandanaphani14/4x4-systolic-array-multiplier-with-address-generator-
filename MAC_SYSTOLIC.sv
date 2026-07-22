module MAC_PE #(
    parameter int INPUT_WIDTH = 8,
    parameter int ACCUM_WIDTH = 32
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic clear_acc,

    input  logic signed [INPUT_WIDTH-1:0] activ_in,
    input  logic signed [INPUT_WIDTH-1:0] weight_in,

    output logic signed [INPUT_WIDTH-1:0] activ_out,
    output logic signed [INPUT_WIDTH-1:0] weight_out,

    output logic signed [ACCUM_WIDTH-1:0] mac_out,
    output logic valid_out
);

    logic signed [(2*INPUT_WIDTH)-1:0] product;

    assign product = activ_in * weight_in;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            activ_out  <= '0;
            weight_out <= '0;
            mac_out    <= '0;
            valid_out  <= 1'b0;
        end else begin
            activ_out  <= activ_in;
            weight_out <= weight_in;
            valid_out  <= valid_in;

            if (valid_in) begin
                if (clear_acc)
                    mac_out <= product;
                else
                    mac_out <= mac_out + product;
            end
        end
    end

endmodule