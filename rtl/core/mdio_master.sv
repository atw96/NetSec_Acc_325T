// mdio_master.sv — IEEE 802.3 Clause 22 MDIO master.
// MDC = clk / (2*CLK_DIV_HALF). At 125 MHz with CLK_DIV_HALF=50, MDC is 1.25 MHz
// (400 ns of setup). The PHY samples MDIO on the rising edge of MDC and drives
// read data up to 300 ns after that edge, so:
//   * the master changes MDIO on the falling edge (mdc_q 1 -> 0)
//   * the master samples read data on the rising edge (mdc_q 0 -> 1)
// mdio_i is synchronized before use. The sample is taken from the synchronizer
// on the clock that launches the rising edge, i.e. a couple of clocks before the
// pin edge, when the bit driven after the previous rising edge is already stable.
`timescale 1ns / 1ps

module mdio_master #(
    parameter int CLK_DIV_HALF = 50
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start,
    input  logic        we,           // 1 = write, 0 = read
    input  logic [4:0]  phy_addr,
    input  logic [4:0]  reg_addr,
    input  logic [15:0] wdata,
    output logic [15:0] rdata,
    output logic        busy,
    output logic        done,         // 1-cycle pulse

    output logic        mdc,
    output logic        mdio_o,
    output logic        mdio_t,       // 1 = tristate (input)
    input  logic        mdio_i
);

    typedef enum logic [1:0] { ST_IDLE, ST_RUN, ST_DONE } state_t;
    state_t state;

    logic [5:0]  bit_idx;     // 63 .. 0, MSB first
    logic [6:0]  div_cnt;
    logic        mdc_q;
    logic        we_r;
    logic [63:0] shreg;
    logic [15:0] racc;
    logic        mdio_s0, mdio_s1;
    logic        finish;       // last rising edge has happened; drop MDC then finish

    assign mdc  = (state == ST_RUN) ? mdc_q : 1'b0;
    assign busy = (state != ST_IDLE);

    // Drive preamble/ST/OP/PHY/REG, and for a write the TA+DATA as well.
    // A read releases the bus at the first TA bit (bit 17).
    wire drive_en = we_r ? 1'b1 : (bit_idx >= 6'd18);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mdio_s0 <= 1'b1;
            mdio_s1 <= 1'b1;
        end else begin
            mdio_s0 <= mdio_i;
            mdio_s1 <= mdio_s0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_IDLE;
            bit_idx <= '0;
            div_cnt <= '0;
            mdc_q   <= 1'b0;
            we_r    <= 1'b0;
            shreg   <= '0;
            rdata   <= '0;
            racc    <= '0;
            done    <= 1'b0;
            mdio_o  <= 1'b1;
            mdio_t  <= 1'b1;
            finish  <= 1'b0;
        end else begin
            done <= 1'b0;

            unique case (state)
                ST_IDLE: begin
                    mdc_q   <= 1'b0;
                    mdio_t  <= 1'b1;
                    mdio_o  <= 1'b1;
                    div_cnt <= '0;
                    bit_idx <= 6'd63;
                    finish  <= 1'b0;
                    if (start) begin
                        we_r <= we;
                        // {preamble[31:0]=1, ST=01, OP, PHYAD, REGAD, TA, DATA}
                        if (we)
                            shreg <= {32'hFFFF_FFFF, 2'b01, 2'b01, phy_addr, reg_addr, 2'b10, wdata};
                        else
                            shreg <= {32'hFFFF_FFFF, 2'b01, 2'b10, phy_addr, reg_addr, 2'b00, 16'h0000};
                        racc    <= '0;
                        // bit 63 is a preamble one; drive it before the first rising edge
                        mdio_o  <= 1'b1;
                        mdio_t  <= 1'b0;
                        state   <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (div_cnt == CLK_DIV_HALF[6:0] - 7'd1) begin
                        div_cnt <= '0;
                        mdc_q   <= ~mdc_q;
                        if (mdc_q) begin
                            // falling edge. After the last bit, just end — do not launch another one.
                            if (finish)
                                state <= ST_DONE;
                            else begin
                                mdio_o <= shreg[bit_idx];
                                mdio_t <= ~drive_en;
                            end
                        end else begin
                            // rising edge: capture the bit launched on the previous falling edge.
                            // Stay in ST_RUN so this rising edge actually reaches the pin.
                            if (!we_r && (bit_idx <= 6'd15))
                                racc <= {racc[14:0], mdio_s1};
                            if (bit_idx == 6'd0)
                                finish <= 1'b1;
                            else
                                bit_idx <= bit_idx - 1'b1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                ST_DONE: begin
                    mdc_q  <= 1'b0;
                    mdio_t <= 1'b1;
                    if (!we_r)
                        rdata <= racc;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
