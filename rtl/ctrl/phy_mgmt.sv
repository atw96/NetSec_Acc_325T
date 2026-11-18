// phy_mgmt.sv — MDIO management for one RTL8211F(D) PHY.
//   * optional boot-time auto configuration (after PHY reset release + settle):
//       read PHYID1, then page 0xD08: set TXDLY (reg 0x11 b8) and RXDLY (reg 0x15 b3), page 0
//   * background link polling (BMSR reg 1, bit 2) every ~10 ms
//   * host-initiated single MDIO transaction (go/we/reg/phy/wdata) when idle
// This makes the RGMII delay configuration deterministic regardless of the
// board's strap resistors (RGMII-ID: both delays inside the PHY, FPGA aligned).
`timescale 1ns / 1ps
module phy_mgmt #(
    parameter [4:0]  PHY_ADDR      = 5'd1,
    parameter        TXDLY_EN      = 1,
    parameter        RXDLY_EN      = 1,
    parameter integer CLK_HZ       = 125_000_000,
    parameter integer SETTLE_MS    = 60,
    parameter integer POLL_MS      = 10,
    parameter integer MDC_HALF     = 25           // clk/(2*25) = 2.5 MHz @125 MHz
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        phy_rst_released,   // level: PHY reset de-asserted
    input  wire        auto_en,

    // host transaction
    input  wire        h_go,                // 1-cycle pulse
    input  wire        h_we,
    input  wire [4:0]  h_phy,
    input  wire [4:0]  h_reg,
    input  wire [15:0] h_wdata,
    output reg  [15:0] h_rdata,
    output wire        h_busy,
    output reg         h_done,              // sticky until next h_go

    output reg         init_done,
    output reg  [15:0] phy_id1,
    output reg         link_up,

    output wire        mdc,
    output wire        mdio_o,
    output wire        mdio_t,
    input  wire        mdio_i
);
    localparam integer SETTLE_CYC = (CLK_HZ / 1000) * SETTLE_MS;
    localparam integer POLL_CYC   = (CLK_HZ / 1000) * POLL_MS;

    reg         m_start, m_we;
    reg  [4:0]  m_phy, m_reg;
    reg  [15:0] m_wdata;
    wire [15:0] m_rdata;
    wire        m_busy, m_done;

    mdio_master #(.CLK_DIV_HALF(MDC_HALF)) u_mdio (
        .clk(clk), .rst_n(rst_n), .start(m_start), .we(m_we),
        .phy_addr(m_phy), .reg_addr(m_reg), .wdata(m_wdata), .rdata(m_rdata),
        .busy(m_busy), .done(m_done), .mdc(mdc), .mdio_o(mdio_o), .mdio_t(mdio_t), .mdio_i(mdio_i)
    );

    typedef enum logic [4:0] {
        S_WAIT_RST, S_SETTLE, S_ID_REQ, S_ID_WAIT,
        S_PG_REQ, S_PG_WAIT,
        S_TX_RD, S_TX_RDW, S_TX_WR, S_TX_WRW,
        S_RX_RD, S_RX_RDW, S_RX_WR, S_RX_WRW,
        S_PG0_REQ, S_PG0_WAIT,
        S_IDLE, S_HOST_WAIT, S_POLL_REQ, S_POLL_WAIT
    } st_t;
    st_t st;

    reg [31:0] tmr;
    reg        h_pend;
    reg        h_go_q;
    assign h_busy = h_pend | (st == S_HOST_WAIT);

    task automatic issue(input we, input [4:0] phy, input [4:0] rg, input [15:0] wd);
        begin
            m_start <= 1'b1; m_we <= we; m_phy <= phy; m_reg <= rg; m_wdata <= wd;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_WAIT_RST; tmr <= 32'd0; m_start <= 1'b0; m_we <= 1'b0; m_phy <= 5'd0; m_reg <= 5'd0;
            m_wdata <= 16'd0; h_rdata <= 16'd0; h_done <= 1'b0; init_done <= 1'b0; phy_id1 <= 16'd0;
            link_up <= 1'b0; h_pend <= 1'b0;
        end else begin
            m_start <= 1'b0;
            if (h_go) begin h_pend <= 1'b1; h_done <= 1'b0; end

            case (st)
            S_WAIT_RST: begin
                tmr <= 32'd0;
                init_done <= 1'b0;
                if (phy_rst_released) st <= S_SETTLE;
            end
            S_SETTLE: begin
                if (!phy_rst_released) st <= S_WAIT_RST;
                else if (tmr >= SETTLE_CYC) begin
                    tmr <= 32'd0;
                    st <= auto_en ? S_ID_REQ : S_IDLE;
                    if (!auto_en) init_done <= 1'b1;
                end else tmr <= tmr + 1'b1;
            end
            S_ID_REQ:  begin issue(1'b0, PHY_ADDR, 5'd2, 16'd0); st <= S_ID_WAIT; end
            S_ID_WAIT: if (m_done) begin phy_id1 <= m_rdata; st <= S_PG_REQ; end
            S_PG_REQ:  begin issue(1'b1, PHY_ADDR, 5'd31, 16'h0D08); st <= S_PG_WAIT; end
            S_PG_WAIT: if (m_done) st <= TXDLY_EN ? S_TX_RD : (RXDLY_EN ? S_RX_RD : S_PG0_REQ);
            S_TX_RD:   begin issue(1'b0, PHY_ADDR, 5'd17, 16'd0); st <= S_TX_RDW; end
            S_TX_RDW:  if (m_done) begin h_rdata <= m_rdata; st <= S_TX_WR; end
            S_TX_WR:   begin issue(1'b1, PHY_ADDR, 5'd17, h_rdata | 16'h0100); st <= S_TX_WRW; end
            S_TX_WRW:  if (m_done) st <= RXDLY_EN ? S_RX_RD : S_PG0_REQ;
            S_RX_RD:   begin issue(1'b0, PHY_ADDR, 5'd21, 16'd0); st <= S_RX_RDW; end
            S_RX_RDW:  if (m_done) begin h_rdata <= m_rdata; st <= S_RX_WR; end
            S_RX_WR:   begin issue(1'b1, PHY_ADDR, 5'd21, h_rdata | 16'h0008); st <= S_RX_WRW; end
            S_RX_WRW:  if (m_done) st <= S_PG0_REQ;
            S_PG0_REQ: begin issue(1'b1, PHY_ADDR, 5'd31, 16'h0000); st <= S_PG0_WAIT; end
            S_PG0_WAIT: if (m_done) begin init_done <= 1'b1; tmr <= 32'd0; st <= S_IDLE; end

            S_IDLE: begin
                if (!phy_rst_released) st <= S_WAIT_RST;
                else if (h_pend) begin
                    issue(h_we, h_phy, h_reg, h_wdata);
                    st <= S_HOST_WAIT;
                end else if (tmr >= POLL_CYC) begin
                    tmr <= 32'd0; st <= S_POLL_REQ;
                end else tmr <= tmr + 1'b1;
            end
            S_HOST_WAIT: if (m_done) begin
                h_rdata <= m_rdata; h_done <= 1'b1; h_pend <= 1'b0; st <= S_IDLE;
            end
            S_POLL_REQ:  begin issue(1'b0, PHY_ADDR, 5'd1, 16'd0); st <= S_POLL_WAIT; end
            S_POLL_WAIT: if (m_done) begin link_up <= m_rdata[2]; st <= S_IDLE; end
            default: st <= S_WAIT_RST;
            endcase
        end
    end
endmodule
