// axil_arb2.sv — 2-master -> 1-slave AXI4-Lite arbiter (one transaction at a time).
// Master 0 = JTAG-to-AXI, master 1 = UART bridge. First request wins, ownership is
// held until the matching B or R response has been accepted.
`timescale 1ns / 1ps
module axil_arb2 (
    input  wire        clk,
    input  wire        rst_n,
    // master 0
    input  wire [31:0] m0_awaddr, input wire m0_awvalid, output wire m0_awready,
    input  wire [31:0] m0_wdata,  input wire [3:0] m0_wstrb, input wire m0_wvalid, output wire m0_wready,
    output wire [1:0]  m0_bresp,  output wire m0_bvalid, input wire m0_bready,
    input  wire [31:0] m0_araddr, input wire m0_arvalid, output wire m0_arready,
    output wire [31:0] m0_rdata,  output wire [1:0] m0_rresp, output wire m0_rvalid, input wire m0_rready,
    // master 1
    input  wire [31:0] m1_awaddr, input wire m1_awvalid, output wire m1_awready,
    input  wire [31:0] m1_wdata,  input wire [3:0] m1_wstrb, input wire m1_wvalid, output wire m1_wready,
    output wire [1:0]  m1_bresp,  output wire m1_bvalid, input wire m1_bready,
    input  wire [31:0] m1_araddr, input wire m1_arvalid, output wire m1_arready,
    output wire [31:0] m1_rdata,  output wire [1:0] m1_rresp, output wire m1_rvalid, input wire m1_rready,
    // slave side
    output wire [31:0] s_awaddr, output wire s_awvalid, input wire s_awready,
    output wire [31:0] s_wdata,  output wire [3:0] s_wstrb, output wire s_wvalid, input wire s_wready,
    input  wire [1:0]  s_bresp,  input wire s_bvalid, output wire s_bready,
    output wire [31:0] s_araddr, output wire s_arvalid, input wire s_arready,
    input  wire [31:0] s_rdata,  input wire [1:0] s_rresp, input wire s_rvalid, output wire s_rready
);
    reg [1:0] owner;   // 0 none, 1 master0, 2 master1
    wire req0 = m0_awvalid | m0_wvalid | m0_arvalid;
    wire req1 = m1_awvalid | m1_wvalid | m1_arvalid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) owner <= 2'd0;
        else case (owner)
            2'd0: if (req0) owner <= 2'd1; else if (req1) owner <= 2'd2;
            default: if ((s_bvalid && s_bready) || (s_rvalid && s_rready)) owner <= 2'd0;
        endcase
    end
    wire g0 = (owner == 2'd1), g1 = (owner == 2'd2);

    assign s_awaddr  = g0 ? m0_awaddr : m1_awaddr;
    assign s_awvalid = g0 ? m0_awvalid : (g1 ? m1_awvalid : 1'b0);
    assign s_wdata   = g0 ? m0_wdata : m1_wdata;
    assign s_wstrb   = g0 ? m0_wstrb : m1_wstrb;
    assign s_wvalid  = g0 ? m0_wvalid : (g1 ? m1_wvalid : 1'b0);
    assign s_bready  = g0 ? m0_bready : (g1 ? m1_bready : 1'b0);
    assign s_araddr  = g0 ? m0_araddr : m1_araddr;
    assign s_arvalid = g0 ? m0_arvalid : (g1 ? m1_arvalid : 1'b0);
    assign s_rready  = g0 ? m0_rready : (g1 ? m1_rready : 1'b0);

    assign m0_awready = g0 & s_awready;  assign m1_awready = g1 & s_awready;
    assign m0_wready  = g0 & s_wready;   assign m1_wready  = g1 & s_wready;
    assign m0_bresp   = s_bresp;         assign m1_bresp   = s_bresp;
    assign m0_bvalid  = g0 & s_bvalid;   assign m1_bvalid  = g1 & s_bvalid;
    assign m0_arready = g0 & s_arready;  assign m1_arready = g1 & s_arready;
    assign m0_rdata   = s_rdata;         assign m1_rdata   = s_rdata;
    assign m0_rresp   = s_rresp;         assign m1_rresp   = s_rresp;
    assign m0_rvalid  = g0 & s_rvalid;   assign m1_rvalid  = g1 & s_rvalid;
endmodule
