// raycaster_core.v -- board-independent top of the hardware raycaster.
//
//   +---------+  frame tick   +------------+  65-bit column   +---------------+
//   | player  | ------------> | ray_engine | ---- records ---> | column buffer |
//   | (move,  |   camera      | (DDA, 2    |   (back bank)     | 2 x 1024 x 65 |
//   | collide)|               |  dividers) |                   | block RAM     |
//   +---------+               +------------+                   +-------+-------+
//                                                                      | front bank
//   +-----------+  hc, vc   +-------------------------------------+    |
//   | VGA timing| --------> | pixel pipeline: wall/ceiling/floor, | <--+
//   | 640x480@60|           | procedural textures, shading, fog,  | --> VGA pins
//   +-----------+           | minimap + crosshair overlay         |
//                           +-------------------------------------+
//
// Everything runs on the 100 MHz board clock. The 25 MHz pixel rate is a
// clock *enable* (pix_en every 4th cycle), not a derived clock, so there is a
// single clock domain and no clocking IP is needed.
//
// Double buffering: while the screen scans out the front bank, the engine
// fills the back bank for the next frame. The banks swap at the start of
// vertical blanking, so there is never any tearing.
module raycaster_core (
    input  wire        clk,          // 100 MHz
    input  wire        btn_reset,
    input  wire        btn_up,
    input  wire        btn_down,
    input  wire        btn_left,
    input  wire        btn_right,
    input  wire [3:0]  sw,           // [0] hide minimap [1] no fog [2] flat colors [3] sprint
    output reg  [3:0]  vga_r = 4'd0,
    output reg  [3:0]  vga_g = 4'd0,
    output reg  [3:0]  vga_b = 4'd0,
    output reg         vga_hs = 1'b1,
    output reg         vga_vs = 1'b1,
    output reg         out_de = 1'b0, // pixel valid (for simulation capture)
    output reg  [15:0] led = 16'd0,  // engine load bar graph
    output wire [6:0]  seg,
    output wire [3:0]  an,
    input  wire        uart_rx,      // from the laptop (keyboard control)
    output wire        uart_tx       // to the laptop (video stream)
);
    // ------------------------------------------------------- input sync
    reg [4:0] b_meta = 5'd0, b_sync = 5'd0;
    reg [3:0] sw_meta = 4'd0, sw_sync = 4'd0;
    always @(posedge clk) begin
        b_meta  <= {btn_reset, btn_up, btn_down, btn_left, btn_right};
        b_sync  <= b_meta;
        sw_meta <= sw;
        sw_sync <= sw_meta;
    end
    // Laptop keyboard: the viewer sends one byte 101SUDLR (sprint, up, down,
    // left, right) ~20 times a second. Keys release if bytes stop arriving.
    wire       rx_valid;
    wire [7:0] rx_byte;
    uart_rx #(.CLKS_PER_BIT(33)) u_rx (.clk(clk), .rx(uart_rx), .valid(rx_valid), .data(rx_byte));

    reg [4:0]  pc_keys = 5'd0;
    reg [24:0] pc_timeout = 25'd0;
    always @(posedge clk) begin
        if (rx_valid && rx_byte[7:5] == 3'b101) begin
            pc_keys    <= rx_byte[4:0];
            pc_timeout <= 25'd25_000_000;          // 250 ms
        end else if (pc_timeout != 25'd0) begin
            pc_timeout <= pc_timeout - 25'd1;
        end else begin
            pc_keys <= 5'd0;
        end
    end

    wire k_reset = b_sync[4];
    wire k_up    = b_sync[3] | pc_keys[3];
    wire k_down  = b_sync[2] | pc_keys[2];
    wire k_left  = b_sync[1] | pc_keys[1];
    wire k_right = b_sync[0] | pc_keys[0];
    wire hide_map = sw_sync[0], no_fog = sw_sync[1], flat = sw_sync[2];
    wire sprint   = sw_sync[3] | pc_keys[4];

    // Power-on reset, plus the centre button.
    reg [7:0] por = 8'd0;
    always @(posedge clk) if (!por[7]) por <= por + 8'd1;
    wire rst = !por[7] || k_reset;

    // ------------------------------------------------------- VGA timing
    // 640x480 @ 60 Hz: 800 x 525 total, 25 MHz pixel rate.
    reg  [1:0] div = 2'd0;
    wire       pix_en = (div == 2'd3);
    reg  [9:0] hc = 10'd0, vc = 10'd0;
    always @(posedge clk) begin
        div <= div + 2'd1;
        if (pix_en) begin
            if (hc == 10'd799) begin
                hc <= 10'd0;
                vc <= (vc == 10'd524) ? 10'd0 : vc + 10'd1;
            end else begin
                hc <= hc + 10'd1;
            end
        end
    end
    wire visible    = (hc < 10'd640) && (vc < 10'd480);
    wire frame_tick = pix_en && (hc == 10'd799) && (vc == 10'd479);  // vblank starts

    // ----------------------------------------------------------- player
    wire signed [31:0] pos_x, pos_y, dir_x, dir_y, plane_x, plane_y;
    wire        [7:0]  angle;
    player u_player (
        .clk(clk), .rst(rst), .tick(frame_tick),
        .btn_fwd(k_up), .btn_back(k_down), .btn_left(k_left), .btn_right(k_right),
        .sprint(sprint),
        .pos_x(pos_x), .pos_y(pos_y), .angle(angle),
        .dir_x(dir_x), .dir_y(dir_y), .plane_x(plane_x), .plane_y(plane_y)
    );

    // ------------------------------------------------------- ray engine
    reg         front = 1'b0;
    wire        busy, wr_en;
    wire [10:0] wr_addr;
    wire [64:0] wr_data;
    wire        launch = frame_tick && !busy;

    always @(posedge clk) if (launch) front <= ~front;

    ray_engine u_engine (
        .clk(clk), .rst(rst), .start(launch), .bank(front),   // old front = new back
        .pos_x(pos_x), .pos_y(pos_y), .dir_x(dir_x), .dir_y(dir_y),
        .plane_x(plane_x), .plane_y(plane_y),
        .busy(busy), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data)
    );

    // Engine load meter: cycles spent busy per frame, shown as an LED bar.
    reg [20:0] busy_cnt = 21'd0;
    always @(posedge clk) begin
        if (frame_tick) begin
            busy_cnt <= 21'd0;
            led <= ~(16'hFFFF << busy_cnt[20:14]);   // 1 LED per 16k cycles
        end else if (busy) begin
            busy_cnt <= busy_cnt + 21'd1;
        end
    end

    // ---------------------------------------------------- column buffer
    // Simple dual-port block RAM: engine writes, display reads.
    (* ram_style = "block" *) reg [64:0] colmem [0:2047];

    reg [64:0] col = 65'd0;
    always @(posedge clk) begin
        if (wr_en) colmem[wr_addr] <= wr_data;
        col <= colmem[{front, hc}];                     // pipeline stage 1
    end

    wire signed [15:0] c_top  = col[64:49];
    wire signed [15:0] c_bot  = col[48:33];
    wire        [19:0] c_step = col[32:13];
    wire        [5:0]  c_tx   = col[12:7];
    wire        [2:0]  c_type = col[6:4];
    wire               c_side = col[3];
    wire        [2:0]  c_fog  = col[2:0];

    // ------------------------------------------------ pixel pipeline
    // The counters only move every 4 clocks, so the pipeline below runs at
    // the full 100 MHz and is fully settled when the next pix_en arrives.
    // Stage timing: addr @E0 -> RAM @E1 -> stage 2 @E2 -> stage 3 @E3 -> pins @E4.

    // Stage 2: wall test, texture-row multiply, minimap lookup.
    wire signed [15:0] y_s = {6'd0, vc};
    wire signed [15:0] dy  = y_s - c_top;
    wire signed [36:0] ty_prod = dy * $signed({1'b0, c_step});

    // Minimap: 16x16 cells, 4 px each, at (8,8).
    wire [9:0] mmx = hc - 10'd8;
    wire [9:0] mmy = vc - 10'd8;
    wire       in_mm = (hc >= 10'd8) && (hc < 10'd72) && (vc >= 10'd8) && (vc < 10'd72);
    wire [3:0] mm_cell;
    world_map u_mm (.x(mmx[5:2]), .y(mmy[5:2]), .tile(mm_cell));

    // Player dot and a "look" dot one tile ahead.
    wire [5:0]         ppx = pos_x[19:14], ppy = pos_y[19:14];
    wire signed [31:0] look_x = pos_x + dir_x, look_y = pos_y + dir_y;
    wire [5:0]         plx = look_x[19:14], ply = look_y[19:14];
    wire [5:0]         mx6 = mmx[5:0], my6 = mmy[5:0];
    wire near_player = (mx6 + 6'd1 >= ppx) && (mx6 <= ppx + 6'd1) &&
                       (my6 + 6'd1 >= ppy) && (my6 <= ppy + 6'd1);
    wire on_look     = (mx6 == plx) && (my6 == ply);

    reg        s2_wall = 1'b0, s2_mm = 1'b0, s2_player = 1'b0, s2_look = 1'b0;
    reg [5:0]  s2_ty = 6'd0, s2_tx = 6'd0;
    reg [2:0]  s2_type = 3'd0, s2_fog = 3'd0;
    reg        s2_side = 1'b0;
    reg [3:0]  s2_mm_cell = 4'd0;
    reg        s2_cross = 1'b0;

    always @(posedge clk) begin
        s2_wall    <= (y_s >= c_top) && (y_s < c_bot);
        s2_ty      <= ty_prod[21:16];
        s2_tx      <= c_tx;
        s2_type    <= c_type;
        s2_side    <= c_side;
        s2_fog     <= no_fog ? 3'd0 : c_fog;
        s2_mm      <= in_mm && !hide_map;
        s2_mm_cell <= mm_cell;
        s2_player  <= near_player;
        s2_look    <= on_look;
        s2_cross   <= ((hc == 10'd320) && (vc >= 10'd234) && (vc <= 10'd246) && (vc != 10'd240)) ||
                      ((vc == 10'd240) && (hc >= 10'd314) && (hc <= 10'd326) && (hc != 10'd320));
    end

    // Stage 3: procedural textures, lighting, overlays.
    function [11:0] flat_color;
        input [2:0] t;
        case (t)
            3'd1: flat_color = 12'hB22;   // red
            3'd2: flat_color = 12'h33B;   // blue
            3'd3: flat_color = 12'h2A2;   // green
            3'd4: flat_color = 12'h962;   // brown
            3'd5: flat_color = 12'hA3C;   // purple
            default: flat_color = 12'h888;
        endcase
    endfunction

    // 64x64 textures computed from (u,v) on the fly -- no texture memory at all.
    function [11:0] texel;
        input [2:0] t;
        input [5:0] u, v;
        reg   [5:0] bu;
        reg   [3:0] x4;
        reg   [6:0] du, dv, d;
        begin
            case (t)
            3'd1: begin                                   // red brick, offset rows
                bu = u + (v[4] ? 6'd16 : 6'd0);
                if (v[3:0] == 4'd0 || bu[4:0] == 5'd0)
                    texel = 12'h777;                      // mortar
                else
                    texel = {4'hA + {3'd0, u[1] ^ v[2]}, 4'h2 + {3'd0, v[1]}, 4'h1};
            end
            3'd2: begin                                   // blue XOR stone
                x4 = (u ^ v) >> 2;
                texel = {2'b00, x4[3:2], 1'b0, x4[3:1], x4 | 4'h4};
            end
            3'd3: begin                                   // green tiles
                if (u[3:0] == 4'd0 || v[3:0] == 4'd0) texel = 12'h131;
                else texel = (u[4] ^ v[4]) ? 12'h3B3 : 12'h282;
            end
            3'd4: begin                                   // wooden planks
                if (u[3:0] == 4'd0) texel = 12'h421;
                else texel = {4'h9 + {3'd0, v[3] ^ u[2]}, 4'h5 + {3'd0, v[2] ^ u[1]}, 4'h2};
            end
            3'd5: begin                                   // purple diamonds
                du = u[5] ? {1'b0, u} - 7'd32 : 7'd32 - {1'b0, u};
                dv = v[5] ? {1'b0, v} - 7'd32 : 7'd32 - {1'b0, v};
                d  = du + dv;
                texel = d[3] ? 12'hA3C : 12'h518;
            end
            default: texel = 12'h888;
            endcase
        end
    endfunction

    // Scale a 4-bit channel by k/8, k in 0..8.
    function [3:0] scale;
        input [3:0] ch;
        input [3:0] k;
        reg   [7:0] p;
        begin
            p = ch * k;
            scale = p[6:3];
        end
    endfunction

    function [11:0] shade;
        input [11:0] rgb;
        input        side;
        input [2:0]  fog;
        reg   [3:0]  k;
        begin
            k = 4'd8 - {1'b0, fog} - (side ? 4'd2 : 4'd0);   // y-sides are darker
            shade = {scale(rgb[11:8], k), scale(rgb[7:4], k), scale(rgb[3:0], k)};
        end
    endfunction

    wire [11:0] wall_rgb = shade(flat ? flat_color(s2_type) : texel(s2_type, s2_tx, s2_ty),
                                 s2_side, s2_fog);

    // Sky gradient (dark at the top) and floor gradient (lighter close up).
    wire [9:0]  fy        = vc - 10'd240;
    wire [11:0] ceil_rgb  = {2'b00, vc[7:6], 2'b00, vc[7:6], 4'd4 + {1'b0, vc[7:5]}};
    wire [3:0]  fv        = 4'd2 + {1'b0, fy[7:5]};
    wire [11:0] floor_rgb = {fv, fv - {2'b00, fv[3:2]}, {1'b0, fv[3:1]}};

    wire [11:0] mm_rgb = s2_player ? 12'hFF0 :
                         s2_look   ? 12'hF80 :
                         (s2_mm_cell != 4'd0) ? flat_color(s2_mm_cell[2:0]) : 12'h111;

    reg [11:0] s3_rgb = 12'd0;
    always @(posedge clk) begin
        if (s2_mm)         s3_rgb <= mm_rgb;
        else if (s2_cross) s3_rgb <= 12'hFFF;
        else if (s2_wall)  s3_rgb <= wall_rgb;
        else if (vc < 10'd240) s3_rgb <= ceil_rgb;
        else               s3_rgb <= floor_rgb;
    end

    // Output registers, aligned with the counter value set 4 clocks earlier.
    always @(posedge clk) begin
        if (pix_en) begin
            {vga_r, vga_g, vga_b} <= visible ? s3_rgb : 12'd0;
            vga_hs <= ~((hc >= 10'd656) && (hc < 10'd752));
            vga_vs <= ~((vc >= 10'd490) && (vc < 10'd492));
            out_de <= visible;
        end
    end

    // ------------------------------------------------- USB video stream
    frame_streamer #(.CLKS_PER_BIT(33)) u_stream (
        .clk(clk), .pix_en(pix_en), .hc(hc), .vc(vc), .rgb(s3_rgb), .tx(uart_tx)
    );

    // ------------------------------------------------------ 7-segment
    // Shows map X, map Y and the 8-bit view angle in hex: "X Y AA".
    seven_seg u_seg (
        .clk(clk),
        .value({pos_x[19:16], pos_y[19:16], angle}),
        .seg(seg), .an(an)
    );
endmodule
