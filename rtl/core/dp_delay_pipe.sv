// dp_delay_pipe.sv — fixed-length shift register without reset.
// Maps to SRLC32E chains on 7-series (a 75-bit x 480 pipe is ~1.1k SRL LUTs,
// versus ~36k flip-flops when every stage carries an async reset).
`timescale 1ns / 1ps
module dp_delay_pipe #(
    parameter WIDTH = 75,
    parameter DEPTH = 480
) (
    input  logic             clk,
    input  logic             en,
    input  logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout
);
    (* shreg_extract = "yes" *) logic [WIDTH-1:0] sr [0:DEPTH-1];
    integer i;
    always_ff @(posedge clk) begin
        if (en) begin
            sr[0] <= din;
            for (i = 1; i < DEPTH; i = i + 1) sr[i] <= sr[i-1];
        end
    end
    assign dout = sr[DEPTH-1];
endmodule
