// ray_engine.v -- the "GPU": casts one ray per screen column with the DDA
// (Digital Differential Analyzer) grid-walk algorithm, entirely in hardware.
//
// All math is signed fixed point, Q16.16 (65536 = 1.0), unless noted.
//
// For each column x = 0..639:
//   1. cameraX  = 2x/640 - 1                    (constant multiply, no divide)
//   2. rayDir   = dir + plane * cameraX
//   3. deltaX/Y = |1 / rayDir.x|, |1 / rayDir.y| (serial divider)
//   4. walk the grid one tile at a time until a wall tile is hit
//   5. perpDist = fisheye-corrected distance     (sideDist - delta, no divide)
//   6. lineH    = 480 / perpDist                 (serial divider)
//   7. texture column, texture step and fog level
//   8. write one 65-bit record into the column buffer
//
// Worst case is roughly 250 cycles per column, about 160k cycles per frame,
// i.e. under 10% of the 1.68M cycles available in a 60 Hz frame at 100 MHz.
module ray_engine (
    input  wire               clk,
    input  wire               rst,
    input  wire               start,      // pulse: begin a new frame
    input  wire               bank,       // which half of the column buffer to fill
    input  wire signed [31:0] pos_x,
    input  wire signed [31:0] pos_y,
    input  wire signed [31:0] dir_x,
    input  wire signed [31:0] dir_y,
    input  wire signed [31:0] plane_x,
    input  wire signed [31:0] plane_y,
    output reg                busy = 1'b0,
    output reg                wr_en = 1'b0,
    output reg  [10:0]        wr_addr = 11'd0,
    output reg  [64:0]        wr_data = 65'd0
);
    // ---------------------------------------------------------------- states
    localparam S_IDLE  = 4'd0,
               S_CAM   = 4'd1,
               S_RAY   = 4'd2,
               S_DIVX  = 4'd3,
               S_WDX   = 4'd4,
               S_DIVY  = 4'd5,
               S_WDY   = 4'd6,
               S_INIT  = 4'd7,
               S_DDA   = 4'd8,
               S_CHECK = 4'd9,
               S_DIST  = 4'd10,
               S_TEX   = 4'd11,
               S_WDH   = 4'd12,
               S_WRITE = 4'd13;

    localparam [31:0] MIN_DIST  = 32'h0000_0C00;   // ~0.047, keeps lineH bounded
    localparam [31:0] MAX_DIST  = 32'h001F_FFFF;   // just under 32 cells
    localparam [23:0] MAX_DELTA = 24'hFF_FFFF;     // 256.0, "parallel to axis"
    localparam [31:0] LH_MAX    = 32'd16000;
    localparam [5:0]  MAX_STEPS = 6'd40;

    reg [3:0] st = S_IDLE;
    reg [9:0] col = 10'd0;
    reg       bank_r = 1'b0;

    // Snapshot of the camera, taken at the start of the frame so the whole
    // frame is rendered from one consistent viewpoint.
    reg signed [31:0] px, py, dx, dy, plx, ply;

    reg signed [31:0] cam;            // cameraX, Q16.16 in [-1, 1)
    reg signed [31:0] rdx, rdy;       // ray direction
    reg        [31:0] dlx, dly;       // delta distances (unsigned)
    reg        [31:0] sdx, sdy;       // side distances (unsigned)
    reg        [3:0]  mx, my;         // current map tile
    reg               neg_x, neg_y;   // step direction is -1
    reg               side;           // 0 = hit an x-side, 1 = hit a y-side
    reg        [5:0]  steps;
    reg        [2:0]  wtype;
    reg        [31:0] perp;
    reg        [5:0]  tex_x;
    reg        [19:0] tex_step;
    reg        [2:0]  fog;

    // --------------------------------------------------------- map lookup
    wire [3:0] tile;
    world_map u_map (.x(mx), .y(my), .tile(tile));

    // ------------------------------------------------------------ divider
    reg         div_start = 1'b0;
    reg  [47:0] div_n = 48'd0;
    reg  [31:0] div_d = 32'd0;
    wire        div_done;
    wire [47:0] div_q;
    udiv #(.N(48), .D(32)) u_div (
        .clk(clk), .start(div_start), .dividend(div_n), .divisor(div_d),
        .done(div_done), .quotient(div_q)
    );

    // -------------------------------------------------- combinational math
    // Every multiply below is sized to fit one DSP48E1 slice (25 x 18 signed),
    // so each completes in a single 10 ns cycle without extra pipelining.

    // ray = dir + plane * cameraX      (|plane| <= 0.66, |cam| <= 1 -> 18 bits each)
    wire signed [17:0] plx18 = plx[17:0], ply18 = ply[17:0], cam18 = cam[17:0];
    wire signed [35:0] pcx = plx18 * cam18;
    wire signed [35:0] pcy = ply18 * cam18;

    wire [31:0] abs_rdx = rdx[31] ? -rdx : rdx;
    wire [31:0] abs_rdy = rdy[31] ? -rdy : rdy;

    wire [23:0] div_q_clamped = (div_q > {24'd0, MAX_DELTA}) ? MAX_DELTA : div_q[23:0];

    // Distance from the player to the first grid line on each axis, as a
    // fraction of a tile (Q0.16, may be exactly 1.0 so 17 bits).
    wire [31:0] frac_x = rdx[31] ? {16'd0, px[15:0]} : (32'h0001_0000 - {16'd0, px[15:0]});
    wire [31:0] frac_y = rdy[31] ? {16'd0, py[15:0]} : (32'h0001_0000 - {16'd0, py[15:0]});
    wire [16:0] fx17 = frac_x[16:0], fy17 = frac_y[16:0];
    wire [23:0] dlx24 = dlx[23:0], dly24 = dly[23:0];
    wire [40:0] sdx0  = fx17 * dlx24;
    wire [40:0] sdy0  = fy17 * dly24;

    // Perpendicular (fisheye-free) distance to the wall that was hit.
    wire [31:0] perp_raw = side ? (sdy - dly) : (sdx - dlx);

    // Exact hit point along the wall, for texture mapping.
    // perp is clamped below 32.0 (21 bits); |rayDir| < 2 (18 bits signed).
    wire signed [21:0] perp22  = {1'b0, perp[20:0]};
    wire signed [17:0] rd18    = side ? rdx[17:0] : rdy[17:0];
    wire signed [39:0] hit_off = perp22 * rd18;
    wire signed [31:0] wall_x  = (side ? px : py) + {{8{hit_off[39]}}, hit_off[39:16]};
    wire        [5:0]  tex_raw = wall_x[15:10];
    wire               flip    = (!side && !rdx[31]) || (side && rdy[31]);

    // Texture step = 64 / lineH = perpDist * 64/480 (a multiply, not a divide).
    wire [20:0] perp21    = perp[20:0];
    wire [34:0] step_prod = perp21 * 14'd8738;

    // Line height and the (unclamped) top / bottom of the wall slice.
    wire [31:0]        lh    = (div_q > {16'd0, LH_MAX}) ? LH_MAX : div_q[31:0];
    wire signed [16:0] top   = 17'sd240 - $signed({1'b0, lh[15:1]});
    wire signed [16:0] bot   = top + $signed({1'b0, lh[15:0]});

    // ------------------------------------------------------- state machine
    always @(posedge clk) begin
        wr_en     <= 1'b0;
        div_start <= 1'b0;

        if (rst) begin
            st   <= S_IDLE;
            busy <= 1'b0;
        end else begin
            case (st)
            S_IDLE: if (start) begin
                px <= pos_x;  py <= pos_y;
                dx <= dir_x;  dy <= dir_y;
                plx <= plane_x; ply <= plane_y;
                bank_r <= bank;
                col  <= 10'd0;
                busy <= 1'b1;
                st   <= S_CAM;
            end

            // cameraX = col * (2/640) - 1; 65536*2/640 = 204.8 ~ 205
            S_CAM: begin
                cam <= $signed({22'd0, col}) * 32'sd205 - 32'sd65536;
                st  <= S_RAY;
            end

            S_RAY: begin
                rdx <= dx + {{12{pcx[35]}}, pcx[35:16]};
                rdy <= dy + {{12{pcy[35]}}, pcy[35:16]};
                mx  <= px[19:16];
                my  <= py[19:16];
                st  <= S_DIVX;
            end

            // deltaX = 1.0 / |rayDir.x|  ->  2^32 / |rdx| in Q16.16
            S_DIVX: begin
                div_n <= 48'h0001_0000_0000;
                div_d <= abs_rdx;
                div_start <= 1'b1;
                st <= S_WDX;
            end
            S_WDX: if (div_done) begin
                dlx <= {8'd0, div_q_clamped};
                st  <= S_DIVY;
            end

            S_DIVY: begin
                div_n <= 48'h0001_0000_0000;
                div_d <= abs_rdy;
                div_start <= 1'b1;
                st <= S_WDY;
            end
            S_WDY: if (div_done) begin
                dly <= {8'd0, div_q_clamped};
                st  <= S_INIT;
            end

            S_INIT: begin
                sdx   <= {7'd0, sdx0[40:16]};
                sdy   <= {7'd0, sdy0[40:16]};
                neg_x <= rdx[31];
                neg_y <= rdy[31];
                steps <= 6'd0;
                st    <= S_DDA;
            end

            // Step into whichever grid line is closer.
            S_DDA: begin
                if (sdx < sdy) begin
                    sdx  <= sdx + dlx;
                    mx   <= neg_x ? mx - 4'd1 : mx + 4'd1;
                    side <= 1'b0;
                end else begin
                    sdy  <= sdy + dly;
                    my   <= neg_y ? my - 4'd1 : my + 4'd1;
                    side <= 1'b1;
                end
                steps <= steps + 6'd1;
                st    <= S_CHECK;
            end

            S_CHECK: begin
                if (tile != 4'd0 || steps >= MAX_STEPS) begin
                    wtype <= (tile == 4'd0) ? 3'd1 : tile[2:0];
                    st    <= S_DIST;
                end else begin
                    st <= S_DDA;
                end
            end

            S_DIST: begin
                perp <= (perp_raw < MIN_DIST) ? MIN_DIST :
                        (perp_raw > MAX_DIST) ? MAX_DIST : perp_raw;
                st   <= S_TEX;
            end

            // Texture coordinate, fog level, and kick off lineH = 480 / perp.
            S_TEX: begin
                tex_x    <= flip ? ~tex_raw : tex_raw;
                tex_step <= step_prod[34:16];   // < 2^19 because perp < 32.0
                fog      <= (perp[31:17] > 15'd5) ? 3'd5 : perp[19:17];
                div_n    <= 48'd480 << 16;
                div_d    <= perp;
                div_start <= 1'b1;
                st       <= S_WDH;
            end

            S_WDH: if (div_done) begin
                st <= S_WRITE;
            end

            // Record layout: top(16) bot(16) tex_step(20) tex_x(6) type(3) side(1) fog(3)
            S_WRITE: begin
                wr_en   <= 1'b1;
                wr_addr <= {bank_r, col};
                wr_data <= {top[15:0], bot[15:0], tex_step, tex_x, wtype, side, fog};
                if (col == 10'd639) begin
                    busy <= 1'b0;
                    st   <= S_IDLE;
                end else begin
                    col <= col + 10'd1;
                    st  <= S_CAM;
                end
            end

            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
