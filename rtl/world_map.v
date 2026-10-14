// world_map.v -- 16x16 level stored as a combinational ROM.
//
// Each tile is one hex digit: 0 = empty floor, 1..5 = wall with that texture.
// Row 0 is the top of the map (north), column 0 is the left (west).
// The outer ring must stay solid so rays always hit something.
//
// Because this is pure logic (a big constant + indexed part-select), every
// instance is an independent read port. The ray engine, the player collision
// logic and the minimap renderer each get their own copy for free.
module world_map (
    input  wire [3:0] x,
    input  wire [3:0] y,
    output wire [3:0] tile
);
    //                   x: 0123456789ABCDEF
    localparam [1023:0] MAP = {
        64'h1111111111111111,   // y = 0
        64'h1000000100000001,   // y = 1
        64'h1000000100333001,   // y = 2
        64'h1002200000303001,   // y = 3
        64'h1002200100003001,   // y = 4
        64'h1000000100333001,   // y = 5
        64'h1110111100000001,   // y = 6
        64'h1000000000000001,   // y = 7
        64'h1000000004404401,   // y = 8
        64'h1050505004000401,   // y = 9
        64'h1000000004000401,   // y = 10
        64'h1050505004444401,   // y = 11
        64'h1000000000000001,   // y = 12
        64'h1002000000000201,   // y = 13
        64'h1000000000000001,   // y = 14
        64'h1111111111111111    // y = 15
    };

    wire [7:0] idx = {y, x};
    // Cell (x,y) lives at bit offset (255 - idx) * 4. (255 - idx) == ~idx for 8 bits.
    wire [9:0] base = {~idx, 2'b00};
    assign tile = MAP[base +: 4];
endmodule
