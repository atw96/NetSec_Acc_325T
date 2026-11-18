// stat_bank.sv — N free-running 32-bit event counters in the source clock domain,
// read from the control clock domain through a request/ack snapshot handshake.
//   ctl side : idx + snap_req (1-cycle pulse)  ->  val valid when done=1
//   clr_req  : 1-cycle pulse clears every counter
// Works unchanged when src_clk == ctl_clk.
`timescale 1ns / 1ps
module stat_bank #(
    parameter N = 128
) (
    input  wire         src_clk,
    input  wire         src_rst_n,
    input  wire [N-1:0] pulse,

    input  wire         ctl_clk,
    input  wire         ctl_rst_n,
    input  wire [7:0]   idx,
    input  wire         snap_req,
    input  wire         clr_req,
    output reg  [31:0]  val,
    output reg          done
);
    localparam G = (N + 15) / 16;

    // ---------------- source domain ----------------
    reg [31:0] cnt [0:N-1];
    reg        clr_s1, clr_s2, clr_s3;
    reg        req_s1, req_s2, req_s3;
    reg  [7:0] idx_l;
    reg [31:0] grp [0:G-1];
    reg [31:0] val_s;
    reg  [2:0] st;
    reg        ack_tog;

    reg        clr_tog_c, req_tog_c;
    reg  [7:0] idx_c;

    integer i, g;
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            clr_s1 <= 1'b0; clr_s2 <= 1'b0; clr_s3 <= 1'b0;
            req_s1 <= 1'b0; req_s2 <= 1'b0; req_s3 <= 1'b0;
            st <= 3'd0; ack_tog <= 1'b0; idx_l <= 8'd0; val_s <= 32'd0;
            for (i = 0; i < N; i = i + 1) cnt[i] <= 32'd0;
            for (g = 0; g < G; g = g + 1) grp[g] <= 32'd0;
        end else begin
            clr_s1 <= clr_tog_c; clr_s2 <= clr_s1; clr_s3 <= clr_s2;
            req_s1 <= req_tog_c; req_s2 <= req_s1; req_s3 <= req_s2;
            for (i = 0; i < N; i = i + 1) begin
                if (clr_s2 ^ clr_s3) cnt[i] <= 32'd0;
                else if (pulse[i])   cnt[i] <= cnt[i] + 1'b1;
            end
            // two-stage select pipeline; val_s is frozen outside a request so the
            // control domain can capture it without tearing
            if (st == 3'd1)
                for (g = 0; g < G; g = g + 1)
                    grp[g] <= ((g*16 + idx_l[3:0]) < N) ? cnt[g*16 + idx_l[3:0]] : 32'd0;
            if (st == 3'd2)
                val_s <= grp[idx_l[7:4] < G ? idx_l[7:4] : 0];
            case (st)
                3'd0: if (req_s2 ^ req_s3) begin idx_l <= idx_c; st <= 3'd1; end
                3'd1: st <= 3'd2;
                3'd2: st <= 3'd3;
                3'd3: st <= 3'd4;
                3'd4: begin ack_tog <= ~ack_tog; st <= 3'd0; end
                default: st <= 3'd0;
            endcase
        end
    end

    // ---------------- control domain ----------------
    reg ack_c1, ack_c2, ack_c3;
    always @(posedge ctl_clk or negedge ctl_rst_n) begin
        if (!ctl_rst_n) begin
            clr_tog_c <= 1'b0; req_tog_c <= 1'b0; idx_c <= 8'd0;
            ack_c1 <= 1'b0; ack_c2 <= 1'b0; ack_c3 <= 1'b0; val <= 32'd0; done <= 1'b1;
        end else begin
            ack_c1 <= ack_tog; ack_c2 <= ack_c1; ack_c3 <= ack_c2;
            if (clr_req)  clr_tog_c <= ~clr_tog_c;
            if (snap_req) begin idx_c <= idx; req_tog_c <= ~req_tog_c; done <= 1'b0; end
            if (ack_c2 ^ ack_c3) begin val <= val_s; done <= 1'b1; end
        end
    end
endmodule
