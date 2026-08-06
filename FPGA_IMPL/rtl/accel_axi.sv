`timescale 1ns/1ps
//=====================================================================
// accel_axi.sv  --  AXI4-Lite slave wrapper around accelerator_system_top
//
// Lets a CPU (the Zynq PS on the ZedBoard) drive the accelerator over an
// AXI-Lite port, so a bare-metal "monitor" program can offer a text
// console on the on-board USB-UART (PS UART1, MIO48/49).  The accelerator
// RTL is instantiated UNMODIFIED.
//
// Register map (32-bit registers, byte address = index*4)
//   idx off   name        access  meaning
//    0  0x00  NUMVEC      W       num_vectors[7:0]
//    1  0x04  ACT_BASE    W       act_base[7:0]
//    2  0x08  OUT_BASE    W       out_base[7:0]
//    3  0x0C  W_WDATA     W       32-bit weight word (4 x int8, lane c)
//    4  0x10  W_COMMIT    W       write w_addr[1:0]  -> pulses host_w_we
//    5  0x14  A_WDATA     W       32-bit activation word (4 x int8, lane r)
//    6  0x18  A_COMMIT    W       write a_addr[7:0]  -> pulses host_a_we
//    7  0x1C  START       W       write anything     -> pulses start
//    8  0x20  O_ADDR      W       output_mem read address for read-back
//    9  0x24  STATUS      R       {29'b0, phase[2:0]? } -> {busy,done,phase}
//   10  0x28  ORD0        R       o_rdata[31:0]    (column 0 result)
//   11  0x2C  ORD1        R       o_rdata[63:32]   (column 1 result)
//   12  0x30  ORD2        R       o_rdata[95:64]   (column 2 result)
//   13  0x34  ORD3        R       o_rdata[127:96]  (column 3 result)
//
// STATUS layout:  bit0=busy, bit1=done, bits[4:2]=phase
//=====================================================================
module accel_axi #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 8
)(
    input  logic                              S_AXI_ACLK,
    input  logic                              S_AXI_ARESETN,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  logic                              S_AXI_AWVALID,
    output logic                              S_AXI_AWREADY,
    input  logic [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  logic                              S_AXI_WVALID,
    output logic                              S_AXI_WREADY,
    output logic [1:0]                        S_AXI_BRESP,
    output logic                              S_AXI_BVALID,
    input  logic                              S_AXI_BREADY,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  logic                              S_AXI_ARVALID,
    output logic                              S_AXI_ARREADY,
    output logic [C_S_AXI_DATA_WIDTH-1:0]     S_AXI_RDATA,
    output logic [1:0]                        S_AXI_RRESP,
    output logic                              S_AXI_RVALID,
    input  logic                              S_AXI_RREADY
);
    localparam int ADDR_LSB = 2;   // 32-bit word addressing

    // ---- config registers ----
    logic [7:0]  numvec_r, actbase_r, outbase_r, oaddr_r;
    logic [31:0] wdata_r, adata_r;

    // ---- one-cycle command pulses ----
    logic        start_p, w_commit_p, a_commit_p;
    logic [1:0]  w_addr_p;
    logic [7:0]  a_addr_p;

    // ---- accelerator wires ----
    logic        host_w_we; logic [1:0] host_w_addr; logic [31:0] host_w_wdata;
    logic        host_a_we; logic [7:0] host_a_addr; logic [31:0] host_a_wdata;
    logic        start;
    logic [127:0] o_rdata; logic [2:0] phase; logic busy, done;
    logic signed [31:0] result [0:3];

    //-----------------------------------------------------------------
    // AXI write channel
    //-----------------------------------------------------------------
    logic aw_en;
    logic [C_S_AXI_ADDR_WIDTH-1:0] awaddr_q;
    logic slv_wr;
    assign slv_wr = S_AXI_WREADY & S_AXI_WVALID & S_AXI_AWREADY & S_AXI_AWVALID;

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY<=0; S_AXI_WREADY<=0; S_AXI_BVALID<=0; S_AXI_BRESP<=0;
            aw_en<=1; awaddr_q<=0;
        end else begin
            // AW handshake
            if (!S_AXI_AWREADY && S_AXI_AWVALID && S_AXI_WVALID && aw_en) begin
                S_AXI_AWREADY<=1; aw_en<=0; awaddr_q<=S_AXI_AWADDR;
            end else if (S_AXI_BREADY && S_AXI_BVALID) begin
                aw_en<=1; S_AXI_AWREADY<=0;
            end else S_AXI_AWREADY<=0;
            // W handshake
            if (!S_AXI_WREADY && S_AXI_WVALID && S_AXI_AWVALID && aw_en) S_AXI_WREADY<=1;
            else S_AXI_WREADY<=0;
            // B response
            if (slv_wr && !S_AXI_BVALID) begin S_AXI_BVALID<=1; S_AXI_BRESP<=2'b00; end
            else if (S_AXI_BREADY && S_AXI_BVALID) S_AXI_BVALID<=0;
        end
    end

    //-----------------------------------------------------------------
    // Register write decode  (+ generate one-cycle command pulses)
    //-----------------------------------------------------------------
    wire [5:0] widx = awaddr_q[ADDR_LSB +: 6];
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            numvec_r<=0; actbase_r<=0; outbase_r<=0; oaddr_r<=0; wdata_r<=0; adata_r<=0;
            start_p<=0; w_commit_p<=0; a_commit_p<=0; w_addr_p<=0; a_addr_p<=0;
        end else begin
            start_p<=0; w_commit_p<=0; a_commit_p<=0;   // default: pulses low
            if (slv_wr) begin
                case (widx)
                    6'd0: numvec_r  <= S_AXI_WDATA[7:0];
                    6'd1: actbase_r <= S_AXI_WDATA[7:0];
                    6'd2: outbase_r <= S_AXI_WDATA[7:0];
                    6'd3: wdata_r   <= S_AXI_WDATA;
                    6'd4: begin w_addr_p <= S_AXI_WDATA[1:0]; w_commit_p <= 1'b1; end
                    6'd5: adata_r   <= S_AXI_WDATA;
                    6'd6: begin a_addr_p <= S_AXI_WDATA[7:0]; a_commit_p <= 1'b1; end
                    6'd7: start_p   <= 1'b1;
                    6'd8: oaddr_r   <= S_AXI_WDATA[7:0];
                    default: ;
                endcase
            end
        end
    end

    // drive the accelerator host ports from the pulses/regs
    assign host_w_we    = w_commit_p;  assign host_w_addr = w_addr_p;  assign host_w_wdata = wdata_r;
    assign host_a_we    = a_commit_p;  assign host_a_addr = a_addr_p;  assign host_a_wdata = adata_r;
    assign start        = start_p;

    // Sticky "done": the RTL pulses done for one cycle, far too briefly for
    // the CPU to catch by polling.  Latch it here; clear it when a new job
    // starts.  Software polls STATUS.bit1 until it reads 1.
    logic done_sticky;
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) done_sticky <= 1'b0;
        else if (start_p)   done_sticky <= 1'b0;
        else if (done)      done_sticky <= 1'b1;
    end

    //-----------------------------------------------------------------
    // AXI read channel
    //-----------------------------------------------------------------
    logic [C_S_AXI_ADDR_WIDTH-1:0] araddr_q;
    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY<=0; S_AXI_RVALID<=0; S_AXI_RRESP<=0; araddr_q<=0;
        end else begin
            if (!S_AXI_ARREADY && S_AXI_ARVALID) begin S_AXI_ARREADY<=1; araddr_q<=S_AXI_ARADDR; end
            else S_AXI_ARREADY<=0;
            if (S_AXI_ARREADY && S_AXI_ARVALID && !S_AXI_RVALID) begin S_AXI_RVALID<=1; S_AXI_RRESP<=2'b00; end
            else if (S_AXI_RVALID && S_AXI_RREADY) S_AXI_RVALID<=0;
        end
    end

    wire [5:0] ridx = araddr_q[ADDR_LSB +: 6];
    always_comb begin
        unique case (ridx)
            6'd9:  S_AXI_RDATA = {27'b0, phase, done_sticky, busy};
            6'd10: S_AXI_RDATA = o_rdata[31:0];
            6'd11: S_AXI_RDATA = o_rdata[63:32];
            6'd12: S_AXI_RDATA = o_rdata[95:64];
            6'd13: S_AXI_RDATA = o_rdata[127:96];
            default: S_AXI_RDATA = 32'h0;
        endcase
    end

    //-----------------------------------------------------------------
    // The accelerator (LEVEL 3), unmodified
    //-----------------------------------------------------------------
    accelerator_system_top u_acc (
        .clk(S_AXI_ACLK), .rst_n(S_AXI_ARESETN),
        .start(start), .num_vectors(numvec_r), .act_base(actbase_r), .out_base(outbase_r),
        .host_a_we(host_a_we), .host_a_addr(host_a_addr), .host_a_wdata(host_a_wdata),
        .host_w_we(host_w_we), .host_w_addr(host_w_addr), .host_w_wdata(host_w_wdata),
        .host_o_addr(oaddr_r), .o_rdata(o_rdata),
        .phase(phase), .busy(busy), .done(done), .result(result)
    );
endmodule
