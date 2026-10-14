// tb_udiv.v -- self-checking randomized test of the serial divider.
`timescale 1ns/1ps
module tb_udiv;
    reg clk = 0; always #5 clk = ~clk;
    reg start = 0; reg [47:0] n; reg [31:0] d;
    wire done; wire [47:0] q;
    udiv #(.N(48), .D(32)) dut (.clk(clk), .start(start), .dividend(n), .divisor(d), .done(done), .quotient(q));
    integer i, errors = 0;
    reg [47:0] expect;
    initial begin
        for (i = 0; i < 2000; i = i + 1) begin
            n = {$random, $random} >> ($unsigned($random) % 40);
            d = $random >> ($unsigned($random) % 31);
            if (i == 0) d = 0;                       // divide-by-zero case
            expect = (d == 0) ? {48{1'b1}} : n / d;
            @(negedge clk) start = 1; @(negedge clk) start = 0;
            @(posedge done); #1;
            if (q !== expect) begin
                errors = errors + 1;
                if (errors < 5) $display("FAIL %0d / %0d = %0d, got %0d", n, d, expect, q);
            end
        end
        $display("udiv: %0d vectors, %0d errors -> %s", i, errors, errors ? "FAIL" : "PASS");
        $finish;
    end
endmodule
