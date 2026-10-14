// frame_streamer.v -- sends the rendered picture to the laptop over USB-serial.
//
// The serial link carries ~300 KB/s, far less than live 640x480 video
// (18 MB/s), so the streamer grabs every 4th pixel of every 4th line: a
// 160x120 image in 8-bit RRRGGGBB color, 19,200 bytes per frame.
//
//   WAIT  -> wait for the top-left pixel of a new frame
//   GRAB  -> copy the subsampled pixels into block RAM during one frame scan
//   SYNC  -> send the 0xFF frame marker
//   SEND  -> send 19,200 pixel bytes  (~64 ms at 3 Mbaud)
//   back to WAIT  ->  about 12 frames per second on the laptop
//
// Grabbing a whole frame before sending means the picture never tears.
// Pixel value 0xFF is reserved for the marker (white is sent as 0xFE),
// so the viewer can always find the start of a frame.
module frame_streamer #(
    parameter CLKS_PER_BIT = 33
) (
    input  wire        clk,
    input  wire        pix_en,
    input  wire [9:0]  hc,
    input  wire [9:0]  vc,
    input  wire [11:0] rgb,      // pixel that goes out for (hc, vc) this pix_en
    output wire        tx
);
    localparam NPIX = 160 * 120;

    localparam S_WAIT = 3'd0, S_GRAB = 3'd1, S_SYNC = 3'd2,
               S_READ = 3'd3, S_DATA = 3'd4, S_TX = 3'd5, S_GAP = 3'd6;

    (* ram_style = "block" *) reg [7:0] fb [0:NPIX-1];

    reg [2:0]  st = S_WAIT;
    reg [14:0] waddr = 15'd0, raddr = 15'd0;
    reg [7:0]  q = 8'd0;

    reg        tx_start = 1'b0;
    reg [7:0]  tx_data = 8'd0;
    wire       tx_ready;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .start(tx_start), .data(tx_data), .ready(tx_ready), .tx(tx)
    );

    wire [7:0] px8  = {rgb[11:9], rgb[7:5], rgb[3:2]};
    wire [7:0] px   = (px8 == 8'hFF) ? 8'hFE : px8;
    wire       take = pix_en && (hc[1:0] == 2'd0) && (vc[1:0] == 2'd0) &&
                      (hc < 10'd640) && (vc < 10'd480);

    // Block RAM: one write port (grab), one registered read port (send).
    always @(posedge clk) begin
        if (st == S_GRAB && take) fb[waddr] <= px;
        q <= fb[raddr];
    end

    always @(posedge clk) begin
        tx_start <= 1'b0;
        case (st)
        // Arm on the very last counter position of a frame, so that GRAB
        // is active for the (0,0) pixel of the next one.
        S_WAIT: if (pix_en && hc == 10'd799 && vc == 10'd524) begin
            waddr <= 15'd0;
            st    <= S_GRAB;
        end
        S_GRAB: begin
            if (take) begin
                waddr <= waddr + 15'd1;
                if (waddr == NPIX - 1) st <= S_SYNC;
            end
        end
        S_SYNC: if (tx_ready) begin
            tx_data  <= 8'hFF;
            tx_start <= 1'b1;
            raddr    <= 15'd0;
            st       <= S_GAP;
        end
        S_GAP:  st <= S_READ;              // let the UART leave `ready`
        S_READ: st <= S_DATA;              // block RAM read latency
        S_DATA: if (tx_ready) begin
            tx_data  <= q;
            tx_start <= 1'b1;
            st       <= S_TX;
        end
        S_TX: begin
            if (raddr == NPIX - 1) st <= S_WAIT;
            else begin
                raddr <= raddr + 15'd1;
                st    <= S_GAP;
            end
        end
        default: st <= S_WAIT;
        endcase
    end
endmodule
