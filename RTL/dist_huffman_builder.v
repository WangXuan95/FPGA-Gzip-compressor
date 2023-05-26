
module dist_huffman_builder #(
    parameter SIMULATION = 0
) (
    input  wire        rstn,
    input  wire        clk,
    // input : symbol stream
    input  wire        i_sob,
    input  wire        i_symbol_en,
    input  wire [ 8:0] i_symbol,
    input  wire [ 4:0] i_dist_symbol,
    // input : start to build tree signal
    input  wire        i_huffman_start,
    // output : huffman bits and length
    output wire [ 4:0] o_hdist,
    output reg         o_huffman_en,
    output reg  [13:0] o_huffman_bits,
    output reg  [ 3:0] o_huffman_len,
    output reg         o_huffman_ed
);



initial o_huffman_en   = 1'b0;
initial o_huffman_bits = 14'h0;
initial o_huffman_len  = 4'h0;
initial o_huffman_ed   = 1'b0;


localparam [         15:0] WAIT_COUNT      = 2935;

localparam [          8:0] EOB_SYMBOL      = 9'd256;                                      // end_of_block symbol

localparam                 HIST_ITEM_COUNT = 29;
localparam                 MAX_DEPTH       = 14;                                          // max huffman tree depth

localparam                 HIST_BITS          = 13;
localparam [         15:0] HIST2_INIT_VALUE   = 16'h1;
localparam [         15:0] HIST1_INIT_VALUE   = 16'h8000 + (HIST2_INIT_VALUE << (16-HIST_BITS));
localparam [HIST_BITS-1:0] INVALID_HIST2_ITEM = 'hFFFFFFFF;



integer i;                                                                                // not real registers, only temoporary value


reg [15:0] histogram1 [HIST_ITEM_COUNT-1:0];                                              // 16bit * 29 register array : {1bit disable, 15bit count}, to count the frequency of each symbol

always @ (posedge clk)
    if (i_symbol_en) begin
        if (i_sob) begin                                                                  // meet the first symbol in block
            for (i=0; i<HIST_ITEM_COUNT; i=i+1) histogram1[i] <= HIST1_INIT_VALUE;        //   all histogram item is clear to {disable, count=1}
            histogram1[0][15] <= 1'b0;                                                    //   Intentionally enabling the first two to avoid the trouble of establishing a huffman tree in the future
            histogram1[1][15] <= 1'b0;
        end else if (i_symbol > EOB_SYMBOL) begin                                         // meet a LZ77 symbol
            histogram1[i_dist_symbol][14:0] <= histogram1[i_dist_symbol][14:0] + 15'h1;   //   histogram item count+1
            histogram1[i_dist_symbol][15]   <= 1'b0;                                      //   enable histogram item of current symbol
        end
    end



localparam [3:0] S_IDLE           = 4'd0,       // IDLE
                 S_SEARCH         = 4'd1,       // searching for the 1st and 2nd minimum value in histogram
                 S_SEARCH_D1      = 4'd2,
                 S_SEARCH_D2      = 4'd3,
                 S_SEARCH_DONE    = 4'd4,
                 S_BLCOUNT        = 4'd5,
                 S_BLCOUNT_DONE   = 4'd6,
                 S_GEN_BASE       = 4'd7,
                 S_WAIT           = 4'd8,
                 S_GEN_BITS       = 4'd9,
                 S_GEN_BITS_DONE  = 4'd10;


reg  [ 3:0] state       = S_IDLE;
reg  [ 4:0] epoch       = 5'h0;                   // searching epoch count (when state=S_SEARCH), for 29 dist_symbols, we need 28 epoches (actually run 29 epoches)
reg  [ 4:0] search_c0   = 5'h0;                   // c means counter
reg  [ 4:0] search_c1   = 5'h0;
reg         search_e1   = 1'b0;
reg  [ 4:0] blcount_c0  = 5'h0;
reg  [ 4:0] blcount_c1  = 5'h0;
reg         blcount_e1  = 1'b0;
reg  [ 3:0] gen_base_c0 = 4'h0;
reg         gen_bits_e1 = 1'b0;
reg  [15:0] wait_c0     = 16'h0;

