// player.v -- camera state, movement and wall collision.
//
// Updated once per frame on `tick`. Position is Q16.16 in map cells.
// The view direction comes from an 8-bit angle (256 steps per turn) through
// a cos/sin ROM; the camera plane is the direction rotated 90 degrees and
// scaled by 0.66, which gives a ~66 degree field of view.
module player (
    input  wire               clk,
    input  wire               rst,
    input  wire               tick,        // one pulse per frame
    input  wire               btn_fwd,
    input  wire               btn_back,
    input  wire               btn_left,
    input  wire               btn_right,
    input  wire               sprint,
    output reg  signed [31:0] pos_x = 32'sh0003_8000,
    output reg  signed [31:0] pos_y = 32'sh0007_8000,
    output reg         [7:0]  angle = 8'd0,
    output wire signed [31:0] dir_x,
    output wire signed [31:0] dir_y,
    output wire signed [31:0] plane_x,
    output wire signed [31:0] plane_y
);
    localparam signed [31:0] SPAWN_X = 32'sh0003_8000;   // 3.5
    localparam signed [31:0] SPAWN_Y = 32'sh0007_8000;   // 7.5
    localparam signed [31:0] MARGIN  = 32'sh0000_4000;   // 0.25 tile wall clearance
    localparam signed [15:0] FOV_K   = 16'sd10813;       // 0.66 in Q1.14

    // ------------------------------------------------------ direction vectors
    // The camera only changes once per frame, so everything below is a
    // free-running register pipeline: by the time the next `tick` arrives
    // (1.68M cycles later) every stage has long since settled. Registering
    // each step keeps every path to a single LUT/DSP level at 100 MHz.
    wire signed [15:0] c, s;
    trig_lut u_trig (.angle(angle), .cos_q14(c), .sin_q14(s));

    reg signed [15:0] c_r = 16'sd16384, s_r = 16'sd0;
    always @(posedge clk) begin
        c_r <= c;
        s_r <= s;
    end

    wire signed [31:0] pl_x_prod = s_r * FOV_K;   // Q2.28
    wire signed [31:0] pl_y_prod = c_r * FOV_K;

    reg signed [31:0] dir_x_r = 32'sh0001_0000, dir_y_r = 32'sd0;
    reg signed [31:0] plane_x_r = 32'sd0,     plane_y_r = 32'sh0000_A8F5;
    always @(posedge clk) begin
        dir_x_r   <= {{14{c_r[15]}}, c_r, 2'b00};      // Q1.14 -> Q16.16
        dir_y_r   <= {{14{s_r[15]}}, s_r, 2'b00};
        plane_x_r <= -(pl_x_prod >>> 12);               // -(sin * 0.66), Q2.28 -> Q16.16
        plane_y_r <=   pl_y_prod >>> 12;                //   cos * 0.66
    end
    assign dir_x = dir_x_r, dir_y = dir_y_r, plane_x = plane_x_r, plane_y = plane_y_r;

    // ------------------------------------------------------------- movement
    // Buttons are sampled once per frame, so every pipeline input below is
    // constant between ticks (one frame of input latency, ~16 ms).
    reg fwd = 1'b0, back = 1'b0, left = 1'b0, right = 1'b0, fast = 1'b0;
    always @(posedge clk) if (tick) begin
        fwd <= btn_fwd; back <= btn_back; left <= btn_left; right <= btn_right; fast <= sprint;
    end

    reg signed [31:0] mv_x = 32'sd0, mv_y = 32'sd0;
    always @(posedge clk) begin
        mv_x <= fwd  ?  (fast ? dir_x_r >>> 4 : dir_x_r >>> 5) :
                back ? -(fast ? dir_x_r >>> 4 : dir_x_r >>> 5) : 32'sd0;
        mv_y <= fwd  ?  (fast ? dir_y_r >>> 4 : dir_y_r >>> 5) :
                back ? -(fast ? dir_y_r >>> 4 : dir_y_r >>> 5) : 32'sd0;
    end

    // Candidate position, plus a probe one margin further along each axis so
    // the player stops short of walls and slides along them.
    reg signed [31:0] nx = 32'sd0, ny = 32'sd0, probe_x = 32'sd0, probe_y = 32'sd0;
    always @(posedge clk) begin
        nx      <= pos_x + mv_x;
        ny      <= pos_y + mv_y;
        probe_x <= pos_x + mv_x + (mv_x[31] ? -MARGIN : MARGIN);
        probe_y <= pos_y + mv_y + (mv_y[31] ? -MARGIN : MARGIN);
    end

    wire [3:0] tile_x, tile_y;
    world_map u_map_x (.x(probe_x[19:16]), .y(pos_y[19:16]),   .tile(tile_x));
    world_map u_map_y (.x(pos_x[19:16]),   .y(probe_y[19:16]), .tile(tile_y));

    reg free_x = 1'b0, free_y = 1'b0;
    always @(posedge clk) begin
        free_x <= (tile_x == 4'd0);
        free_y <= (tile_y == 4'd0);
    end

    always @(posedge clk) begin
        if (rst) begin
            pos_x <= SPAWN_X;
            pos_y <= SPAWN_Y;
            angle <= 8'd0;
        end else if (tick) begin
            if (left)  angle <= angle - 8'd2;
            if (right) angle <= angle + 8'd2;
            if (free_x) pos_x <= nx;
            if (free_y) pos_y <= ny;
        end
    end
endmodule
