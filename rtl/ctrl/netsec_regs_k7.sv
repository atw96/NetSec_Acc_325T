// netsec_regs_k7.sv — AXI4-Lite register file for the MK7325FB NetSec accelerator.
// Everything here lives in the control clock domain (clk125). See docs/register_map.md.
//
//  0x000 ID  0x004 VERSION  0x008 CTRL  0x00C SCRATCH  0x010 STATUS  0x014 UPTIME_S  0x018 CONFIG
//  0x100.. 10G control/status     0x130 AES key   0x140 DPI patterns   0x180 per-port AES ciphertext
//  0x200.. copper (RGMII) control, MDIO, RX delay taps
//  0x300.. MMIO accelerators (AES block, RFC1071 checksum, 32-bit modexp)
//  0x400.. statistic counter windows (10G bank, copper bank)
`timescale 1ns / 1ps
module netsec_regs_k7 #(
    parameter [31:0] VERSION   = 32'h0001_0000,
    parameter [31:0] CONFIG_W  = 32'h0,
    parameter integer N10      = 128,
    parameter integer N1G      = 32,
    parameter [4:0]  PHYADDR_A = 5'd2,
    parameter [4:0]  PHYADDR_B = 5'd1,
    parameter [4:0]  DLY_A_INIT = 5'd0,   // reset value of 0x220, matches rgmii_mac IDELAY
    parameter [4:0]  DLY_B_INIT = 5'd0
) (
    input  wire         clk,
    input  wire         rst_n,

    // AXI4-Lite slave
    input  wire [11:0]  s_awaddr,  input wire s_awvalid, output wire s_awready,
    input  wire [31:0]  s_wdata,   input wire [3:0] s_wstrb, input wire s_wvalid, output wire s_wready,
    output reg  [1:0]   s_bresp,   output reg s_bvalid, input wire s_bready,
    input  wire [11:0]  s_araddr,  input wire s_arvalid, output wire s_arready,
    output reg  [31:0]  s_rdata,   output reg [1:0] s_rresp, output reg s_rvalid, input wire s_rready,

    // global
    output reg          ctrl_enable,
    output reg          soft_reset,            // 1-cycle pulse
    input  wire [15:0]  status_in,
    input  wire [31:0]  uptime_s,

    // 10G
    output reg  [1:0]   g10_mode,
    output reg  [3:0]   g10_dp_en,
    output reg  [3:0]   g10_aes_en,
    output reg  [3:0]   g10_gen_en,
    output reg  [15:0]  g10_gap,
    output reg          g10_gen_to_dp,
    output reg          g10_inj_mac,
    output reg  [3:0]   g10_inj_start,         // pulses
    output reg  [3:0]   g10_tx_dis,
    output reg  [7:0]   g10_rs,
    output reg          g10_gt_reset,          // pulse
    output reg  [127:0] aes_key,
    output reg  [511:0] pats,
    input  wire [15:0]  g10_status_in,
    input  wire [7:0]   g10_last_in,
    input  wire [3:0]   g10_aes_done_in,       // pulses (sticky here)
    input  wire [511:0] g10_aes_ct_in,

    // copper
    output reg  [1:0]   cu_mode,
    output reg  [1:0]   cu_aes_en,
    output reg          cu_gen_start,          // pulse
    input  wire [15:0]  cu_status_in,
    input  wire [3:0]   cu_last_in,
    input  wire [255:0] cu_aes_ct_in,          // {B,A}
    input  wire [1:0]   cu_aes_done_in,
    output reg          mdio_go,               // pulse
    output reg          mdio_we,
    output reg          mdio_port,
    output wire [4:0]   mdio_reg,
    output wire [4:0]   mdio_phy,
    output wire [15:0]  mdio_wdata,
    input  wire [15:0]  mdio_rdata_in,
    input  wire         mdio_busy_in,
    input  wire         mdio_done_in,
    output reg  [4:0]   dly_tap_a,
    output reg  [4:0]   dly_tap_b,
    output reg          dly_load_a,            // pulses
    output reg          dly_load_b,
    output reg          phy_rst_force,
    output reg          phy_auto_en,
    input  wire [15:0]  phy_status_in,         // {idB[..],...} see map
    input  wire [15:0]  phy_id_a_in,
    input  wire [15:0]  phy_id_b_in,

    // statistics windows
    output reg  [7:0]   s10_idx,  output reg s10_snap, output reg s10_clr,
    input  wire [31:0]  s10_val,  input wire s10_done,
    output reg  [7:0]   s1g_idx,  output reg s1g_snap, output reg s1g_clr,
    input  wire [31:0]  s1g_val,  input wire s1g_done
);
    // ------------------------------------------------------------------ AXI-Lite
    reg        aw_got, w_got;
    reg [11:0] waddr;
    reg [31:0] wdat;
    reg [3:0]  wstr;
    assign s_awready = !aw_got && !s_bvalid;
    assign s_wready  = !w_got  && !s_bvalid;
    wire do_write = aw_got && w_got && !s_bvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_got <= 1'b0; w_got <= 1'b0; waddr <= 12'd0; wdat <= 32'd0; wstr <= 4'd0;
            s_bvalid <= 1'b0; s_bresp <= 2'b00;
        end else begin
            if (s_awvalid && s_awready) begin aw_got <= 1'b1; waddr <= s_awaddr; end
            if (s_wvalid  && s_wready)  begin w_got  <= 1'b1; wdat  <= s_wdata; wstr <= s_wstrb; end
            if (do_write) begin aw_got <= 1'b0; w_got <= 1'b0; s_bvalid <= 1'b1; s_bresp <= 2'b00; end
            else if (s_bvalid && s_bready) s_bvalid <= 1'b0;
        end
    end

    function automatic [31:0] mrg(input [31:0] old, input [31:0] nw, input [3:0] st);
        mrg = { st[3] ? nw[31:24] : old[31:24], st[2] ? nw[23:16] : old[23:16],
                st[1] ? nw[15:8]  : old[15:8],  st[0] ? nw[7:0]   : old[7:0] };
    endfunction

    // ------------------------------------------------------------------ state
    reg [31:0] scratch;
    reg [15:0] mdio_wd_r;
    reg [4:0]  mdio_reg_r, mdio_phy_r_a, mdio_phy_r_b;
    reg        mdio_phy_ovr;
    reg [4:0]  mdio_phy_user;
    reg        mdio_done_s;
    reg [3:0]  g10_aes_done_s;
    reg [1:0]  cu_aes_done_s;

    assign mdio_reg   = mdio_reg_r;
    assign mdio_wdata = mdio_wd_r;
    assign mdio_phy   = mdio_phy_ovr ? mdio_phy_user : (mdio_port ? PHYADDR_B : PHYADDR_A);

    // MMIO accelerators
    reg  [127:0] aes_pt;
    reg          aes_start, csum_start, csum_dv, csum_last, mx_start;
    reg  [15:0]  csum_data;
    reg  [31:0]  mx_base, mx_exp, mx_mod;
    wire         aes_done_w, csum_valid_w, mx_done_w;
    wire [127:0] aes_ct_w;
    wire [15:0]  csum_res_w;
    wire [31:0]  mx_res_w;
    reg          aes_done_s, csum_valid_s, mx_done_s;
    reg  [1:0]   aes_blank, csum_blank, mx_blank;

    u_aes128_core u_aes (.clk(clk), .rst_n(rst_n), .start(aes_start), .key(aes_key), .plaintext(aes_pt),
                         .done(aes_done_w), .ciphertext(aes_ct_w));
    u_checksum_rfc1071 u_csum (.clk(clk), .rst_n(rst_n), .start(csum_start), .data_valid(csum_dv),
                         .data(csum_data), .data_last(csum_last), .checksum_valid(csum_valid_w), .checksum(csum_res_w));
    u_modexp_demo #(.WIDTH(32)) u_mx (.clk(clk), .rst_n(rst_n), .start(mx_start), .base_in(mx_base),
                         .exp_in(mx_exp), .mod_in(mx_mod), .done(mx_done_w), .result(mx_res_w));

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_enable <= 1'b1; soft_reset <= 1'b0; scratch <= 32'd0;
            g10_mode <= 2'd0; g10_dp_en <= 4'hF; g10_aes_en <= 4'd0; g10_gen_en <= 4'd0; g10_gap <= 16'd8;
            g10_gen_to_dp <= 1'b0; g10_inj_mac <= 1'b0; g10_inj_start <= 4'd0; g10_tx_dis <= 4'd0;
            g10_rs <= 8'hFF; g10_gt_reset <= 1'b0; aes_key <= 128'd0; pats <= 512'd0;
            pats[31:0] <= 32'h47455420;                       // "GET "
            g10_aes_done_s <= 4'd0; cu_aes_done_s <= 2'd0;
            cu_mode <= 2'd0; cu_aes_en <= 2'd0; cu_gen_start <= 1'b0;
            mdio_go <= 1'b0; mdio_we <= 1'b0; mdio_port <= 1'b0; mdio_reg_r <= 5'd0; mdio_wd_r <= 16'd0;
            mdio_phy_ovr <= 1'b0; mdio_phy_user <= 5'd0; mdio_done_s <= 1'b0;
            dly_tap_a <= DLY_A_INIT; dly_tap_b <= DLY_B_INIT; dly_load_a <= 1'b0; dly_load_b <= 1'b0;
            phy_rst_force <= 1'b0; phy_auto_en <= 1'b1;
            s10_idx <= 8'd0; s10_snap <= 1'b0; s10_clr <= 1'b0; s1g_idx <= 8'd0; s1g_snap <= 1'b0; s1g_clr <= 1'b0;
            aes_pt <= 128'd0; aes_start <= 1'b0; csum_start <= 1'b0; csum_dv <= 1'b0; csum_last <= 1'b0; csum_data <= 16'd0;
            mx_start <= 1'b0; mx_base <= 32'd0; mx_exp <= 32'd0; mx_mod <= 32'd1;
            aes_done_s <= 1'b0; csum_valid_s <= 1'b0; mx_done_s <= 1'b0; aes_blank <= 2'd0; csum_blank <= 2'd0; mx_blank <= 2'd0;
        end else begin
            // default pulse clears
            soft_reset <= 1'b0; g10_inj_start <= 4'd0; g10_gt_reset <= 1'b0; cu_gen_start <= 1'b0;
            mdio_go <= 1'b0; dly_load_a <= 1'b0; dly_load_b <= 1'b0;
            s10_snap <= 1'b0; s10_clr <= 1'b0; s1g_snap <= 1'b0; s1g_clr <= 1'b0;
            aes_start <= 1'b0; csum_start <= 1'b0; csum_dv <= 1'b0; mx_start <= 1'b0;
            if (aes_blank  != 0) aes_blank  <= aes_blank  - 1'b1;
            if (csum_blank != 0) csum_blank <= csum_blank - 1'b1;
            if (mx_blank   != 0) mx_blank   <= mx_blank   - 1'b1;

            // sticky completion flags
            g10_aes_done_s <= g10_aes_done_s | g10_aes_done_in;
            cu_aes_done_s  <= cu_aes_done_s  | cu_aes_done_in;
            if (mdio_done_in) mdio_done_s <= 1'b1;
            if (aes_done_w   && aes_blank  == 0) aes_done_s   <= 1'b1;
            if (csum_valid_w && csum_blank == 0) csum_valid_s <= 1'b1;
            if (mx_done_w    && mx_blank   == 0) mx_done_s    <= 1'b1;

            if (do_write) begin
                case (waddr[11:2])
                10'h002: if (wstr[0]) begin ctrl_enable <= wdat[0]; if (wdat[1]) soft_reset <= 1'b1; end
                10'h003: scratch <= mrg(scratch, wdat, wstr);
                // ---- 10G
                10'h040: if (wstr[0]) g10_mode <= wdat[1:0];
                10'h041: if (wstr[0]) g10_dp_en  <= wdat[3:0];
                10'h042: if (wstr[0]) g10_aes_en <= wdat[3:0];
                10'h043: if (wstr[0]) g10_gen_en <= wdat[3:0];
                10'h044: begin if (wstr[0]) g10_gap[7:0] <= wdat[7:0]; if (wstr[1]) g10_gap[15:8] <= wdat[15:8]; end
                10'h045: if (wstr[0]) begin g10_gen_to_dp <= wdat[0]; g10_inj_mac <= wdat[1]; end
                10'h046: if (wstr[0]) g10_inj_start <= wdat[3:0];
                10'h047: begin if (wstr[0]) g10_tx_dis <= wdat[3:0]; if (wstr[1]) g10_rs <= wdat[15:8]; end
                10'h04A: if (wstr[0]) g10_aes_done_s <= g10_aes_done_s & ~wdat[3:0];     // W1C
                10'h04B: if (wstr[0] && wdat[0]) g10_gt_reset <= 1'b1;
                10'h04C: aes_key[127:96] <= mrg(aes_key[127:96], wdat, wstr);
                10'h04D: aes_key[95:64]  <= mrg(aes_key[95:64],  wdat, wstr);
                10'h04E: aes_key[63:32]  <= mrg(aes_key[63:32],  wdat, wstr);
                10'h04F: aes_key[31:0]   <= mrg(aes_key[31:0],   wdat, wstr);
                // ---- copper
                10'h080: if (wstr[0]) cu_mode <= wdat[1:0];
                10'h081: begin if (wstr[0]) begin cu_aes_en <= wdat[1:0]; if (wdat[8]) cu_gen_start <= 1'b1; end end
                10'h084: begin if (wstr[0]) begin mdio_we <= wdat[1]; mdio_port <= wdat[2]; mdio_phy_ovr <= wdat[3];
                                if (wdat[0]) begin mdio_go <= 1'b1; mdio_done_s <= 1'b0; end
                                if (wdat[9]) mdio_done_s <= 1'b0; end end
                10'h085: begin if (wstr[0]) mdio_reg_r <= wdat[4:0]; if (wstr[1]) mdio_phy_user <= wdat[12:8]; end
                10'h086: begin if (wstr[0]) mdio_wd_r[7:0] <= wdat[7:0]; if (wstr[1]) mdio_wd_r[15:8] <= wdat[15:8]; end
                10'h08E: if (wstr[0]) cu_aes_done_s <= cu_aes_done_s & ~wdat[1:0];            // W1C
                10'h088: begin if (wstr[0]) dly_tap_a <= wdat[4:0]; if (wstr[1] && wdat[8]) dly_load_a <= 1'b1; end
                10'h089: begin if (wstr[0]) dly_tap_b <= wdat[4:0]; if (wstr[1] && wdat[8]) dly_load_b <= 1'b1; end
                10'h08A: if (wstr[0]) begin phy_rst_force <= wdat[0]; phy_auto_en <= wdat[1]; end
                // ---- MMIO accelerators
                10'h0C0: if (wstr[0]) begin
                            if (wdat[0]) begin aes_start <= 1'b1; aes_done_s <= 1'b0; aes_blank <= 2'd2; end
                            if (wdat[1]) begin csum_start <= 1'b1; csum_valid_s <= 1'b0; csum_blank <= 2'd2; end
                            if (wdat[2]) begin mx_start <= 1'b1; mx_done_s <= 1'b0; mx_blank <= 2'd2; end
                         end
                10'h0C4: aes_pt[127:96] <= mrg(aes_pt[127:96], wdat, wstr);
                10'h0C5: aes_pt[95:64]  <= mrg(aes_pt[95:64],  wdat, wstr);
                10'h0C6: aes_pt[63:32]  <= mrg(aes_pt[63:32],  wdat, wstr);
                10'h0C7: aes_pt[31:0]   <= mrg(aes_pt[31:0],   wdat, wstr);
                10'h0CC: begin csum_data <= wdat[15:0]; csum_last <= wdat[16]; csum_dv <= 1'b1; end
                10'h0D0: mx_base <= mrg(mx_base, wdat, wstr);
                10'h0D1: mx_exp  <= mrg(mx_exp,  wdat, wstr);
                10'h0D2: mx_mod  <= mrg(mx_mod,  wdat, wstr);
                // ---- stats
                10'h100: begin s10_idx <= wdat[7:0]; s10_snap <= 1'b1; end
                10'h102: if (wstr[0] && wdat[0]) s10_clr <= 1'b1;
                10'h104: begin s1g_idx <= wdat[7:0]; s1g_snap <= 1'b1; end
                10'h106: if (wstr[0] && wdat[0]) s1g_clr <= 1'b1;
                default: begin
                    // DPI patterns 0x140..0x17C, word i = pats[i*32 +: 32]
                    if (waddr[11:2] >= 10'h050 && waddr[11:2] < 10'h060)
                        for (k = 0; k < 16; k = k + 1)
                            if (waddr[5:2] == k[3:0]) pats[k*32 +: 32] <= mrg(pats[k*32 +: 32], wdat, wstr);
                end
                endcase
            end
        end
    end

    // ------------------------------------------------------------------ reads
    reg ar_busy;
    assign s_arready = !s_rvalid && !ar_busy;
    reg [11:0] raddr;
    reg [31:0] rd;

    function automatic [31:0] ct_word(input [511:0] v, input [1:0] port, input [1:0] w);
        reg [127:0] blk;
        begin
            blk = v[port*128 +: 128];
            ct_word = blk[(3-w)*32 +: 32];
        end
    endfunction
    function automatic [31:0] cu_ct_word(input [255:0] v, input port, input [1:0] w);
        reg [127:0] blk;
        begin
            blk = v[port*128 +: 128];
            cu_ct_word = blk[(3-w)*32 +: 32];
        end
    endfunction

    always @* begin
        rd = 32'd0;
        case (raddr[11:2])
        10'h000: rd = 32'h4B37_3235;                       // "K725"
        10'h001: rd = VERSION;
        10'h002: rd = {31'd0, ctrl_enable};
        10'h003: rd = scratch;
        10'h004: rd = {16'd0, status_in};
        10'h005: rd = uptime_s;
        10'h006: rd = CONFIG_W;
        10'h040: rd = {30'd0, g10_mode};
        10'h041: rd = {28'd0, g10_dp_en};
        10'h042: rd = {28'd0, g10_aes_en};
        10'h043: rd = {28'd0, g10_gen_en};
        10'h044: rd = {16'd0, g10_gap};
        10'h045: rd = {30'd0, g10_inj_mac, g10_gen_to_dp};
        10'h046: rd = 32'd0;
        10'h047: rd = {16'd0, g10_rs, 4'd0, g10_tx_dis};
        10'h048: rd = {16'd0, g10_status_in};
        10'h049: rd = {24'd0, g10_last_in};
        10'h04A: rd = {28'd0, g10_aes_done_s};
        10'h04C: rd = aes_key[127:96];
        10'h04D: rd = aes_key[95:64];
        10'h04E: rd = aes_key[63:32];
        10'h04F: rd = aes_key[31:0];
        10'h080: rd = {30'd0, cu_mode};
        10'h081: rd = {30'd0, cu_aes_en};
        10'h082: rd = {16'd0, cu_status_in};
        10'h083: rd = {28'd0, cu_last_in};
        10'h084: rd = {22'd0, mdio_done_s, mdio_busy_in, 4'd0, mdio_phy_ovr, mdio_port, mdio_we, 1'b0};
        10'h085: rd = {19'd0, mdio_phy_user, 3'd0, mdio_reg_r};
        10'h086: rd = {16'd0, mdio_wd_r};
        10'h087: rd = {16'd0, mdio_rdata_in};
        10'h088: rd = {27'd0, dly_tap_a};
        10'h089: rd = {27'd0, dly_tap_b};
        10'h08A: rd = {30'd0, phy_auto_en, phy_rst_force};
        10'h08B: rd = {16'd0, phy_status_in};
        10'h08C: rd = {16'd0, phy_id_a_in};
        10'h08D: rd = {16'd0, phy_id_b_in};
        10'h08E: rd = {30'd0, cu_aes_done_s};
        10'h0C0: rd = {29'd0, mx_done_s, csum_valid_s, aes_done_s};
        10'h0C4: rd = aes_pt[127:96];
        10'h0C5: rd = aes_pt[95:64];
        10'h0C6: rd = aes_pt[63:32];
        10'h0C7: rd = aes_pt[31:0];
        10'h0C8: rd = aes_ct_w[127:96];
        10'h0C9: rd = aes_ct_w[95:64];
        10'h0CA: rd = aes_ct_w[63:32];
        10'h0CB: rd = aes_ct_w[31:0];
        10'h0CD: rd = {16'd0, csum_res_w};
        10'h0D0: rd = mx_base;
        10'h0D1: rd = mx_exp;
        10'h0D2: rd = mx_mod;
        10'h0D3: rd = mx_res_w;
        10'h100: rd = {31'd0, s10_done};
        10'h101: rd = s10_val;
        10'h103: rd = N10;
        10'h104: rd = {31'd0, s1g_done};
        10'h105: rd = s1g_val;
        10'h107: rd = N1G;
        default: begin
            if (raddr[11:2] >= 10'h050 && raddr[11:2] < 10'h060)
                rd = pats[raddr[5:2]*32 +: 32];
            else if (raddr[11:2] >= 10'h060 && raddr[11:2] < 10'h070)       // 0x180..0x1BC  10G ct, port = [5:4], word = [3:2]
                rd = ct_word(g10_aes_ct_in, raddr[5:4], raddr[3:2]);
            else if (raddr[11:2] >= 10'h090 && raddr[11:2] < 10'h098)       // 0x240..0x25C  copper ct, port = [4], word=[3:2]
                rd = cu_ct_word(cu_aes_ct_in, raddr[4], raddr[3:2]);
        end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_rvalid <= 1'b0; s_rdata <= 32'd0; s_rresp <= 2'b00; ar_busy <= 1'b0; raddr <= 12'd0;
        end else begin
            if (s_arvalid && s_arready) begin raddr <= s_araddr; ar_busy <= 1'b1; end
            else if (ar_busy) begin s_rdata <= rd; s_rvalid <= 1'b1; ar_busy <= 1'b0; end
            if (s_rvalid && s_rready) s_rvalid <= 1'b0;
        end
    end
endmodule