always @ (posedge clk or negedge rstn)                       // generate FSM and control signals
    if (~rstn) begin
        state       <= S_IDLE;
        epoch       <= 5'h0;
        search_c0   <= 5'h0;
        search_c1   <= 5'h0;
        search_e1   <= 1'b0;
        blcount_c0  <= 5'h0;
        blcount_c1  <= 5'h0;
        blcount_e1  <= 1'b0;
        gen_base_c0 <= 4'h0;
        gen_bits_e1 <= 1'b0;
        wait_c0     <= 16'h0;
    end else begin
        case (state)
            S_IDLE : begin
                if (i_huffman_start) state <= S_SEARCH;
                epoch     <= 5'h0;
                search_c0 <= 5'h0;
            end
            
            S_SEARCH :                                       // search_c0 = 0~28 in this state
                if (search_c0 < (HIST_ITEM_COUNT-1) ) begin
                    search_c0 <= search_c0 + 5'h1;
                end else begin
                    state     <= S_SEARCH_D1;
                    search_c0 <= 5'h0;
                end
            
            S_SEARCH_D1 :
                state <= S_SEARCH_D2;
            
            S_SEARCH_D2 :                                    // at this state, we get the get the 1st and 2nd minimum index and value of histogram2
                if (epoch < (HIST_ITEM_COUNT-1) ) begin      // epoch : 0~28 (total 29 epoches)
                    state <= S_SEARCH;                       // back to S_SEARCH (the next epoch)
                    epoch <= epoch + 5'h1;
                end else begin
                    state <= S_SEARCH_DONE;                  // forward
                end
            
            S_SEARCH_DONE : begin
                state      <= S_BLCOUNT;
                blcount_c0 <= 5'h0;
            end
            
            S_BLCOUNT :                                      // blcount_c0 = 0~28 at this state
                if (blcount_c0 < (HIST_ITEM_COUNT-1) ) begin
                    blcount_c0 <= blcount_c0 + 5'h1;
                end else begin
                    state      <= S_BLCOUNT_DONE;
                    blcount_c0 <= 5'h0;
                end
            
            S_BLCOUNT_DONE : begin
                state       <= S_GEN_BASE;
                gen_base_c0 <= 4'h1;
            end
            
            S_GEN_BASE :                                     // gen_base_c0 = 1~(MAX_DEPTH-1) at this state
                if (gen_base_c0 < (MAX_DEPTH-1) ) begin
                    gen_base_c0 <= gen_base_c0 + 4'h1;
                end else begin
                    state       <= S_WAIT;
                    gen_base_c0 <= 4'h1;
                    wait_c0     <= 16'h0;
                end
            
            S_WAIT :
                if (wait_c0 < WAIT_COUNT)
                    wait_c0 <= wait_c0 + 16'h1;
                else
                    state   <= S_GEN_BITS;
            
            S_GEN_BITS :                                     // blcount_c0 = 0~28 at this state
                if (blcount_c0 < (HIST_ITEM_COUNT-1) ) begin
                    blcount_c0 <= blcount_c0 + 5'h1;
                end else begin
                    state      <= S_GEN_BITS_DONE;
                    blcount_c0 <= 5'h0;
                end
            
            default : // S_GEN_BITS_DONE
                state <= S_IDLE;
        endcase
        
        search_c1   <= search_c0;
        search_e1   <= (state == S_SEARCH);
        
        blcount_c1  <= blcount_c0;
        blcount_e1  <= (state == S_BLCOUNT);
        
        gen_bits_e1 <= (state == S_GEN_BITS);
    end



reg  [HIST_BITS-1:0] mv0;

reg  [ 4:0] mia, mib;                                          // the final 1st minimum {index, value} of 29 histogram items
reg  [HIST_BITS-1:0] mva, mvb;                                 // the final 2nd minimum {index, value} of 29 histogram items

reg  [ 4:0] group_a;                                           // the       1st minimum histogram item's group (a group means a huffman sub-tree)
reg  [ 4:0] group_b;                                           // the       2nd minimum histogram item's group

reg         tree_merge  = 1'b0;                                // when=1 pulse, merge two huffman sub-trees

