
module convert_lz77_to_symbols (
    input  wire        rstn,
    input  wire        clk,
    // input : lz77 stream
    input  wire [ 7:0] i_byte,
    input  wire        i_nlz_en,
    input  wire        i_lz_en,
    input  wire [ 7:0] i_lz_len_minus3,
    input  wire [13:0] i_lz_dist_minus1,
    // output : symbol stream
    output reg         o_symbol_en,
    output reg  [ 8:0] o_symbol,        // 0~285 . Note that this module will generate END symbol (256), which must be add by successor module
    output reg  [ 4:0] o_len_ebits,     // 5bits
    output reg  [ 2:0] o_len_ecnt,      // 0 ~ 5
    output reg  [ 4:0] o_dist_symbol,   // 0 ~ 27 . Note that distance <= 16383, so o_dist_symbol cannot larger than 27
    output reg  [11:0] o_dist_ebits,    // 12bits
    output reg  [ 3:0] o_dist_ecnt      // 0 ~ 12 . Note that distance <= 16383, so o_dist_ecnt cannot be 13
);


initial o_symbol_en   = 1'b0;
initial o_symbol      = 9'h0;
initial o_len_ebits   = 5'h0;
initial o_len_ecnt    = 3'h0;
initial o_dist_symbol = 5'h0;
initial o_dist_ebits  = 12'h0;
initial o_dist_ecnt   = 4'h0;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        o_symbol_en   <= 1'b0;
        o_symbol      <= 9'h0;
        o_len_ebits   <= 5'h0;
        o_len_ecnt    <= 3'h0;
        o_dist_symbol <= 5'h0;
        o_dist_ebits  <= 12'h0;
        o_dist_ecnt   <= 4'h0;
    end else begin
        o_symbol_en <= i_nlz_en | i_lz_en;
        
        if      (i_lz_len_minus3 < 8'd8  ) begin   o_symbol <= 9'd257 + i_lz_len_minus3[2:0];   o_len_ebits <=  5'h0;                          o_len_ecnt <= 3'h0;  end
        else if (i_lz_len_minus3 < 8'd16 ) begin   o_symbol <= 9'd265 + i_lz_len_minus3[2:1];   o_len_ebits <= {4'h0, i_lz_len_minus3[0]};     o_len_ecnt <= 3'h1;  end
        else if (i_lz_len_minus3 < 8'd32 ) begin   o_symbol <= 9'd269 + i_lz_len_minus3[3:2];   o_len_ebits <= {3'h0, i_lz_len_minus3[1:0]};   o_len_ecnt <= 3'h2;  end
        else if (i_lz_len_minus3 < 8'd64 ) begin   o_symbol <= 9'd273 + i_lz_len_minus3[4:3];   o_len_ebits <= {2'h0, i_lz_len_minus3[2:0]};   o_len_ecnt <= 3'h3;  end
        else if (i_lz_len_minus3 < 8'd128) begin   o_symbol <= 9'd277 + i_lz_len_minus3[5:4];   o_len_ebits <= {1'h0, i_lz_len_minus3[3:0]};   o_len_ecnt <= 3'h4;  end
        else if (i_lz_len_minus3 < 8'd255) begin   o_symbol <= 9'd281 + i_lz_len_minus3[6:5];   o_len_ebits <=        i_lz_len_minus3[4:0];    o_len_ecnt <= 3'h5;  end
        else                               begin   o_symbol <= 9'd285;                          o_len_ebits <=  5'h0;                          o_len_ecnt <= 3'h0;  end
        
        if (i_nlz_en)
            o_symbol <= i_byte;
        
        if      (i_lz_dist_minus1 < 14'd4   ) begin   o_dist_symbol <= { 3'b000, i_lz_dist_minus1[1:0]};   o_dist_ebits <= 12'h0;                    o_dist_ecnt <= 4'h0;  end
        else if (i_lz_dist_minus1 < 14'd8   ) begin   o_dist_symbol <= {4'b0010, i_lz_dist_minus1[1]};     o_dist_ebits <= i_lz_dist_minus1[0];      o_dist_ecnt <= 4'h1;  end
        else if (i_lz_dist_minus1 < 14'd16  ) begin   o_dist_symbol <= {4'b0011, i_lz_dist_minus1[2]};     o_dist_ebits <= i_lz_dist_minus1[1:0];    o_dist_ecnt <= 4'h2;  end
        else if (i_lz_dist_minus1 < 14'd32  ) begin   o_dist_symbol <= {4'b0100, i_lz_dist_minus1[3]};     o_dist_ebits <= i_lz_dist_minus1[2:0];    o_dist_ecnt <= 4'h3;  end
        else if (i_lz_dist_minus1 < 14'd64  ) begin   o_dist_symbol <= {4'b0101, i_lz_dist_minus1[4]};     o_dist_ebits <= i_lz_dist_minus1[3:0];    o_dist_ecnt <= 4'h4;  end
        else if (i_lz_dist_minus1 < 14'd128 ) begin   o_dist_symbol <= {4'b0110, i_lz_dist_minus1[5]};     o_dist_ebits <= i_lz_dist_minus1[4:0];    o_dist_ecnt <= 4'h5;  end
        else if (i_lz_dist_minus1 < 14'd256 ) begin   o_dist_symbol <= {4'b0111, i_lz_dist_minus1[6]};     o_dist_ebits <= i_lz_dist_minus1[5:0];    o_dist_ecnt <= 4'h6;  end
        else if (i_lz_dist_minus1 < 14'd512 ) begin   o_dist_symbol <= {4'b1000, i_lz_dist_minus1[7]};     o_dist_ebits <= i_lz_dist_minus1[6:0];    o_dist_ecnt <= 4'h7;  end
        else if (i_lz_dist_minus1 < 14'd1024) begin   o_dist_symbol <= {4'b1001, i_lz_dist_minus1[8]};     o_dist_ebits <= i_lz_dist_minus1[7:0];    o_dist_ecnt <= 4'h8;  end
        else if (i_lz_dist_minus1 < 14'd2048) begin   o_dist_symbol <= {4'b1010, i_lz_dist_minus1[9]};     o_dist_ebits <= i_lz_dist_minus1[8:0];    o_dist_ecnt <= 4'h9;  end
        else if (i_lz_dist_minus1 < 14'd4096) begin   o_dist_symbol <= {4'b1011, i_lz_dist_minus1[10]};    o_dist_ebits <= i_lz_dist_minus1[9:0];    o_dist_ecnt <= 4'hA;  end
        else if (i_lz_dist_minus1 < 14'd8192) begin   o_dist_symbol <= {4'b1100, i_lz_dist_minus1[11]};    o_dist_ebits <= i_lz_dist_minus1[10:0];   o_dist_ecnt <= 4'hB;  end
        else                                  begin   o_dist_symbol <= {4'b1101, i_lz_dist_minus1[12]};    o_dist_ebits <= i_lz_dist_minus1[11:0];   o_dist_ecnt <= 4'hC;  end
    end


endmodule
