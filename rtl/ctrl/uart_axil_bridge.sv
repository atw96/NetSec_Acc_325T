// uart_axil_bridge.sv — 8N1 UART to AXI4-Lite master (single outstanding).
//
// Binary protocol, big-endian, host initiates:
//   write:  'W'(0x57) A3 A2 A1 A0 D3 D2 D1 D0   -> 'K'(0x4B)  (or 'E'(0x45) on AXI error)
//   read :  'R'(0x52) A3 A2 A1 A0               -> D3 D2 D1 D0 (or 'E')
//   ping :  'P'(0x50)                           -> 'p'(0x70)
// An incomplete command is discarded after ~5 ms of silence.
`timescale 1ns / 1ps
module uart_axil_bridge #(
    parameter integer CLK_HZ = 125_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        uart_rx,
    output wire        uart_tx,

    output reg  [31:0] m_awaddr,
    output reg         m_awvalid,
    input  wire        m_awready,
    output reg  [31:0] m_wdata,
    output wire [3:0]  m_wstrb,
    output reg         m_wvalid,
    input  wire        m_wready,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output reg         m_bready,
    output reg  [31:0] m_araddr,
    output reg         m_arvalid,
    input  wire        m_arready,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rvalid,
    output reg         m_rready
);
    localparam integer DIV = CLK_HZ / BAUD;
    assign m_wstrb = 4'hF;

    // ---------- RX ----------
    reg [2:0] rx_s;
    always @(posedge clk) rx_s <= {rx_s[1:0], uart_rx};
    reg [15:0] rx_cnt;
    reg [3:0]  rx_bit;
    reg        rx_busy;
    reg [7:0]  rx_sh;
    reg [7:0]  rx_byte;
    reg        rx_stb;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_cnt <= 16'd0; rx_bit <= 4'd0; rx_busy <= 1'b0; rx_sh <= 8'd0; rx_byte <= 8'd0; rx_stb <= 1'b0;
        end else begin
            rx_stb <= 1'b0;
            if (!rx_busy) begin
                if (!rx_s[2]) begin rx_busy <= 1'b1; rx_cnt <= DIV/2; rx_bit <= 4'd0; end
            end else if (rx_cnt != 0) begin
                rx_cnt <= rx_cnt - 1'b1;
            end else begin
                rx_cnt <= DIV - 1;
                if (rx_bit == 4'd0) begin
                    if (rx_s[2]) rx_busy <= 1'b0;     // false start
                    else rx_bit <= 4'd1;
                end else if (rx_bit <= 4'd8) begin
                    rx_sh <= {rx_s[2], rx_sh[7:1]};
                    rx_bit <= rx_bit + 1'b1;
                end else begin                         // stop bit
                    rx_busy <= 1'b0;
                    if (rx_s[2]) begin rx_byte <= rx_sh; rx_stb <= 1'b1; end
                end
            end
        end
    end

    // ---------- TX ----------
    reg [15:0] tx_cnt;
    reg [3:0]  tx_bit;
    reg [9:0]  tx_sh;
    reg        tx_busy;
    reg        tx_req;
    reg  [7:0] tx_req_d;
    assign uart_tx = tx_busy ? tx_sh[0] : 1'b1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_cnt <= 16'd0; tx_bit <= 4'd0; tx_sh <= 10'h3FF; tx_busy <= 1'b0;
        end else begin
            if (!tx_busy) begin
                if (tx_req) begin tx_sh <= {1'b1, tx_req_d, 1'b0}; tx_busy <= 1'b1; tx_cnt <= DIV - 1; tx_bit <= 4'd0; end
            end else if (tx_cnt != 0) tx_cnt <= tx_cnt - 1'b1;
            else begin
                tx_cnt <= DIV - 1;
                tx_sh  <= {1'b1, tx_sh[9:1]};
                tx_bit <= tx_bit + 1'b1;
                if (tx_bit == 4'd9) tx_busy <= 1'b0;
            end
        end
    end

    // ---------- command FSM ----------
    typedef enum logic [3:0] {
        C_IDLE, C_ADDR, C_DATA, C_AW, C_W, C_B, C_AR, C_R, C_TX, C_TXWAIT
    } c_t;
    c_t cs;
    reg        is_wr;
    reg [2:0]  nrx;
    reg [31:0] rd_val;
    reg [2:0]  ntx;
    reg        err;
    reg        reply_one;       // reply is a single byte
    reg  [7:0] reply_b;
    reg [21:0] idle_cnt;
    reg        aw_done, w_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs <= C_IDLE; is_wr <= 1'b0; nrx <= 3'd0; rd_val <= 32'd0; ntx <= 3'd0; err <= 1'b0;
            reply_one <= 1'b0; reply_b <= 8'd0; idle_cnt <= 22'd0; tx_req <= 1'b0; tx_req_d <= 8'd0;
            m_awaddr <= 32'd0; m_awvalid <= 1'b0; m_wdata <= 32'd0; m_wvalid <= 1'b0; m_bready <= 1'b0;
            m_araddr <= 32'd0; m_arvalid <= 1'b0; m_rready <= 1'b0; aw_done <= 1'b0; w_done <= 1'b0;
        end else begin
            tx_req <= 1'b0;
            if (cs == C_IDLE || cs == C_ADDR || cs == C_DATA) begin
                if (rx_stb) idle_cnt <= 22'd0;
                else if (cs != C_IDLE) begin
                    idle_cnt <= idle_cnt + 1'b1;
                    if (idle_cnt == (CLK_HZ/200)) begin cs <= C_IDLE; idle_cnt <= 22'd0; end
                end
            end
            case (cs)
            C_IDLE: if (rx_stb) begin
                case (rx_byte)
                    8'h57: begin is_wr <= 1'b1; nrx <= 3'd0; cs <= C_ADDR; end
                    8'h52: begin is_wr <= 1'b0; nrx <= 3'd0; cs <= C_ADDR; end
                    8'h50: begin reply_one <= 1'b1; reply_b <= 8'h70; cs <= C_TX; end
                    default: ;
                endcase
            end
            C_ADDR: if (rx_stb) begin
                if (is_wr) m_awaddr <= {m_awaddr[23:0], rx_byte}; 
                m_araddr <= {m_araddr[23:0], rx_byte};
                if (nrx == 3'd3) begin
                    nrx <= 3'd0;
                    if (is_wr) cs <= C_DATA;
                    else begin m_arvalid <= 1'b1; m_rready <= 1'b1; cs <= C_AR; end
                end else nrx <= nrx + 1'b1;
            end
            C_DATA: if (rx_stb) begin
                m_wdata <= {m_wdata[23:0], rx_byte};
                if (nrx == 3'd3) begin
                    nrx <= 3'd0; m_awvalid <= 1'b1; m_wvalid <= 1'b1;
                    aw_done <= 1'b0; w_done <= 1'b0; cs <= C_AW;
                end else nrx <= nrx + 1'b1;
            end
            C_AW: begin
                if (m_awvalid && m_awready) begin m_awvalid <= 1'b0; aw_done <= 1'b1; end
                if (m_wvalid && m_wready)   begin m_wvalid  <= 1'b0; w_done  <= 1'b1; end
                if (aw_done && w_done) begin m_bready <= 1'b1; cs <= C_B; end
            end
            C_B: if (m_bvalid && m_bready) begin
                m_bready <= 1'b0; reply_one <= 1'b1; reply_b <= (m_bresp == 2'b00) ? 8'h4B : 8'h45; cs <= C_TX;
            end
            C_AR: begin
                if (m_arvalid && m_arready) m_arvalid <= 1'b0;
                if (m_rvalid) begin
                    m_rready <= 1'b0; m_arvalid <= 1'b0;
                    if (m_rresp == 2'b00) begin rd_val <= m_rdata; reply_one <= 1'b0; ntx <= 3'd0; end
                    else begin reply_one <= 1'b1; reply_b <= 8'h45; end
                    cs <= C_TX;
                end
            end
            C_TX: begin
                if (!tx_busy && !tx_req) begin
                    tx_req <= 1'b1;
                    tx_req_d <= reply_one ? reply_b :
                                (ntx == 3'd0) ? rd_val[31:24] : (ntx == 3'd1) ? rd_val[23:16] :
                                (ntx == 3'd2) ? rd_val[15:8]  : rd_val[7:0];
                    cs <= C_TXWAIT;
                end
            end
            C_TXWAIT: if (tx_busy) begin
                if (reply_one || ntx == 3'd3) cs <= C_IDLE;
                else begin ntx <= ntx + 1'b1; cs <= C_TX; end
            end
            default: cs <= C_IDLE;
            endcase
        end
    end
endmodule
