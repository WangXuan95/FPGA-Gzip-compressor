
module symbol_huffman_builder #(
    parameter SIMULATION = 0
) (
    input  wire        rstn,
    input  wire        clk,
    // input : symbol stream
    input  wire        i_sob,
    input  wire        i_symbol_en,
    input  wire [ 7:0] i_symbol_div2,
    // input : start to build tree signal
    input  wire        i_huffman_start,
    // output : huffman bits and length
    output wire [ 3:0] o_hlit_div2,
    output reg         o_huffman_en,
    output reg  [13:0] o_huffman_bits,
    output reg  [ 3:0] o_huffman_len,
    output reg         o_huffman_st
);



initial o_huffman_en   = 1'b0;
initial o_huffman_bits = 14'h0;
initial o_huffman_len  = 4'h0;
initial o_huffman_st   = 1'b0;


localparam [          8:0] EOB_SYMBOL      = 9'd256;                                      // end_of_block symbol

localparam                 HIST_ITEM_COUNT = 143;                                         // two symbols shares a histogram item (286/2=143), the goal is to save LUT
localparam                 MAX_DEPTH       = 14;                                          // max huffman tree depth

localparam                 HIST_BITS          = 11;
localparam [         15:0] HIST2_INIT_VALUE   = 16'h1;
localparam [         15:0] HIST1_INIT_VALUE   = 16'h8000 + (HIST2_INIT_VALUE << (16-HIST_BITS));
localparam [HIST_BITS-1:0] INVALID_HIST2_ITEM = 'hFFFFFFFF;



// input D, for better timing
reg         d_sob           = 1'b0;
reg         d_symbol_en     = 1'b0;
reg  [ 7:0] d_symbol_div2   = 8'h0;
reg         d_huffman_start = 1'b0;

always @ (posedge clk) begin
    d_sob           <= i_sob;
    d_symbol_en     <= i_symbol_en;
    d_symbol_div2   <= i_symbol_div2;
    d_huffman_start <= i_huffman_start;
end



integer i;                                                                                // not real registers, only temoporary value


reg [15:0] histogram1 [HIST_ITEM_COUNT-1:0];                                              // 16bit * 143 register array : {1bit disable, 15bit count}, to count the frequency of each symbol

always @ (posedge clk)
    if (d_symbol_en) begin
        if (d_sob) begin                                                                  // meet the first symbol in block
            for (i=0; i<HIST_ITEM_COUNT; i=i+1) histogram1[i] <= HIST1_INIT_VALUE;        //   all histogram item is clear to {disable, count=1}
            histogram1[EOB_SYMBOL[8:1]][15]   <= 1'b0;                                    //   enable the histogram item of EOB_SYMBOL
            histogram1[  d_symbol_div2][15]   <= 1'b0;                                    //   enable the histogram item of first symbol
        end else begin                                                                    // meet a symbol (not the first in block)
            histogram1[  d_symbol_div2][14:0] <= histogram1[d_symbol_div2][14:0] + 15'h1; //   histogram item count+1
            histogram1[  d_symbol_div2][15]   <= 1'b0;                                    //   enable histogram item of current symbol
        end
    end



localparam [3:0] S_IDLE           = 4'd0,       // IDLE
                 S_SEARCH         = 4'd1,       // searching for the 1st and 2nd minimum value in histogram
                 S_SEARCH_D1      = 4'd2,
                 S_SEARCH_D2      = 4'd3,
                 S_SEARCH_D3      = 4'd4,
                 S_SEARCH_D4      = 4'd5,
                 S_SEARCH_D5      = 4'd6,
                 S_SEARCH_D6      = 4'd7,
                 S_SEARCH_D7      = 4'd8,
                 S_SEARCH_DONE    = 4'd9,
                 S_BLCOUNT        = 4'd10,
                 S_BLCOUNT_DONE   = 4'd11,
                 S_GEN_BASE       = 4'd12,
                 S_GEN_BITS       = 4'd13,
                 S_GEN_BITS_DONE  = 4'd14;


reg  [ 3:0] state       = S_IDLE;
reg  [ 7:0] epoch       = 8'h0;                   // searching epoch count (when state=S_SEARCH), for 143 symbols, we need 142 epoches (actually run 143 epoches)

