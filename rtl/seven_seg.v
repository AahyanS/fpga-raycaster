// seven_seg.v -- multiplexed 4-digit hex display (active-low segments/anodes,
// as on the Basys 3 and Nexys A7). Each digit is lit for ~1.3 ms in turn.
module seven_seg (
    input  wire        clk,
    input  wire [15:0] value,
    output reg  [6:0]  seg = 7'h7F,   // {g,f,e,d,c,b,a}, active low
    output reg  [3:0]  an  = 4'hF     // active low
);
    reg [18:0] refresh = 19'd0;
    always @(posedge clk) refresh <= refresh + 19'd1;

    wire [1:0] digit = refresh[18:17];
    reg  [3:0] nib;

    always @* begin
        case (digit)
            2'd0: nib = value[3:0];
            2'd1: nib = value[7:4];
            2'd2: nib = value[11:8];
            default: nib = value[15:12];
        endcase
    end

    always @(posedge clk) begin
        an <= ~(4'b0001 << digit);
        case (nib)                    //  gfedcba
            4'h0: seg <= ~7'b0111111;
            4'h1: seg <= ~7'b0000110;
            4'h2: seg <= ~7'b1011011;
            4'h3: seg <= ~7'b1001111;
            4'h4: seg <= ~7'b1100110;
            4'h5: seg <= ~7'b1101101;
            4'h6: seg <= ~7'b1111101;
            4'h7: seg <= ~7'b0000111;
            4'h8: seg <= ~7'b1111111;
            4'h9: seg <= ~7'b1101111;
            4'hA: seg <= ~7'b1110111;
            4'hB: seg <= ~7'b1111100;
            4'hC: seg <= ~7'b0111001;
            4'hD: seg <= ~7'b1011110;
            4'hE: seg <= ~7'b1111001;
            default: seg <= ~7'b1110001;  // F
        endcase
    end
endmodule
