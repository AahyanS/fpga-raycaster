// top_nexys_a7.v -- Digilent Nexys A7-100T (xc7a100tcsg324-1) pin-level wrapper.
// Also works for the Nexys A7-50T / Nexys 4 DDR (change the part in the build script).
module top_nexys_a7 (
    input  wire        CLK100MHZ,
    input  wire        BTNC,
    input  wire        BTNU,
    input  wire        BTND,
    input  wire        BTNL,
    input  wire        BTNR,
    input  wire [3:0]  SW,
    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire [15:0] LED,
    output wire        CA, CB, CC, CD, CE, CF, CG, DP,
    output wire [7:0]  AN,
    input  wire        UART_TXD_IN,    // laptop -> FPGA
    output wire        UART_RXD_OUT    // FPGA -> laptop
);
    wire [6:0] seg;
    wire [3:0] an4;
    assign {CG, CF, CE, CD, CC, CB, CA} = seg;
    assign DP = 1'b1;
    assign AN = {4'hF, an4};   // only the right-hand four digits are used

    raycaster_core u_core (
        .clk(CLK100MHZ), .btn_reset(BTNC), .btn_up(BTNU), .btn_down(BTND),
        .btn_left(BTNL), .btn_right(BTNR), .sw(SW),
        .vga_r(VGA_R), .vga_g(VGA_G), .vga_b(VGA_B),
        .vga_hs(VGA_HS), .vga_vs(VGA_VS), .out_de(),
        .led(LED), .seg(seg), .an(an4), .uart_rx(UART_TXD_IN), .uart_tx(UART_RXD_OUT)
    );
endmodule
