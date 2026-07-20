`timescale 1ns/1ps

module tb_MAC;

    // Parameters
    localparam int IN_WIDTH  = 8;
    localparam int OUT_WIDTH = 32;

    // DUT Signals
    logic clk;
    logic rst;
    logic valid_in;
    logic clear_acc;
    logic signed [IN_WIDTH-1:0]  activ;
    logic signed [IN_WIDTH-1:0]  weight;
    
    logic signed [OUT_WIDTH-1:0] mac_out;
    logic valid_out;

    // Instantiate the DUT
    MAC #(
        .input_bit_width(IN_WIDTH),
        .output_bit_width(OUT_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .valid_in(valid_in),
        .clear_acc(clear_acc),
        .activ(activ),
        .weight(weight),
        .mac_out(mac_out),
        .valid_out(valid_out)
    );

    // Clock Generation (10ns period / 100MHz)
    always #5 clk = ~clk;

    // Test Sequence
    initial begin
        // 1. Initialize signals
        clk       = 0;
        rst       = 1;
        valid_in  = 0;
        clear_acc = 0;
        activ     = '0;
        weight    = '0;

        // 2. Apply Reset
        #20;
        rst = 0;
        #10;
        
        $display("--- Starting First Dot Product ---");
        // We will calculate: (2 * 3) + (-1 * 4) + (5 * 2) = 6 - 4 + 10 = 12
        
        // Cycle 1: First element (MUST assert clear_acc to clear old junk)
        @(posedge clk);
        valid_in  <= 1;
        clear_acc <= 1;  
        activ     <= 8'sd2;
        weight    <= 8'sd3;

        // Cycle 2: Second element (De-assert clear_acc to accumulate)
        @(posedge clk);
        valid_in  <= 1;
        clear_acc <= 0;  
        activ     <= -8'sd1;
        weight    <= 8'sd4;

        // Cycle 3: Third element
        @(posedge clk);
        valid_in  <= 1;
        clear_acc <= 0;  
        activ     <= 8'sd5;
        weight    <= 8'sd2;
        
        // Pause for a cycle (Simulation of memory stall)
        @(posedge clk);
        valid_in  <= 0;
        
        $display("--- Starting Second Dot Product ---");
        // We will calculate: (-3 * -3) + (1 * 5) = 9 + 5 = 14
        
        // Cycle 4: First element of NEW dot product
        @(posedge clk);
        valid_in  <= 1;
        clear_acc <= 1; // Resets the accumulator, overwriting the '12' 
        activ     <= -8'sd3;
        weight    <= -8'sd3;
        
        // Cycle 5: Second element
        @(posedge clk);
        valid_in  <= 1;
        clear_acc <= 0;  
        activ     <= 8'sd1;
        weight    <= 8'sd5;

        // Stop feeding data
        @(posedge clk);
        valid_in  <= 0;
        clear_acc <= 0;

        // Wait a few cycles to observe the final valid_out falling
        #30;
        $display("Simulation Complete.");
        $finish;
    end

    // Monitor to print outputs to the console automatically
    initial begin
        $monitor("Time=%0t | val_in=%b clr=%b A=%d W=%d | MAC_OUT=%d val_out=%b", 
                 $time, valid_in, clear_acc, activ, weight, mac_out, valid_out);
    end

endmodule