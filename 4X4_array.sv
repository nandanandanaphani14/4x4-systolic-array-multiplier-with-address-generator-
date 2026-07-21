module MAC_4x4_Grid #(
    parameter int INPUT_WIDTH = 8,
    parameter int ACCUM_WIDTH = 32
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic clear_acc,
    
    // Arrays for row activations and column weights
    input  logic signed [INPUT_WIDTH-1:0] activ_in [0:3],
    input  logic signed [INPUT_WIDTH-1:0] weight_in [0:3],
    
    // 2D Arrays for outputs
    output logic signed [ACCUM_WIDTH-1:0] mac_out_grid [0:3][0:3],
    output logic valid_out_grid [0:3][0:3]
);

    // ====================================================
    // ROW 0
    // ====================================================
    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_0_0 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[0]), .weight(weight_in[0]),
        .mac_out(mac_out_grid[0][0]), .valid_out(valid_out_grid[0][0])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_0_1 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[0]), .weight(weight_in[1]),
        .mac_out(mac_out_grid[0][1]), .valid_out(valid_out_grid[0][1])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_0_2 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[0]), .weight(weight_in[2]),
        .mac_out(mac_out_grid[0][2]), .valid_out(valid_out_grid[0][2])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_0_3 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[0]), .weight(weight_in[3]),
        .mac_out(mac_out_grid[0][3]), .valid_out(valid_out_grid[0][3])
    );

    // ====================================================
    // ROW 1
    // ====================================================
    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_1_0 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[1]), .weight(weight_in[0]),
        .mac_out(mac_out_grid[1][0]), .valid_out(valid_out_grid[1][0])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_1_1 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[1]), .weight(weight_in[1]),
        .mac_out(mac_out_grid[1][1]), .valid_out(valid_out_grid[1][1])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_1_2 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[1]), .weight(weight_in[2]),
        .mac_out(mac_out_grid[1][2]), .valid_out(valid_out_grid[1][2])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_1_3 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[1]), .weight(weight_in[3]),
        .mac_out(mac_out_grid[1][3]), .valid_out(valid_out_grid[1][3])
    );

    // ====================================================
    // ROW 2
    // ====================================================
    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_2_0 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[2]), .weight(weight_in[0]),
        .mac_out(mac_out_grid[2][0]), .valid_out(valid_out_grid[2][0])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_2_1 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[2]), .weight(weight_in[1]),
        .mac_out(mac_out_grid[2][1]), .valid_out(valid_out_grid[2][1])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_2_2 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[2]), .weight(weight_in[2]),
        .mac_out(mac_out_grid[2][2]), .valid_out(valid_out_grid[2][2])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_2_3 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[2]), .weight(weight_in[3]),
        .mac_out(mac_out_grid[2][3]), .valid_out(valid_out_grid[2][3])
    );

    // ====================================================
    // ROW 3
    // ====================================================
    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_3_0 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[3]), .weight(weight_in[0]),
        .mac_out(mac_out_grid[3][0]), .valid_out(valid_out_grid[3][0])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_3_1 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[3]), .weight(weight_in[1]),
        .mac_out(mac_out_grid[3][1]), .valid_out(valid_out_grid[3][1])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_3_2 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[3]), .weight(weight_in[2]),
        .mac_out(mac_out_grid[3][2]), .valid_out(valid_out_grid[3][2])
    );

    MAC #(.input_bit_width(INPUT_WIDTH), .output_bit_width(ACCUM_WIDTH)) u_PE_3_3 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ(activ_in[3]), .weight(weight_in[3]),
        .mac_out(mac_out_grid[3][3]), .valid_out(valid_out_grid[3][3])
    );

endmodule