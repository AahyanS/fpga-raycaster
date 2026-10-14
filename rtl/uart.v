// uart.v -- 8N1 UART transmitter and receiver.
//
// The Basys 3's USB port is an FTDI FT2232 chip: one channel does JTAG
// programming, the other is a USB-serial port wired to FPGA pins. Both run
// over the same cable, so this is how the board talks to the laptop.
//
// CLKS_PER_BIT = 100 MHz / baud. 33 gives 3.03 Mbaud, within 1% of the
// FTDI's 3 Mbaud rate (well inside the ~4% UART tolerance).

module uart_tx #(
    parameter CLKS_PER_BIT = 33
) (
    input  wire       clk,
    input  wire       start,     // pulse with `data` while ready
    input  wire [7:0] data,
    output wire       ready,
    output reg        tx = 1'b1
);
    reg [9:0] shift = 10'h3FF;   // {stop, data[7:0], start}
    reg [3:0] bits  = 4'd0;      // bits left to send
    reg [7:0] cnt   = 8'd0;

    assign ready = (bits == 4'd0);

    always @(posedge clk) begin
        if (ready) begin
            if (start) begin
                shift <= {1'b1, data, 1'b0};
                bits  <= 4'd10;
                cnt   <= CLKS_PER_BIT - 1;
                tx    <= 1'b0;               // start bit goes out now
            end
        end else if (cnt != 8'd0) begin
            cnt <= cnt - 8'd1;
        end else begin
            shift <= {1'b1, shift[9:1]};
            tx    <= shift[1];
            bits  <= bits - 4'd1;
            cnt   <= CLKS_PER_BIT - 1;
            if (bits == 4'd1) tx <= 1'b1;    // idle after stop bit
        end
    end
endmodule

module uart_rx #(
    parameter CLKS_PER_BIT = 33
) (
    input  wire       clk,
    input  wire       rx,
    output reg        valid = 1'b0,  // one-cycle pulse
    output reg  [7:0] data  = 8'd0
);
    reg       m = 1'b1, s = 1'b1;    // 2-flop synchronizer
    reg [1:0] st  = 2'd0;
    reg [7:0] cnt = 8'd0;
    reg [2:0] idx = 3'd0;
    reg [7:0] sh  = 8'd0;

    always @(posedge clk) begin
        m <= rx;
        s <= m;
        valid <= 1'b0;
        case (st)
        2'd0: if (!s) begin                      // start bit edge
            cnt <= CLKS_PER_BIT / 2;
            st  <= 2'd1;
        end
        2'd1: if (cnt != 0) cnt <= cnt - 8'd1;   // middle of start bit
              else if (!s) begin cnt <= CLKS_PER_BIT - 1; idx <= 3'd0; st <= 2'd2; end
              else st <= 2'd0;                   // glitch
        2'd2: if (cnt != 0) cnt <= cnt - 8'd1;
              else begin
                  sh  <= {s, sh[7:1]};
                  cnt <= CLKS_PER_BIT - 1;
                  if (idx == 3'd7) st <= 2'd3;
                  idx <= idx + 3'd1;
              end
        2'd3: if (cnt != 0) cnt <= cnt - 8'd1;   // stop bit
              else begin
                  if (s) begin valid <= 1'b1; data <= sh; end
                  st <= 2'd0;
              end
        endcase
    end
endmodule
