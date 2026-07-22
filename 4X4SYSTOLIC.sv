module SYSTOLIC_4x4 #(
    parameter int INPUT_WIDTH = 8,
    parameter int ACCUM_WIDTH = 32
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic clear_acc,

    input  logic signed [INPUT_WIDTH-1:0] activ_left [0:3],
    input  logic signed [INPUT_WIDTH-1:0] weight_top [0:3],

    output logic signed [ACCUM_WIDTH-1:0] mac_out [0:3][0:3],
    output logic        valid_out [0:3][0:3]
);

    logic signed [INPUT_WIDTH-1:0] activ_pipe  [0:3][0:3];
    logic signed [INPUT_WIDTH-1:0] weight_pipe [0:3][0:3];

    // Row 0
    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_0_0 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_left[0]), .weight_in(weight_top[0]),
        .activ_out(activ_pipe[0][0]), .weight_out(weight_pipe[0][0]),
        .mac_out(mac_out[0][0]), .valid_out(valid_out[0][0])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_0_1 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[0][0]), .weight_in(weight_top[1]),
        .activ_out(activ_pipe[0][1]), .weight_out(weight_pipe[0][1]),
        .mac_out(mac_out[0][1]), .valid_out(valid_out[0][1])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_0_2 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[0][1]), .weight_in(weight_top[2]),
        .activ_out(activ_pipe[0][2]), .weight_out(weight_pipe[0][2]),
        .mac_out(mac_out[0][2]), .valid_out(valid_out[0][2])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_0_3 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[0][2]), .weight_in(weight_top[3]),
        .activ_out(), .weight_out(weight_pipe[0][3]),
        .mac_out(mac_out[0][3]), .valid_out(valid_out[0][3])
    );

    // Row 1
    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_1_0 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_left[1]), .weight_in(weight_pipe[0][0]),
        .activ_out(activ_pipe[1][0]), .weight_out(weight_pipe[1][0]),
        .mac_out(mac_out[1][0]), .valid_out(valid_out[1][0])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_1_1 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[1][0]), .weight_in(weight_pipe[0][1]),
        .activ_out(activ_pipe[1][1]), .weight_out(weight_pipe[1][1]),
        .mac_out(mac_out[1][1]), .valid_out(valid_out[1][1])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_1_2 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[1][1]), .weight_in(weight_pipe[0][2]),
        .activ_out(activ_pipe[1][2]), .weight_out(weight_pipe[1][2]),
        .mac_out(mac_out[1][2]), .valid_out(valid_out[1][2])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_1_3 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[1][2]), .weight_in(weight_pipe[0][3]),
        .activ_out(), .weight_out(weight_pipe[1][3]),
        .mac_out(mac_out[1][3]), .valid_out(valid_out[1][3])
    );

    // Row 2
    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_2_0 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_left[2]), .weight_in(weight_pipe[1][0]),
        .activ_out(activ_pipe[2][0]), .weight_out(weight_pipe[2][0]),
        .mac_out(mac_out[2][0]), .valid_out(valid_out[2][0])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_2_1 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[2][0]), .weight_in(weight_pipe[1][1]),
        .activ_out(activ_pipe[2][1]), .weight_out(weight_pipe[2][1]),
        .mac_out(mac_out[2][1]), .valid_out(valid_out[2][1])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_2_2 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[2][1]), .weight_in(weight_pipe[1][2]),
        .activ_out(activ_pipe[2][2]), .weight_out(weight_pipe[2][2]),
        .mac_out(mac_out[2][2]), .valid_out(valid_out[2][2])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_2_3 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[2][2]), .weight_in(weight_pipe[1][3]),
        .activ_out(), .weight_out(weight_pipe[2][3]),
        .mac_out(mac_out[2][3]), .valid_out(valid_out[2][3])
    );

    // Row 3
    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_3_0 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_left[3]), .weight_in(weight_pipe[2][0]),
        .activ_out(activ_pipe[3][0]), .weight_out(),
        .mac_out(mac_out[3][0]), .valid_out(valid_out[3][0])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_3_1 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[3][0]), .weight_in(weight_pipe[2][1]),
        .activ_out(activ_pipe[3][1]), .weight_out(),
        .mac_out(mac_out[3][1]), .valid_out(valid_out[3][1])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_3_2 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[3][1]), .weight_in(weight_pipe[2][2]),
        .activ_out(activ_pipe[3][2]), .weight_out(),
        .mac_out(mac_out[3][2]), .valid_out(valid_out[3][2])
    );

    MAC_PE #(.INPUT_WIDTH(INPUT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH)) u_pe_3_3 (
        .clk(clk), .rst(rst), .valid_in(valid_in), .clear_acc(clear_acc),
        .activ_in(activ_pipe[3][2]), .weight_in(weight_pipe[2][3]),
        .activ_out(), .weight_out(),
        .mac_out(mac_out[3][3]), .valid_out(valid_out[3][3])
    );

endmodule