reg  [HIST_BITS-1:0] histogram2   [HIST_ITEM_COUNT-1:0];
reg  [ 4:0] groups       [HIST_ITEM_COUNT-1:0];
reg  [ 3:0] huffman_lens [HIST_ITEM_COUNT-1:0];


always @ (posedge clk)
    mv0 <= histogram2[search_c0];

always @ (posedge clk)
    if (~search_e1) begin
        mia <= 5'h1F;        mva <= INVALID_HIST2_ITEM;
        mib <= 5'h1F;        mvb <= INVALID_HIST2_ITEM;
    end else if (mv0 < mva) begin
        mia <= search_c1;    mva <= mv0;
        mib <= mia;          mvb <= mva;
    end else if (mv0 < mvb) begin
        mib <= search_c1;    mvb <= mv0;
    end


always @ (posedge clk) begin
    tree_merge <= 1'b0;
    case (state)
        S_IDLE   :
            for (i=0; i<HIST_ITEM_COUNT; i=i+1)                         // initial :
                histogram2[i] <= histogram1[i][15:16-HIST_BITS];        // load histogram2 from histogram1
        
        S_SEARCH_D2 : begin                                             // here we finally get the 1st and 2nd minimum index and value of histogram2
            if ( ~mvb[HIST_BITS-1] ) begin                              // if the 2nd minimum value is enabled, which means there're two minimum value found, two small sub-trees (should be merge into one tree)
                tree_merge <= 1'b1;
                histogram2[mia]     <= mva + mvb;                       // merge them, add their count and write back to one
                histogram2[mib][HIST_BITS-1] <= 1'b1;                   //             disable another one
            end
        end
    endcase
    group_a <= groups[mia];
    group_b <= groups[mib];
end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (state == S_SEARCH_D2) begin
        if ( ~mvb[HIST_BITS-1] ) begin
            if (mva + mvb >= (1<<HIST_BITS>>1) ) begin $display("*** error: histogram overflow when building huffman tree"); $stop; end
        end
        if ( mva[HIST_BITS-1] ) begin $display("*** error: failed to find the 1st minimum value"); $stop; end
    end
end endgenerate


always @ (posedge clk)
    if (state == S_IDLE) begin
        for (i=0; i<HIST_ITEM_COUNT; i=i+1) begin              // initial :
            groups      [i] <= (i[4:0] + 5'd1);                // assign different groups for all items
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
    if (state == S_IDLE && i_huffman_start) begin
        $write("dist histogram     :");
        for (i=0; i<HIST_ITEM_COUNT; i=i+1)
            if (histogram1[i][15])
                $write("    NA");
            else
                $write(" %5d", histogram1[i]);
        $write("\n");
    end
    if (state == S_BLCOUNT_DONE) begin
        $write("dist huffman length:");
        for (i=0; i<HIST_ITEM_COUNT; i=i+1)
            $write(" %5d", huffman_lens[i]);
        $write("\n");
    end
end*/



reg  [ 3:0] huffman_len;
reg  [ 4:0] hdist;

reg  [ 4:0] bl_count [MAX_DEPTH:0];
reg  [13:0] bl_base  [MAX_DEPTH:0];

always @ (posedge clk) huffman_len <= huffman_lens[blcount_c0];

always @ (posedge clk)
    if (state == S_SEARCH) begin                                                              // use S_SEARCH state to clear bl_count by the way
        bl_count[ search_c0[3:0] ] <= 5'h0;
    end else if (blcount_e1) begin                                                            // when blcount_e1=1 , blcount_c1 = 0~28
        bl_count[huffman_len] <= bl_count[huffman_len] + 5'h1;
        if (huffman_len != 4'h0)
            hdist <= blcount_c1;
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
            //o_huffman_en <= ( blcount_c1 <= hdist );
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



reg huffman_ed = 1'b0;
always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        huffman_ed   <= 1'b0;
        o_huffman_ed <= 1'b0;
    end else begin
        huffman_ed   <= (state == S_GEN_BITS_DONE);
        o_huffman_ed <= huffman_ed;
    end


assign o_hdist = hdist;


endmodule
