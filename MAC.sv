module MAC #(
    parameter int input_bit_width = 8,
    parameter int output_bit_width = 32
)(
    input  logic clk,
    input  logic rst,
    input  logic valid_in,
    input  logic clear_acc,
    input  logic signed [input_bit_width-1:0] activ,
    input  logic signed [input_bit_width-1:0] weight,
    
    output logic signed [output_bit_width-1:0] mac_out,
    output logic valid_out
);

    logic signed [(2*input_bit_width)-1:0] product;
    assign product = activ * weight;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mac_out   <= '0;              
            valid_out <= 1'b0;
        end else if (valid_in) begin
            // We have valid data, so the output will be valid
            valid_out <= 1'b1;
            
            // Check if we are starting a NEW dot product
            if (clear_acc) begin
                mac_out <= product;
            end else begin
                // Continuing the CURRENT dot product
                mac_out <= mac_out + product;
            end
        end else begin
            // Data is not valid
            valid_out <= 1'b0;
        end
    end 
endmodule