// top_basys3.v -- Digilent Basys 3 (xc7a35tcpg236-1) pin-level wrapper.
module top_basys3 (
    input  wire        clk,        // 100 MHz, W5
    input  wire        btnC,       // respawn
    input  wire        btnU,       // forward
    input  wire        btnD,       // back
    input  wire        btnL,       // turn left
    input  wire        btnR,       // turn right
    input  wire [3:0]  sw,
    output wire [3:0]  vgaRed,
    output wire [3:0]  vgaGreen,
    output wire [3:0]  vgaBlue,
    output wire        Hsync,
    output wire        Vsync,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,
    input  wire        RsRx,       // USB-serial, laptop -> FPGA
    output wire        RsTx        // USB-serial, FPGA -> laptop
);
    assign dp = 1'b1;   // decimal points off

    raycaster_core u_core (
        .clk(clk), .btn_reset(btnC), .btn_up(btnU), .btn_down(btnD),
        .btn_left(btnL), .btn_right(btnR), .sw(sw),
        .vga_r(vgaRed), .vga_g(vgaGreen), .vga_b(vgaBlue),
        .vga_hs(Hsync), .vga_vs(Vsync), .out_de(),
        .led(led), .seg(seg), .an(an), .uart_rx(RsRx), .uart_tx(RsTx)
    );
endmodule