reg  [ 4:0] search_c0   = 5'h0;                   // c means counter
reg  [ 4:0] search_c1   = 5'h0;
reg  [ 4:0] search_c2   = 5'h0;
reg  [ 4:0] search_c3   = 5'h0;
reg  [ 4:0] search_c4   = 5'h0;
reg  [ 4:0] search_c5   = 5'h0;
reg  [ 4:0] search_c6   = 5'h0;
reg         search_e1   = 1'b0;
reg         search_e2   = 1'b0;
reg         search_e3   = 1'b0;
reg         search_e4   = 1'b0;
reg         search_e5   = 1'b0;
reg         search_e6   = 1'b0;

reg  [ 7:0] blcount_c0  = 8'h0;
reg  [ 7:0] blcount_c1  = 8'h0;
reg         blcount_e1  = 1'b0;
reg  [ 3:0] gen_base_c0 = 4'h0;
reg         gen_bits_e1 = 1'b0;

always @ (posedge clk or negedge rstn)                       // generate FSM and control signals
    if (~rstn) begin
        state       <= S_IDLE;
        epoch       <= 8'h0;
        search_c0   <= 5'h0;
        search_c1   <= 5'h0;
        search_c2   <= 5'h0;
        search_c3   <= 5'h0;
        search_c4   <= 5'h0;
        search_c5   <= 5'h0;
        search_c6   <= 5'h0;
        search_e1   <= 1'b0;
        search_e2   <= 1'b0;
        search_e3   <= 1'b0;
        search_e4   <= 1'b0;
        search_e5   <= 1'b0;
        search_e6   <= 1'b0;
        blcount_c0  <= 8'h0;
        blcount_c1  <= 8'h0;
        blcount_e1  <= 1'b0;
        gen_base_c0 <= 4'h0;
        gen_bits_e1 <= 1'b0;
    end else begin
        case (state)
            S_IDLE : begin
                if (d_huffman_start) state <= S_SEARCH;
                epoch     <= 8'h0;
                search_c0 <= 5'h0;
            end
            
            S_SEARCH :                                       // search_c0 = 0~17 in this state
                if (search_c0 < 5'd17) begin
                    search_c0 <= search_c0 + 5'h1;
                end else begin
                    state     <= S_SEARCH_D1;
                    search_c0 <= 5'h0;
                end
            
            S_SEARCH_D1 :
                state <= S_SEARCH_D2;
            
            S_SEARCH_D2 :
                state <= S_SEARCH_D3;
            
            S_SEARCH_D3 :
                state <= S_SEARCH_D4;
            
            S_SEARCH_D4 :
                state <= S_SEARCH_D5;
            
            S_SEARCH_D5 :
                state <= S_SEARCH_D6;
            
            S_SEARCH_D6 :
                state <= S_SEARCH_D7;
            
            S_SEARCH_D7 :                                    // at this state, we get the get the 1st and 2nd minimum index and value of histogram2
                if (epoch < (HIST_ITEM_COUNT-1) ) begin      // epoch : 0~142 (total 143 epoches)
                    state <= S_SEARCH;                       // back to S_SEARCH (the next epoch)
                    epoch <= epoch + 8'd1;
                end else begin
                    state <= S_SEARCH_DONE;                  // forward
                end
            
            S_SEARCH_DONE : begin
                state      <= S_BLCOUNT;
                blcount_c0 <= 8'h0;
            end
            
            S_BLCOUNT :                                      // blcount_c0 = 0~142 at this state
                if (blcount_c0 < (HIST_ITEM_COUNT-1) ) begin
                    blcount_c0 <= blcount_c0 + 8'h1;
                end else begin
                    state      <= S_BLCOUNT_DONE;
                    blcount_c0 <= 8'h0;
                end
            
            S_BLCOUNT_DONE : begin
                state       <= S_GEN_BASE;
                gen_base_c0 <= 4'h1;
            end
            
            S_GEN_BASE :                                     // gen_base_c0 = 1~(MAX_DEPTH-1) at this state
                if (gen_base_c0 < (MAX_DEPTH-1) ) begin
                    gen_base_c0 <= gen_base_c0 + 4'h1;
                end else begin
                    state       <= S_GEN_BITS;
                    gen_base_c0 <= 4'h1;
                end
            
            S_GEN_BITS :                                     // blcount_c0 = 0~142 at this state
                if (blcount_c0 < (HIST_ITEM_COUNT-1) ) begin
                    blcount_c0 <= blcount_c0 + 8'h1;
                end else begin
                    state      <= S_GEN_BITS_DONE;
                    blcount_c0 <= 8'h0;
                end
            
            default : // S_GEN_BITS_DONE
                state <= S_IDLE;
        endcase
        
        search_c1   <= search_c0;
        search_c2   <= search_c1;
        search_c3   <= search_c2;
        search_c4   <= search_c3;
        search_c5   <= search_c4;
        search_c6   <= search_c5;
        
        search_e1   <= (state == S_SEARCH);
        search_e2   <= search_e1;
        search_e3   <= search_e2;
        search_e4   <= search_e3;
        search_e5   <= search_e4;
        search_e6   <= search_e5;
        
        blcount_c1  <= blcount_c0;
        blcount_e1  <= (state == S_BLCOUNT);
        
        gen_bits_e1 <= (state == S_GEN_BITS);
    end





reg  [HIST_BITS-1:0] mv0, mv1, mv2, mv3, mv4, mv5, mv6, mv7;

reg  [          2:0] mi10, mi11, mi12, mi13, mi14, mi15, mi16, mi17;
reg  [HIST_BITS-1:0] mv10, mv11, mv12, mv13, mv14, mv15, mv16, mv17;

reg  [          2:0] mi20, mi21,             mi24, mi25;
reg  [HIST_BITS-1:0] mv20, mv21,             mv24, mv25;

reg  [          2:0] mi30, mi31,             mi34, mi35;
reg  [HIST_BITS-1:0] mv30, mv31,             mv34, mv35;

reg  [          2:0] mi40, mi41;
reg  [HIST_BITS-1:0] mv40, mv41;

reg  [          2:0] mi50, mi51;                                          // mv50 is the       1st minimum {index, value} of 0~7 histogram items
reg  [HIST_BITS-1:0] mv50, mv51;                                          // mv51 is the       2nd minimum {index, value} of 0~7 histogram items

reg  [          7:0] mia, mib;                                            // mva is the final 1st minimum {index, value} of 143 histogram items
reg  [HIST_BITS-1:0] mva, mvb;                                            // mvb is the final 2nd minimum {index, value} of 143 histogram items

reg  [          7:0] group_a;                                             // the       1st minimum histogram item's group (a group means a huffman sub-tree)
reg  [          7:0] group_b;                                             // the       2nd minimum histogram item's group

reg                  tree_merge  = 1'b0;                                  // when=1 pulse, merge two huffman sub-trees

reg  [HIST_BITS-1:0] histogram2   [HIST_ITEM_COUNT  :0];
reg  [          7:0] groups       [HIST_ITEM_COUNT-1:0];
reg  [          3:0] huffman_lens [HIST_ITEM_COUNT-1:0];


always @ (posedge clk)  /*if (search_e0)*/  begin
    mv0 <= histogram2[ {search_c0,3'h0} ];
    mv1 <= histogram2[ {search_c0,3'h1} ];
    mv2 <= histogram2[ {search_c0,3'h2} ];
    mv3 <= histogram2[ {search_c0,3'h3} ];
    mv4 <= histogram2[ {search_c0,3'h4} ];
    mv5 <= histogram2[ {search_c0,3'h5} ];
    mv6 <= histogram2[ {search_c0,3'h6} ];
    mv7 <= histogram2[ {search_c0,3'h7} ];
end


always @ (posedge clk)  /*if (search_e1)*/  begin  // Sorting Network layer 1 -------------------------------------------------------
    if (mv0 > mv1) {mi10, mv10, mi11, mv11} <= {3'd1, mv1, 3'd0, mv0};
    else           {mi10, mv10, mi11, mv11} <= {3'd0, mv0, 3'd1, mv1};
    if (mv2 > mv3) {mi12, mv12, mi13, mv13} <= {3'd3, mv3, 3'd2, mv2};
    else           {mi12, mv12, mi13, mv13} <= {3'd2, mv2, 3'd3, mv3};
end

always @ (posedge clk)  /*if (search_e2)*/  begin  // Sorting Network layer 2 -------------------------------------------------------
    if (mv11 > mv12) {mi21, mv21} <= {mi12, mv12};
    else             {mi21, mv21} <= {mi11, mv11};
    if (mv10 > mv13) {mi20, mv20} <= {mi13, mv13};
    else             {mi20, mv20} <= {mi10, mv10};
end

always @ (posedge clk)  /*if (search_e3)*/  begin  // Sorting Network layer 3 (same as layer 1) -------------------------------------
    if (mv20 > mv21) {mi30, mv30, mi31, mv31} <= {mi21, mv21, mi20, mv20};
    else             {mi30, mv30, mi31, mv31} <= {mi20, mv20, mi21, mv21};
end

always @ (posedge clk)  /*if (search_e1)*/  begin  // Sorting Network layer 1 -------------------------------------------------------
    if (mv4 > mv5) {mi14, mv14, mi15, mv15} <= {3'd5, mv5, 3'd4, mv4};
    else           {mi14, mv14, mi15, mv15} <= {3'd4, mv4, 3'd5, mv5};
    if (mv6 > mv7) {mi16, mv16, mi17, mv17} <= {3'd7, mv7, 3'd6, mv6};
    else           {mi16, mv16, mi17, mv17} <= {3'd6, mv6, 3'd7, mv7};
end

always @ (posedge clk)  /*if (search_e2)*/  begin  // Sorting Network layer 2 -------------------------------------------------------
    if (mv15 > mv16) {mi25, mv25} <= {mi16, mv16};
    else             {mi25, mv25} <= {mi15, mv15};
    if (mv14 > mv17) {mi24, mv24} <= {mi17, mv17};
    else             {mi24, mv24} <= {mi14, mv14};
end

always @ (posedge clk)  /*if (search_e3)*/  begin  // Sorting Network layer 3 (same as layer 1) -------------------------------------
    if (mv24 > mv25) {mi34, mv34, mi35, mv35} <= {mi25, mv25, mi24, mv24};
    else             {mi34, mv34, mi35, mv35} <= {mi24, mv24, mi25, mv25};
end


always @ (posedge clk)  /*if (search_e4)*/  begin  // Sorting Network layer 2 -------------------------------------------------------
    if (mv31 > mv34) {mi41, mv41} <= {mi34, mv34};
    else             {mi41, mv41} <= {mi31, mv31};
    if (mv30 > mv35) {mi40, mv40} <= {mi35, mv35};
    else             {mi40, mv40} <= {mi30, mv30};
end

always @ (posedge clk)  /* if (search_e5)*/ begin  // Sorting Network layer 3 (same as layer 1) -------------------------------------
    if (mv40 > mv41) {mi50, mv50, mi51, mv51} <= {mi41, mv41, mi40, mv40};
    else             {mi50, mv50, mi51, mv51} <= {mi40, mv40, mi41, mv41};
end


wire [          7:0] i0, i1;
wire [HIST_BITS-1:0] v0, v1;

assign {i1,v1} = (mvb > mv50) ? {search_c6, mi50, mv50} :
                                {            mib, mvb } ;

assign {i0,v0} = (mva > mv51) ? {search_c6, mi51, mv51} :
                                {            mia, mva } ;

always @ (posedge clk)
    if (~search_e6) begin
        mia <= 8'hFF;    mva <= INVALID_HIST2_ITEM;
        mib <= 8'hFF;    mvb <= INVALID_HIST2_ITEM;
    end else begin
        {mia, mva, mib, mvb} <= (v0 > v1) ? {i1,v1,i0,v0} : {i0,v0,i1,v1};
    end



always @ (posedge clk) begin
    tree_merge <= 1'b0;
    case (state)
        S_IDLE   :
            for (i=0; i<HIST_ITEM_COUNT; i=i+1)                             // initial :
                histogram2[i] <= histogram1[i][15:16-HIST_BITS];            // load histogram2 from histogram1
        
        S_SEARCH_D7 : begin                                                 // here we finally get the 1st and 2nd minimum index and value of histogram2
            if ( ~mvb[HIST_BITS-1] ) begin                                  // if the 2nd minimum value is enabled, which means there're two minimum value found, two small sub-trees (should be merge into one tree)
                tree_merge <= 1'b1;
                histogram2[mia]              <= mva + mvb;                  // merge them, add their count and write back to one
                histogram2[mib][HIST_BITS-1] <= 1'b1;                       //             disable another one
            end
        end
    endcase
    group_a <= groups[mia];
    group_b <= groups[mib];
    histogram2[HIST_ITEM_COUNT] <= INVALID_HIST2_ITEM;                      // histogram2[143] is always disabled
end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (state == S_SEARCH_D7) begin
        if ( ~mvb[HIST_BITS-1] ) begin
            if (mva + mvb >= (1<<HIST_BITS>>1) ) begin $display("*** error: histogram overflow when building huffman tree"); $stop; end
        end
        if ( mva[HIST_BITS-1] ) begin $display("*** error: failed to find the 1st minimum value"); $stop; end
    end
end endgenerate


always @ (posedge clk)
    if (state == S_IDLE) begin
        for (i=0; i<HIST_ITEM_COUNT; i=i+1) begin              // initial :
            groups      [i] <= (i[7:0]+8'd1);                  // assign different groups for all items
            huffman_lens[i] <= 4'h0;                           // clear all huffman bit len to 0
        end
    end else if (tree_merge) begin
        for (i=0; i<HIST_ITEM_COUNT; i=i+1) begin
            if ( groups[i] == group_a || groups[i] == group_b ) begin
                groups      [i] <= group_a;                    // merge group number
                huffman_lens[i] <= huffman_lens[i] + 4'h1;     // huffman tree depth increase
            end
        end
    end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (state == S_IDLE) begin
    end else if (tree_merge) begin
        for (i=0; i<HIST_ITEM_COUNT; i=i+1) begin
            if ( groups[i] == group_a || groups[i] == group_b ) begin
                if (huffman_lens[i] == (MAX_DEPTH-1)) begin $display("*** error : huffman tree depth overflow"); $stop; end
            end
        end
    end
end endgenerate



/*always @ (posedge clk) begin                                         //////////////////////////////////////////////
    if (state == S_IDLE && d_huffman_start) begin
        $write("symbol histogram     :");
        for (i=0; i<HIST_ITEM_COUNT; i=i+1)
            if (histogram1[i][15])
                $write("    NA");
            else
                $write(" %5d", histogram1[i]);
        $write("\n");
    end
    if (state == S_BLCOUNT_DONE) begin
        $write("symbol huffman length:");
        for (i=0; i<HIST_ITEM_COUNT; i=i+1)
            $write(" %5d", huffman_lens[i]);
        $write("\n");
    end
end*/



reg  [ 3:0] huffman_len;
reg  [ 3:0] hlit_div2;                                                                        // actually  hlit = {hlit_div2, 1'b1}

reg  [ 7:0] bl_count [MAX_DEPTH:0];
reg  [13:0] bl_base  [MAX_DEPTH:0];

always @ (posedge clk) huffman_len <= huffman_lens[blcount_c0];

always @ (posedge clk)
    if (state == S_SEARCH) begin                                                              // use S_SEARCH state to clear bl_count by the way
        bl_count[ search_c0[3:0] ] <= 8'h0;
    end else if (blcount_e1) begin                                                            // when blcount_e1=1 , blcount_c1 = 0~142
        bl_count[huffman_len] <= bl_count[huffman_len] + 8'h1;
        if (huffman_len != 4'h0)                                                              // when blcount_c1=128 , correspond to symbol 256 and 257 , let hlit_div2=0  , hlit=1
            hlit_div2 <= blcount_c1[3:0];                                                     // when blcount_c1=129 , correspond to symbol 258 and 259 , let hlit_div2=1  , hlit=3   ...
                                                                                              // when blcount_c1=142 , correspond to symbol 284 and 285 , let hlit_div2=14 , hlit=29
    end

always @ (posedge clk)
    if      (state == S_SEARCH)                                                               // use S_SEARCH state to clear search_c0 by the way
        bl_base[ search_c0[3:0] ] <= 14'h0;
    else if (state == S_GEN_BASE)                                                             // gen_base_c0 = 1~(MAX_DEPTH-1) at this state
        bl_base[gen_base_c0+4'h1] <= ( bl_base[gen_base_c0] + bl_count[gen_base_c0] ) << 1;
    else if (gen_bits_e1)
        bl_base[huffman_len] <= bl_base[huffman_len] + 14'h1;


always @ (posedge clk or negedge rstn)                                                        // output huffman bits and len
    if (~rstn) begin
        o_huffman_en   <= 1'b0;
        o_huffman_bits <= 14'h0;
        o_huffman_len  <= 4'h0;
    end else begin
        o_huffman_en   <= 1'b0;
        o_huffman_bits <= 14'h0;
        o_huffman_len  <= 4'h0;
        if (gen_bits_e1) begin                                                                // when gen_bits_e1=1 , blcount_c1 = 0~142
            //o_huffman_en <= ( blcount_c1 <= {4'b1000, hlit_div2} );
            o_huffman_en <= 1'b1;
            if (huffman_len != 4'h0) begin
                o_huffman_bits <= bl_base[huffman_len];
                o_huffman_len  <= huffman_len;
            end
        end
    end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (gen_bits_e1)
        if (huffman_len > MAX_DEPTH) begin $display("*** error : huffman depth overflow"); $stop; end
end endgenerate


always @ (posedge clk or negedge rstn)
    if (~rstn)
        o_huffman_st <= 1'b0;
    else
        o_huffman_st <= (state == S_BLCOUNT_DONE);
    

assign o_hlit_div2 = hlit_div2;


endmodule

