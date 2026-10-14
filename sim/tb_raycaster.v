// tb_raycaster.v -- runs the full design cycle-accurately and saves frames.
//
// Reads a "script" of segments, one per line:  <frames> <buttons> <capture>
//   buttons is a hex nibble {up, down, left, right}, capture 1 = save frames.
// Every captured frame is written as 640x480 hex pixels to frame_NNNN.hex.
// Usage:  vvp tb.vvp +script=script.txt
`timescale 1ns/1ps
module tb_raycaster;
    reg clk = 1'b0;
    always #5 clk = ~clk;                      // 100 MHz

    reg        b_up = 0, b_down = 0, b_left = 0, b_right = 0;
    reg  [3:0] sw = 4'd0;
    wire [3:0] r, g, b;
    wire       hs, vs, de;
    wire [15:0] led;
    wire [6:0] seg;
    wire [3:0] an;
    reg        pc_rx = 1'b1;          // laptop -> FPGA serial line
    wire       pc_tx;                 // FPGA -> laptop serial line
    reg  [3:0] btn_req = 4'd0;        // buttons requested by the script
    reg        via_pc = 1'b0;         // +viapc: send them as laptop key bytes

    raycaster_core dut (
        .clk(clk), .btn_reset(1'b0), .btn_up(b_up), .btn_down(b_down),
        .btn_left(b_left), .btn_right(b_right), .sw(sw),
        .vga_r(r), .vga_g(g), .vga_b(b), .vga_hs(hs), .vga_vs(vs), .out_de(de),
        .led(led), .seg(seg), .an(an), .uart_rx(pc_rx), .uart_tx(pc_tx)
    );

    // ------------------------------------------------------------------
    // Laptop model, part 1: decode the FPGA's serial video stream exactly
    // like viewer.py does (sync on 0xFF, then 160x120 bytes).
    localparam BIT = 33 * 10;          // ns per bit at 100 MHz
    integer ufd = 0, ucount = -1, uframes = 0, bi;
    reg [7:0] ub;
    reg [8*64-1:0] uname;
    initial begin
        forever begin
            @(negedge pc_tx);
            #(BIT/2);
            for (bi = 0; bi < 8; bi = bi + 1) begin
                #(BIT);
                ub[bi] = pc_tx;
            end
            #(BIT);                    // stop bit
            if (!pc_tx) $display("UART framing error");
            if (ub == 8'hFF) begin
                if (ucount > 0) $display("UART: short frame (%0d bytes)", ucount);
                if (ufd) $fclose(ufd);
                $sformat(uname, "uart_%04d.hex", uframes);
                ufd = $fopen(uname, "w");
                ucount = 0;
            end else if (ucount >= 0) begin
                $fdisplay(ufd, "%h", ub);
                ucount = ucount + 1;
                if (ucount == 19200) begin
                    $fclose(ufd); ufd = 0; ucount = -1;
                    $display("UART: received full frame %0s", uname);
                    uframes = uframes + 1;
                end
            end
        end
    end

    // Laptop model, part 2: when +viapc is set, press keys over serial.
    task send_byte;
        input [7:0] v;
        integer j;
        begin
            pc_rx = 1'b0; #(BIT);
            for (j = 0; j < 8; j = j + 1) begin pc_rx = v[j]; #(BIT); end
            pc_rx = 1'b1; #(BIT);
        end
    endtask
    initial begin
        #1;
        forever begin
            if (via_pc) send_byte({3'b101, 1'b0, btn_req});
            #2_000_000;                // every 2 ms
        end
    end

    // Frame boundaries come from the VGA vsync pin, like a real monitor.
    integer frame = 0;
    reg     vs_q = 1'b1;
    integer fd = 0;
    reg     capturing = 1'b0;
    integer pixels = 0;
    reg [8*64-1:0] fname;

    // Hsync/vsync sanity checks (counted on the pins, not on internal state).
    integer hs_lows = 0;

    always @(posedge clk) begin
        vs_q <= vs;
        if (dut.pix_en) begin
            // output registers update on this edge; sample them just after
            #1;
            if (capturing && de) begin
                $fdisplay(fd, "%h%h%h", r, g, b);
                pixels = pixels + 1;
            end
        end
    end

    reg [8*256-1:0] script;
    integer sfd, n_frames, btns, cap, rc, target, cap_index = 0;

    task run_frames;
        input integer n;
        input integer capture;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                @(posedge vs);   // sync pulse over: the next 480 visible lines follow
                if (capture) begin
                    $sformat(fname, "frame_%04d.hex", cap_index);
                    fd = $fopen(fname, "w");
                    pixels = 0;
                    capturing = 1'b1;
                end
                @(negedge vs);   // next sync pulse: the frame has been scanned out
                if (capture) begin
                    capturing = 1'b0;
                    $fclose(fd);
                    $display("captured %0s  pixels=%0d  pos=(%0d.%02d, %0d.%02d) angle=%0d  engine_leds=%b",
                             fname, pixels,
                             dut.pos_x >>> 16, ((dut.pos_x & 32'hFFFF) * 100) >> 16,
                             dut.pos_y >>> 16, ((dut.pos_y & 32'hFFFF) * 100) >> 16,
                             dut.angle, led);
                    cap_index = cap_index + 1;
                end
                frame = frame + 1;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("script=%s", script)) script = "script.txt";
        if ($test$plusargs("sprint")) sw[3] = 1'b1;
        if ($test$plusargs("viapc"))  via_pc = 1'b1;
        sfd = $fopen(script, "r");
        if (sfd == 0) begin $display("cannot open script"); $finish; end

        // Two warm-up frames: one to fill the back buffer, one to swap it in.
        run_frames(2, 0);

        while (!$feof(sfd)) begin
            rc = $fscanf(sfd, "%d %h %d\n", n_frames, btns, cap);
            if (rc == 3) begin
                btn_req = btns[3:0];
                if (!via_pc) {b_up, b_down, b_left, b_right} = btns[3:0];
                run_frames(n_frames, cap);
            end
        end
        $display("done");
        $finish;
    end
endmodule
