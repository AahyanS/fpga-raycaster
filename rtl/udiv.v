// udiv.v -- sequential unsigned restoring divider.
//
// One quotient bit per clock: N cycles per divide. Pulse `start` for one
// cycle; `done` pulses one cycle when `quotient` is valid. Division by zero
// returns all ones, which callers treat as "infinity" and clamp.
//
// Trading time for area like this is the classic FPGA move: a combinational
// 48-bit divider would be huge and slow, but the ray engine has ~2,600 clock
// cycles per screen column to spare, so a serial divider costs almost nothing.
module udiv #(
    parameter N = 48,   // dividend / quotient width
    parameter D = 32    // divisor width
) (
    input  wire         clk,
    input  wire         start,
    input  wire [N-1:0] dividend,
    input  wire [D-1:0] divisor,
    output reg          done = 1'b0,
    output wire [N-1:0] quotient
);
    reg [N-1:0] q    = {N{1'b0}};
    reg [D:0]   r    = {(D+1){1'b0}};
    reg [7:0]   cnt  = 8'd0;
    reg         busy = 1'b0;

    wire [D:0] shifted = {r[D-1:0], q[N-1]};
    wire       fits    = shifted >= {1'b0, divisor};

    assign quotient = q;

    always @(posedge clk) begin
        done <= 1'b0;
        if (start) begin
            q    <= dividend;
            r    <= {(D+1){1'b0}};
            cnt  <= N[7:0];
            busy <= 1'b1;
        end else if (busy) begin
            r   <= fits ? (shifted - {1'b0, divisor}) : shifted;
            q   <= {q[N-2:0], fits};
            cnt <= cnt - 8'd1;
            if (cnt == 8'd1) begin
                busy <= 1'b0;
                done <= 1'b1;
            end
        end
    end
endmodule
