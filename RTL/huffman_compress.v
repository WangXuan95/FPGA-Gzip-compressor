
module huffman_compress #(
    parameter SIMULATION = 0
) (
    input  wire        rstn,
    input  wire        clk,
    // signal to stall input stream (elastic)
    output reg         i_stall_n,
    // input : symbol stream
    input  wire        i_eos,
    input  wire        i_eob,
    input  wire [31:0] i_stream_len,
    input  wire [31:0] i_stream_crc,
    input  wire        i_symbol_en,
    input  wire [ 8:0] i_symbol,
    input  wire [ 4:0] i_len_ebits,
    input  wire [ 4:0] i_dist_symbol,
    input  wire [11:0] i_dist_ebits,
    // signal to stall output stream (elastic)
    input  wire        o_stall_n,
    // output : GZIP stream
    output wire        o_en,
    output wire [31:0] o_data,
    output wire [ 1:0] o_byte_cnt,
    output wire        o_last
);



localparam [ 8:0] EOB_SYMBOL              = 9'd256;
localparam [15:0] DYNAMIC_HUFFMAN_MIN_LEN = 16'd4096;




//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// definations and functions for data types
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

//                                           // type for one data
localparam [ 1:0] T_SYMBOL = 2'h0 ,
                  T_LZ77A  = 2'h1 ,
                  T_LZ77B  = 2'h2 ;

//                    low   high             // type for two adjacent data
localparam [ 1:0] T2_SYMBOL_SYMBOL = 2'h0 ,
                  T2_SYMBOL_LZ77A  = 2'h1 ,
                  T2_LZ77A_LZ77B   = 2'h2 ,
                  T2_LZ77B_SYMBOL  = 2'h3 ;


function  [ 1:0] get_type2_from_two_types;
    input [ 1:0] type_low;
    input [ 1:0] type_high;
begin
    get_type2_from_two_types = (type_low == T_SYMBOL && type_high == T_SYMBOL) ? T2_SYMBOL_SYMBOL :
                               (type_low == T_SYMBOL && type_high == T_LZ77A ) ? T2_SYMBOL_LZ77A  :
                               (type_low == T_LZ77A  && type_high == T_LZ77B ) ? T2_LZ77A_LZ77B   :
                             /*(type_low == T_LZ77B  && type_high == T_SYMBOL)*/ T2_LZ77B_SYMBOL  ;
                             // Note : other case is impossible
end
endfunction


function  [ 3:0] extract_two_types_from_type2;                   // return {type_low, type_high}
    input [ 1:0] type2;
begin
    extract_two_types_from_type2 = (type2 == T2_SYMBOL_SYMBOL) ? {T_SYMBOL, T_SYMBOL} :
                                   (type2 == T2_SYMBOL_LZ77A ) ? {T_SYMBOL, T_LZ77A } :
                                   (type2 == T2_LZ77A_LZ77B  ) ? {T_LZ77A , T_LZ77B } :
                                 /*(type2 == T2_LZ77B_SYMBOL )*/ {T_LZ77B , T_SYMBOL} ;
end
endfunction



//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// functions for getting extra bit count from symbol, reference to deflate algorithm specification (RFC1951)
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function  [ 2:0] get_len_extra_bitc_from_symbol;
    input [ 8:0] symbol;
begin
    if      (symbol < 9'd265) get_len_extra_bitc_from_symbol = 3'd0;
    else if (symbol < 9'd269) get_len_extra_bitc_from_symbol = 3'd1;
    else if (symbol < 9'd273) get_len_extra_bitc_from_symbol = 3'd2;
    else if (symbol < 9'd277) get_len_extra_bitc_from_symbol = 3'd3;
    else if (symbol < 9'd281) get_len_extra_bitc_from_symbol = 3'd4;
    else if (symbol < 9'd285) get_len_extra_bitc_from_symbol = 3'd5;
    else                      get_len_extra_bitc_from_symbol = 3'd0;
end
endfunction


function  [ 3:0] get_dist_extra_bitc_from_dist_symbol;
    input [ 4:0] dist_symbol;
begin
    if      (dist_symbol < 5'd4 ) get_dist_extra_bitc_from_dist_symbol = 4'd0;
    else if (dist_symbol < 5'd6 ) get_dist_extra_bitc_from_dist_symbol = 4'd1;
    else if (dist_symbol < 5'd8 ) get_dist_extra_bitc_from_dist_symbol = 4'd2;
    else if (dist_symbol < 5'd10) get_dist_extra_bitc_from_dist_symbol = 4'd3;
    else if (dist_symbol < 5'd12) get_dist_extra_bitc_from_dist_symbol = 4'd4;
    else if (dist_symbol < 5'd14) get_dist_extra_bitc_from_dist_symbol = 4'd5;
    else if (dist_symbol < 5'd16) get_dist_extra_bitc_from_dist_symbol = 4'd6;
    else if (dist_symbol < 5'd18) get_dist_extra_bitc_from_dist_symbol = 4'd7;
    else if (dist_symbol < 5'd20) get_dist_extra_bitc_from_dist_symbol = 4'd8;
    else if (dist_symbol < 5'd22) get_dist_extra_bitc_from_dist_symbol = 4'd9;
    else if (dist_symbol < 5'd24) get_dist_extra_bitc_from_dist_symbol = 4'd10;
    else if (dist_symbol < 5'd26) get_dist_extra_bitc_from_dist_symbol = 4'd11;
    else if (dist_symbol < 5'd28) get_dist_extra_bitc_from_dist_symbol = 4'd12;
    else                          get_dist_extra_bitc_from_dist_symbol = 4'd13;
end
endfunction




//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// function : bit reverse
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function  [14:0] bit_reverse;
    input [14:0] bits;
    input [ 3:0] cnt;
begin
    bit_reverse = (bits << (~cnt));
    bit_reverse = {bit_reverse[0], bit_reverse[1], bit_reverse[2], bit_reverse[3], bit_reverse[4], bit_reverse[5], bit_reverse[6], bit_reverse[7], bit_reverse[8], bit_reverse[9], bit_reverse[10], bit_reverse[11], bit_reverse[12], bit_reverse[13], bit_reverse[14]};
end
endfunction




//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// generate more informations for input stream
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
reg        i_sos = 1'b1;                                          // indicate current input symbol is at start_of_stream
reg        i_sob = 1'b1;                                          // indicate current input symbol is at start_of_block
reg        huffman_start = 1'b0;                                  // when meeting the end of a block that should apply dynamic huffman, huffman_start=1 pulses, start to build huffman tree

wire       i_dynamic;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        i_sos <= 1'b1;
        i_sob <= 1'b1;
        huffman_start <= 1'b0;
    end else begin
        if (i_symbol_en) begin
            i_sos <= i_eos;
            i_sob <= i_eob;
        end
        huffman_start <= i_symbol_en & i_eob & i_dynamic;         // start to build dynamic huffman tree only when huffman_start=1
    end




//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// build huffman tree
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

wire [ 3:0] symb_hlit_div2;
wire        symb_huffman_en;
wire [13:0] symb_huffman_bits;
wire [ 3:0] symb_huffman_len;
wire [ 4:0] dist_hdist;
wire        dist_huffman_en;
wire [13:0] dist_huffman_bits;
wire [ 3:0] dist_huffman_len;
wire        huffman_st;                                           // huffman_st=1 pulses when start of outputting huffman tree results
wire        huffman_ed;                                           // huffman_ed=1 pulses when end   of outputting huffman tree results

symbol_huffman_builder #(                                         // build symbol (literal) huffman tree, outputs huffman coding (bits, bits_length)
    .SIMULATION         ( SIMULATION           )
) u_symbol_huffman_builder ( 
    .rstn               ( rstn                 ),
    .clk                ( clk                  ),
    .i_sob              ( i_sob                ),
    .i_symbol_en        ( i_symbol_en          ),
    .i_symbol_div2      ( i_symbol[8:1]        ),
    .i_huffman_start    ( huffman_start        ),
    .o_hlit_div2        ( symb_hlit_div2       ),
    .o_huffman_en       ( symb_huffman_en      ),
    .o_huffman_bits     ( symb_huffman_bits    ),
    .o_huffman_len      ( symb_huffman_len     ),
    .o_huffman_st       ( huffman_st           )
);


dist_huffman_builder #(                                           // build dist_symbol huffman tree, outputs huffman coding (bits, bits_length)
    .SIMULATION         ( SIMULATION           )
) u_dist_huffman_builder (
    .rstn               ( rstn                 ),
    .clk                ( clk                  ),
    .i_sob              ( i_sob                ),
    .i_symbol_en        ( i_symbol_en          ),
    .i_symbol           ( i_symbol             ),
    .i_dist_symbol      ( i_dist_symbol        ),
    .i_huffman_start    ( huffman_start        ),
    .o_hdist            ( dist_hdist           ),
    .o_huffman_en       ( dist_huffman_en      ),
    .o_huffman_bits     ( dist_huffman_bits    ),
    .o_huffman_len      ( dist_huffman_len     ),
    .o_huffman_ed       ( huffman_ed           )
);




//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// write buffer_data, buffer_meta, and buffer_huffman
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

reg  [25:0] buffer_data    [16383:0];    // 26bit
reg  [65:0] buffer_meta    [ 1023:0];    // 66bit = 1bit finalblock  +  1bit dynamic  +  32bit stream_crc  +  32bit stream_len
reg  [17:0] buffer_huffman [ 4095:0];    // 18bit = 14bit huffman_bits  +  4bit huffman_len

reg  [ 4:0] w_len_ebits;
reg  [ 4:0] w_dist_symbol;
reg  [11:0] w_dist_ebits;

reg  [ 1:0] wtype = T_SYMBOL;

reg  [15:0] wptr                = 16'h0;
reg  [10:0] wptr_base           = 11'h0;
wire [15:0] wptr_delta          = (wptr - {wptr_base,5'd0});
reg  [10:0] wptr_huffman_base   = 11'h0;
reg  [ 7:0] wptr_huffman_offset = 8'h0;
reg  [10:0] wptr_commit         = 11'h0;
reg         w_wait_huffman      = 1'b0;

assign i_dynamic = (wptr_delta >= DYNAMIC_HUFFMAN_MIN_LEN) ;                             // apply dynamic huffman only when data length >= DYNAMIC_HUFFMAN_MIN_LEN

// buffer control logic --------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)                                                  
    if (~rstn) begin
        w_len_ebits   <= 5'h0;
        w_dist_symbol <= 5'h0;
        w_dist_ebits  <= 12'h0;
        wtype     <= T_SYMBOL;
        wptr      <= 16'h0;
        wptr_base <= 11'h0;
    end else begin
        case (wtype)
            T_SYMBOL :
                if (i_symbol_en) begin
                    if (i_symbol > EOB_SYMBOL) begin                                    // begin to input LZ77 dist and len
                        w_len_ebits   <= i_len_ebits;                                   // save it, use it futher in wtype=T_LZ77A
                        w_dist_symbol <= i_dist_symbol;                                 // save it, use it futher in wtype=T_LZ77A
                        w_dist_ebits  <= i_dist_ebits;                                  // save it, use it futher in wtype=T_LZ77B
                        wtype <= T_LZ77A;
                    end
                    
                    if (~i_eob) begin                                                   // not end of block
                        wptr       <= wptr + 16'h1;
                    end else begin                                                      // end of block, increase the base pointer
                        wptr[15:5] <= wptr[15:5] + 11'h1;
                        wptr[ 4:0] <= 5'h0;
                        wptr_base  <= wptr[15:5] + 11'h1;
                    end
                end
            T_LZ77A : begin
                wtype <= T_LZ77B;
                wptr  <= wptr + 16'h1;
            end
            default : begin  // T_LZ77B :
                wtype <= T_SYMBOL;
                wptr  <= wptr + 16'h1;
            end
        endcase
    end


// write to buffer_data --------------------------------------------------------------------------------------------------------
wire [11:0] wdata = (wtype == T_SYMBOL) ? {   i_eob, i_eos, i_sos, i_symbol} :          // 1+1+1+9 = 12 bits
                    (wtype == T_LZ77A ) ? {2'h0, w_len_ebits, w_dist_symbol} :          // 2+5+5   = 12 bits
                                                               w_dist_ebits  ;          // 12      = 12 bits

reg  [11:0] wdata_low;
reg  [ 1:0] wtype_low;
wire [ 1:0] wtype2 = get_type2_from_two_types(wtype_low, wtype);

always @ (posedge clk)
    if ( i_symbol_en || (wtype != T_SYMBOL) ) begin
        if ( ~wptr[0] ) begin                                                           // at low, save it temporarily, it will be write further (at next high)
            wdata_low <= wdata;
            wtype_low <= wtype;
        end
        
        if ( wptr[0] )                                                                  // at high, write {high, low} together
            buffer_data[wptr[14:1]] <= {          wtype2, wdata, wdata_low};
        else if (i_symbol_en & i_eob)                                                   // a special case : meeting EOB at low byte, write it immidiently
            buffer_data[wptr[14:1]] <= {T2_SYMBOL_SYMBOL, 12'h0, wdata    };
    end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (i_symbol_en && i_eob && wtype != T_SYMBOL) begin $display("wtype != T_SYMBOL when EOB"); $stop; end
end endgenerate



// write to buffer_meta --------------------------------------------------------------------------------------------------------
always @ (posedge clk)
    if ( i_symbol_en & i_eob )                                                           // at end of block
        buffer_meta[wptr_base[9:0]] <= {i_eos, i_dynamic, i_stream_crc, i_stream_len};   // this will write to the start of this block


// buffer control logic --------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        wptr_huffman_base   <= 11'h0;
        wptr_huffman_offset <= 8'h0;
        wptr_commit         <= 11'h0;
        w_wait_huffman      <= 1'b0;
    end else begin
        if (~w_wait_huffman) begin
            if ( i_symbol_en & i_eob & i_dynamic ) begin                 // at end of block, if this block uses dynamic huffman
                w_wait_huffman    <= 1'b1;                               // start to wait for building huffman tree (let w_wait_huffman=1)
                wptr_huffman_base <= wptr_base;
            end
            wptr_huffman_offset   <= 8'h0;
            wptr_commit           <= wptr_base;
        end else begin                                                   // when w_wait_huffman=1, continue wait for building huffman tree
            if (huffman_st)
                wptr_huffman_offset <= 8'h1;
            if (symb_huffman_en | dist_huffman_en)
                wptr_huffman_offset <= wptr_huffman_offset + 8'h1;
            if (huffman_ed)                                              // building huffman tree done
                w_wait_huffman <= 1'b0;                                  // let w_wait_huffman=0
        end
    end

generate if (SIMULATION) begin
always @ (posedge clk) begin
    if (~w_wait_huffman) if (huffman_st | symb_huffman_en | dist_huffman_en | huffman_ed) begin $display("***error : huffman_st=1 | symb_huffman_en=1 | dist_huffman_en=1 | huffman_ed=1 when w_wait_huffman=0"); $stop; end
    if (huffman_st      & symb_huffman_en) begin $display("***error : huffman_st==1     , symb_huffman_en==1 simutinously"); $stop; end
    if (huffman_st      & dist_huffman_en) begin $display("***error : huffman_st==1     , dist_huffman_en==1 simutinously"); $stop; end
    if (huffman_st      & huffman_ed     ) begin $display("***error : huffman_st==1     , huffman_ed==1      simutinously"); $stop; end
    if (symb_huffman_en & dist_huffman_en) begin $display("***error : symb_huffman_en==1, dist_huffman_en==1 simutinously"); $stop; end
    if (symb_huffman_en & huffman_ed     ) begin $display("***error : symb_huffman_en==1, huffman_ed==1      simutinously"); $stop; end
    if (dist_huffman_en & huffman_ed     ) begin $display("***error : dist_huffman_en==1, huffman_ed==1      simutinously"); $stop; end
end
end endgenerate


// write to buffer_huffman --------------------------------------------------------------------------------------------------------
wire [11:0] waddr_huffman = {wptr_huffman_base, 1'b0} + {4'h0, wptr_huffman_offset};

always @ (posedge clk)
    if      (huffman_st)
        buffer_huffman[waddr_huffman] <= {9'h0, dist_hdist , symb_hlit_div2};
    else if (symb_huffman_en)
        buffer_huffman[waddr_huffman] <= {symb_huffman_bits, symb_huffman_len};
    else if (dist_huffman_en)
        buffer_huffman[waddr_huffman] <= {dist_huffman_bits, dist_huffman_len};





//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// main FSM
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

localparam [3:0] R_IDLE          = 4'd0,
                 R_PREPARE       = 4'd1,
                 R_GZIP_HEADER_2 = 4'd2,
                 R_GZIP_HEADER_3 = 4'd3,
                 R_DYN_HEADER_1  = 4'd4,
                 R_DYN_HEADER_2  = 4'd5,
                 R_DYN_HEADER_3  = 4'd6,
                 R_DYN_OUTTREE   = 4'd7,
                 R_HUFFMAN_OUT   = 4'd8,
                 R_EOB_SYMBOL    = 4'd9,
                 R_POST_PARE     = 4'd10,
                 R_GZIP_FOOTER_1 = 4'd11,
                 R_GZIP_FOOTER_2 = 4'd12,
                 R_GZIP_FOOTER_3 = 4'd13;

reg  [ 3:0] r_state = R_IDLE;


// read pointers of buffer_data, buffer_meta, and buffer_huffman ------------------------------------------------------------------------------------------
reg  [14:0] rptr                    = 15'h0;                                                                       //        address for buffer_data
reg  [14:0] rptr_add1               = 15'h1;                                                                       // equivalent to assign rptr_add1=rptr+1  , but drived by register, the goal is to get better timing
wire [13:0] rptr_buffer_data        = ((r_state == R_HUFFMAN_OUT) && o_stall_n) ? rptr_add1[13:0] : rptr[13:0] ;   // actual address for buffer_data
reg  [10:0] rptr_base               = 11'h0;                                                                       //   base address for buffer_huffman
reg  [ 7:0] rptr_huffman_offset     = 8'h0;                                                                        // offset address for buffer_huffman
reg  [ 7:0] rptr_aux_huffman_offset = 8'h0;                                                                        // offset address for buffer_aux_huffman (auxiliary huffman tree buffer)
wire [11:0] raddr_huffman           = {rptr_base, 1'b0} + {4'h0, rptr_huffman_offset};                             // actual address for buffer_huffman


// read out from buffer_data ------------------------------------------------------------------------------------------
reg  [ 1:0] rtype2;
reg  [11:0] r_h_data, r_l_data;
always @ (posedge clk)
    {rtype2, r_h_data, r_l_data} <= buffer_data[rptr_buffer_data];


// read out from buffer_meta ------------------------------------------------------------------------------------------
reg         r_finalblock;
reg         r_dynamic;
reg  [31:0] r_stream_crc;
reg  [31:0] r_stream_len;
always @ (posedge clk)
    {r_finalblock, r_dynamic, r_stream_crc, r_stream_len} <= buffer_meta[ rptr[13:4] ];


// read out from buffer_huffman ------------------------------------------------------------------------------------------
reg  [13:0] r_huffman_bits;
reg  [ 3:0] r_huffman_len;
always @ (posedge clk)
    {r_huffman_bits, r_huffman_len} <= buffer_huffman[raddr_huffman];


// auxiliary huffman tree buffer, only need to save one huffman tree. Since we need to query the Huffman tree twice in a cycle in parallel ------------------------------------------------------------------------------------------
reg  [17:0] buffer_aux_huffman [172:1];         // address=1~143 : literal huffman tree    address=144~172 : dist huffman tree


// read out from buffer_aux_huffman ------------------------------------------------------------------------------------------
reg  [13:0] r_aux_huffman_bits;
reg  [ 3:0] r_aux_huffman_len;

always @ (posedge clk)
    {r_aux_huffman_bits, r_aux_huffman_len} <= buffer_aux_huffman[rptr_aux_huffman_offset];


// write to buffer_aux_huffman ------------------------------------------------------------------------------------------
always @ (posedge clk)
    if (r_state == R_DYN_OUTTREE)
        buffer_aux_huffman[rptr_aux_huffman_offset] <= {r_huffman_bits, r_huffman_len};


// check address for buffer_aux_huffman (only for simulation ------------------------------------------------------------------------------------------
generate if (SIMULATION) begin
always @ (posedge clk)
    if (r_state == R_DYN_OUTTREE)
        if ( 8'd1 > rptr_aux_huffman_offset || rptr_aux_huffman_offset > 8'd172 ) begin $display("*** error : buffer_aux_huffman address out of range"); $stop; end
end endgenerate



// disassemble rdata ------------------------------------------------------------------------------------------
wire [ 1:0] r_l_type;
wire [ 1:0] r_h_type;

assign {r_l_type, r_h_type} = extract_two_types_from_type2(rtype2);

wire        r_l_eob         = r_l_data[11]     && (r_l_type == T_SYMBOL);
wire        r_l_sos         = r_l_data[ 9]     && (r_l_type == T_SYMBOL);
wire [ 8:0] r_l_symbol      = r_l_data[ 8: 0]; // (r_l_type == T_SYMBOL)
wire [ 4:0] r_l_len_ebits   = r_l_data[ 9: 5]; // (r_l_type == T_LZ77A )
wire [ 4:0] r_l_dist_symbol = r_l_data[ 4: 0]; // (r_l_type == T_LZ77A )
wire [11:0] r_l_dist_ebits  = r_l_data;        // (r_l_type == T_LZ77B )

wire        r_h_eob         = r_h_data[11]     && (r_h_type == T_SYMBOL);
wire [ 8:0] r_h_symbol      = r_h_data[ 8: 0]; // (r_h_type == T_SYMBOL)
wire [ 4:0] r_h_len_ebits   = r_h_data[ 9: 5]; // (r_h_type == T_LZ77A )
wire [ 4:0] r_h_dist_symbol = r_h_data[ 4: 0]; // (r_h_type == T_LZ77A )
wire [11:0] r_h_dist_ebits  = r_h_data;        // (r_h_type == T_LZ77B )


// disassemble r_huffman_bits, r_huffman_len ------------------------------------------------------------------------------------------
wire [ 3:0] r_huffman_len_add1         = (r_huffman_len > 4'd0) ? (r_huffman_len + 4'd1) : 4'd0;
wire [ 3:0] r_huffman_len_add1_reverse = {r_huffman_len_add1[0], r_huffman_len_add1[1], r_huffman_len_add1[2], r_huffman_len_add1[3]};


// Temporarily saved data for information transfer between states of FSM ---------------------------------------------
reg         s_finalblock = 1'b0;
reg         s_dynamic    = 1'b0;
reg  [31:0] s_stream_crc = 32'h0;
reg  [31:0] s_stream_len = 32'h0;
reg  [ 3:0] s_hlit_div2  = 4'h0;
reg  [ 4:0] s_hdist      = 5'h0;


// output stream stage A (further processing is needed) ---------------------------------------------
reg         a_align    = 1'b0;
reg         a_eos      = 1'b0;
reg         a_en       = 1'b0;
reg  [31:0] a_bits     = 'h0;
reg  [ 5:0] a_bitc     = 6'h0;

reg         a_dynamic  = 1'b0;

reg         a_l_en     = 1'b0;
reg  [ 1:0] a_l_type   = T_SYMBOL;
reg  [ 8:0] a_l_symbol = 9'h0;
reg  [11:0] a_l_ebits  = 12'h0;

reg         a_h_en     = 1'b0;
reg  [ 1:0] a_h_type   = T_SYMBOL;
reg  [ 8:0] a_h_symbol = 9'h0;
reg  [11:0] a_h_ebits  = 12'h0;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        r_state <= R_IDLE;
        
        rptr                    <= 15'h0;
        rptr_add1               <= 15'h1;
        rptr_base               <= 11'h0;
        rptr_huffman_offset     <= 8'h0;
        rptr_aux_huffman_offset <= 8'h0;
        
        s_finalblock <= 1'b0;
        s_dynamic    <= 1'b0;
        s_stream_crc <= 32'h0;
        s_stream_len <= 32'h0;
        s_hlit_div2  <= 4'h0;
        s_hdist      <= 5'h0;
        
        a_align    <= 1'b0;
        a_eos      <= 1'b0;
        a_en       <= 1'b0;
        a_bits     <= 'h0;
        a_bitc     <= 6'h0;
        a_dynamic  <= 1'b0;
        a_l_en     <= 1'b0;
        a_l_type   <= T_SYMBOL;
        a_l_symbol <= 9'h0;
        a_l_ebits  <= 12'h0;
        a_h_en     <= 1'b0;
        a_h_type   <= T_SYMBOL;
        a_h_symbol <= 9'h0;
        a_h_ebits  <= 12'h0;
    end else begin
        a_align    <= 1'b0;
        a_eos      <= 1'b0;
        a_en       <= 1'b0;
        a_bits     <= 'h0;
        a_bitc     <= 6'h0;
        a_l_en     <= 1'b0;
        a_l_type   <= T_SYMBOL;
        a_l_symbol <= 9'h0;
        a_l_ebits  <= 12'h0;
        a_h_en     <= 1'b0;
        a_h_type   <= T_SYMBOL;
        a_h_symbol <= 9'h0;
        a_h_ebits  <= 12'h0;
        
        case (r_state)
            R_IDLE   : if ( rptr[14:4] != wptr_commit ) begin                                              // buffer available (next block is ready for reading)
                r_state <= R_PREPARE;
            end
            
            R_PREPARE  : begin
                s_finalblock <= r_finalblock;
                s_dynamic    <= r_dynamic;
                s_stream_crc <= r_stream_crc;
                s_stream_len <= r_stream_len;
                s_hlit_div2  <= r_huffman_len;
                s_hdist      <= r_huffman_bits[4:0];
                
                if (r_l_sos) begin                                                                         // start_of_stream : send a GZIP header
                    a_en   <= 1'b1;
                    a_bits <= 'h00088B1F;                                                                  // the first 4 byte of GZIP header
                    a_bitc <= 6'd32;
                    r_state <= R_GZIP_HEADER_2;
                end else begin                                                                             // do not need to send GZIP header, directly start a block
                    a_en   <= 1'b1;
                    a_bits <= r_dynamic ? {29'h0, 2'd2, r_finalblock} : {29'h0, 2'd1, r_finalblock};       // 2'd1 means static huffman, 2'd2 means static huffman
                    a_bitc <= 6'd3;                                                                        // 3 bit block starter
                    r_state <= r_dynamic ? R_DYN_HEADER_1 : R_HUFFMAN_OUT;
                end
            end
            
            R_GZIP_HEADER_2 : begin
                a_en   <= 1'b1;
                a_bits <= 'h00000000;
                a_bitc <= 6'd32;
                r_state <= R_GZIP_HEADER_3;
            end
            
            R_GZIP_HEADER_3 : begin
                a_en   <= 1'b1;
                a_bits <= s_dynamic ? {13'h0, 2'd2, s_finalblock, 16'h0304} : {13'h0, 2'd1, s_finalblock, 16'h0304};   // 2'd1 means static huffman, 2'd2 means static huffman
                a_bitc <= 6'd19;
                r_state <= s_dynamic ? R_DYN_HEADER_1 : R_HUFFMAN_OUT;
            end
            
            R_DYN_HEADER_1 : begin
                a_en   <= 1'b1;
                a_bits <= {9'h0, 3'h0, 3'h0, 3'h0, 4'd15, s_hdist, s_hlit_div2, 1'b1};                                 // 3+3+3+4+5+5 = 23 bits
                a_bitc <= 6'd23;
                r_state <= R_DYN_HEADER_2;
            end
            
            R_DYN_HEADER_2 : begin
                rptr_huffman_offset     <= 8'h1;
                rptr_aux_huffman_offset <= 8'h1;
                a_en   <= 1'b1;
                a_bits <= {8'h0, 3'h4, 3'h4, 3'h4, 3'h4, 3'h4, 3'h4, 3'h4, 3'h4};                                      // 3*8 = 24 bits
                a_bitc <= 6'd24;
                r_state <= R_DYN_HEADER_3;
            end
            
            R_DYN_HEADER_3 : begin
                rptr_huffman_offset     <= 8'h2;
                rptr_aux_huffman_offset <= 8'h1;
                a_en   <= 1'b1;
                a_bits <= {8'h0, 3'h4, 3'h4, 3'h4, 3'h4, 3'h4, 3'h4, 3'h4, 3'h4};                                      // 3*8 = 24 bits
                a_bitc <= 6'd24;
                r_state <= R_DYN_OUTTREE;
            end
            
            R_DYN_OUTTREE : begin                                                                                      // rhoff_h∈[1,143] : literal huffman tree     rhoff_h∈[144,172] : dist huffman tree      Note that 172=143+29
                rptr_huffman_offset     <= rptr_huffman_offset + 8'h1;
                rptr_aux_huffman_offset <= rptr_huffman_offset;
                
                if ( rptr_aux_huffman_offset <= 8'd143 ) begin                                                         // $display("LIT  huffman bits=%04x  len=%2d", r_huffman_bits, r_huffman_len);
                    if ( (rptr_aux_huffman_offset-8'd1) <= {8'b1000, s_hlit_div2} ) begin
                        a_en   <= 1'b1;
                        a_bits <= {24'h0, r_huffman_len_add1_reverse, r_huffman_len_add1_reverse};
                        a_bitc <= 4'd8;
                    end
                end else begin                                                                                         // $display("DIST huffman bits=%04x  len=%2d", r_huffman_bits, r_huffman_len);
                    if ( (rptr_aux_huffman_offset-8'd144) <= s_hdist ) begin
                        a_en   <= 1'b1;
                        a_bits <= {28'h0, r_huffman_len[0], r_huffman_len[1], r_huffman_len[2], r_huffman_len[3]};     // Here, bit reverse is required before sending, since huffman_len is also huffman encoded. However, this implementation does not actually perform huffman compression on huffman_len, so huffman code is just the reverse of the original code.
                        a_bitc <= 4'd4;
                    end
                end
                
                if ( rptr_aux_huffman_offset >= 8'd172 )
                    r_state <= R_HUFFMAN_OUT;
            end
            
            R_HUFFMAN_OUT : begin
                a_dynamic <= s_dynamic;
                if (o_stall_n) begin
                    rptr_huffman_offset     <= (r_l_type==T_SYMBOL) ? (8'd1+r_l_symbol[8:1]) : (r_l_type==T_LZ77A) ? (8'd144+r_l_dist_symbol) : 8'h0;
                    rptr_aux_huffman_offset <= (r_h_type==T_SYMBOL) ? (8'd1+r_h_symbol[8:1]) : (r_h_type==T_LZ77A) ? (8'd144+r_h_dist_symbol) : 8'h0;
                    
                    a_l_en     <= 1'b1;
                    a_l_type   <=  r_l_type;
                    a_l_ebits  <= (r_l_type==T_SYMBOL) ? 12'h0      : (r_l_type==T_LZ77A) ? r_l_len_ebits   : r_l_dist_ebits;
                    a_l_symbol <= (r_l_type==T_SYMBOL) ? r_l_symbol : (r_l_type==T_LZ77A) ? r_l_dist_symbol : 9'h0;
                    
                    a_h_en     <= ~r_l_eob;                                                                                // if meet end_of_block at low, high is not valid 
                    a_h_type   <=  r_h_type;
                    a_h_ebits  <= (r_h_type==T_SYMBOL) ? 12'h0      : (r_h_type==T_LZ77A) ? r_h_len_ebits   : r_h_dist_ebits;
                    a_h_symbol <= (r_h_type==T_SYMBOL) ? r_h_symbol : (r_h_type==T_LZ77A) ? r_h_dist_symbol : 9'h0;
                    
                    if ( r_l_eob | r_h_eob ) begin
                        r_state <= R_EOB_SYMBOL;
                    end else begin
                        rptr      <= rptr_add1;
                        rptr_add1 <= rptr_add1 + 14'd1;
                    end
                end
            end
            
            R_EOB_SYMBOL : begin
                a_l_en     <= 1'b1;
                a_l_type   <= T_SYMBOL;
                a_l_symbol <= EOB_SYMBOL;
                rptr_huffman_offset <= (8'd1 + EOB_SYMBOL[8:1]);
                r_state <= R_POST_PARE;
            end
            
            R_POST_PARE : begin
                rptr     [14:4]         <= rptr[14:4] + 11'd1;                                                             // reset pointers
                rptr     [ 3:0]         <= 4'd0;                                                                           // reset pointers
                rptr_add1[14:4]         <= rptr[14:4] + 11'd1;                                                             // reset pointers
                rptr_add1[ 3:0]         <= 4'd1;                                                                           // reset pointers
                rptr_base               <= rptr[14:4] + 11'd1;                                                             // reset pointers
                rptr_huffman_offset     <= 8'h0;                                                                           // reset pointers
                rptr_aux_huffman_offset <= 8'h0;                                                                           // reset pointers
                
                a_align <= s_finalblock;                                                                                   // if a GZIP footer should be outputed, we need to align the stream to byte (8-bit)
                r_state <= s_finalblock ? R_GZIP_FOOTER_1 : R_IDLE;
            end
            
            R_GZIP_FOOTER_1 : begin
                a_en   <= 1'b1;
                a_bits <= s_stream_crc;
                a_bitc <= 6'd32;
                r_state <= R_GZIP_FOOTER_2;
            end
            
            R_GZIP_FOOTER_2 : begin
                a_eos  <= 1'b1;
                a_en   <= 1'b1;
                a_bits <= s_stream_len;
                a_bitc <= 6'd32;
                r_state <= R_GZIP_FOOTER_3;
            end
            
            R_GZIP_FOOTER_3 : begin
                a_eos  <= 1'b1;
                r_state <= R_IDLE;
            end
            
            default :
                r_state <= R_IDLE;
        endcase
    end


generate if (SIMULATION) begin
wire r_l_eos = r_l_data[10] && (r_l_type == T_SYMBOL);
wire r_h_eos = r_h_data[10] && (r_h_type == T_SYMBOL);
always @ (posedge clk) begin
    if (r_state == R_IDLE) begin
        if (rptr[ 3:0]              !== 4'd0     ) begin $display("rptr[3:0] != 0                at r_state == R_IDLE"); $stop; end
        if (rptr[14:4]              !== rptr_base) begin $display("rptr[14:4] != rptr_base       at r_state == R_IDLE"); $stop; end
        if (rptr_huffman_offset     !== 8'h0     ) begin $display("rptr_huffman_offset     !== 0 at r_state == R_IDLE"); $stop; end
        if (rptr_aux_huffman_offset !== 8'h0     ) begin $display("rptr_aux_huffman_offset !== 0 at r_state == R_IDLE"); $stop; end
    end
    if (r_state == R_HUFFMAN_OUT) begin
        if ( r_l_eos &&            ~s_finalblock) begin $display("*** error : meet EOS, but s_finalblock=0"); $stop; end
        if ( r_h_eos &&            ~s_finalblock) begin $display("*** error : meet EOS, but s_finalblock=0"); $stop; end
        if ( r_l_eob && ~r_l_eos && s_finalblock) begin $display("*** error : EOS=0, but s_finalblock=1"   ); $stop; end
        if ( r_h_eob && ~r_h_eos && s_finalblock) begin $display("*** error : EOS=0, but s_finalblock=1"   ); $stop; end
    end
end

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
    end else begin
        if ( (rptr+14'd1) !== rptr_add1 ) begin $display("*** error : (rptr+14'd1) !== rptr_add1"); $stop; end
    end
end endgenerate




//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// output stream stage B : query static huffman table (if needed)
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
wire [ 8:0] b_l_sta_bits;
wire [ 3:0] b_l_sta_len;
wire [ 8:0] b_h_sta_bits;
wire [ 3:0] b_h_sta_len;

static_huffman_table u_l_static_huffman_table (
    .clk              ( clk            ),
    .i_symbol         ( a_l_symbol     ),
    .o_huffman_bits   ( b_l_sta_bits   ),
    .o_huffman_len    ( b_l_sta_len    )
);

static_huffman_table u_h_static_huffman_table (
    .clk              ( clk            ),
    .i_symbol         ( a_h_symbol     ),
    .o_huffman_bits   ( b_h_sta_bits   ),
    .o_huffman_len    ( b_h_sta_len    )
);

reg         b_align    = 1'b0;
reg         b_eos      = 1'b0;
reg         b_en       = 1'b0;
reg  [31:0] b_bits     = 'h0;
reg  [ 5:0] b_bitc     = 6'h0;

reg         b_dynamic  = 1'b0;

reg         b_l_en     = 1'b0;
reg  [ 1:0] b_l_type   = T_SYMBOL;
reg  [ 8:0] b_l_symbol = 9'h0;
reg  [11:0] b_l_ebits  = 12'h0;
reg  [ 3:0] b_l_ecnt   = 4'h0;

reg         b_h_en     = 1'b0;
reg  [ 1:0] b_h_type   = T_SYMBOL;
reg  [ 8:0] b_h_symbol = 9'h0;
reg  [11:0] b_h_ebits  = 12'h0;
reg  [ 3:0] b_h_ecnt   = 4'h0;

reg  [ 8:0] last_h_symbol = 9'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        b_align    <= 1'b0;
        b_eos      <= 1'b0;
        b_en       <= 1'b0;
        b_bits     <= 'h0;
        b_bitc     <= 6'h0;
        b_dynamic  <= 1'b0;
        b_l_en     <= 1'b0;
        b_l_type   <= T_SYMBOL;
        b_l_symbol <= 9'h0;
        b_l_ebits  <= 12'h0;
        b_l_ecnt   <= 4'h0;
        b_h_en     <= 1'b0;
        b_h_type   <= T_SYMBOL;
        b_h_symbol <= 9'h0;
        b_h_ebits  <= 12'h0;
        b_h_ecnt   <= 4'h0;
        last_h_symbol <= 9'h0;
    end else begin
        b_align    <= a_align;
        b_eos      <= a_eos;
        b_en       <= a_en;
        b_bits     <= a_bits;
        b_bitc     <= a_bitc;
        
        b_dynamic  <= a_dynamic;
        
        b_l_en     <= a_l_en;
        b_l_type   <= a_l_type;
        b_l_symbol <= a_l_en ? a_l_symbol : 9'h0;
        b_l_ebits  <= a_l_en ? a_l_ebits  : 12'h0;
        b_l_ecnt   <= a_l_en ? ( (a_l_type==T_LZ77A) ? get_len_extra_bitc_from_symbol      (last_h_symbol     ) :
                                 (a_l_type==T_LZ77B) ? get_dist_extra_bitc_from_dist_symbol(last_h_symbol[4:0]) :
                                                       4'h0                                                      ) : 4'h0;
        
        b_h_en     <= a_h_en;
        b_h_type   <= a_h_type;
        b_h_symbol <= a_h_en ? a_h_symbol : 9'h0;
        b_h_ebits  <= a_h_en ? a_h_ebits  : 12'h0;
        b_h_ecnt   <= a_h_en ? ( (a_h_type==T_LZ77A) ? get_len_extra_bitc_from_symbol      (a_l_symbol     ) :
                                 (a_h_type==T_LZ77B) ? get_dist_extra_bitc_from_dist_symbol(a_l_symbol[4:0]) :
                                                       4'h0                                                      ) : 4'h0;
        
        if (a_h_en) last_h_symbol <= a_h_symbol;
    end




//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// output stream stage C : get huffman coding {bits, cnt}
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
reg         c_align = 1'b0;
reg         c_eos   = 1'b0;
reg         c_en    = 1'b0;
reg  [31:0] c_bits  = 'h0;
reg  [ 5:0] c_bitc  = 6'h0;

reg         c_l_en    = 1'b0;
reg  [11:0] c_l_ebits = 12'h0;
reg  [ 3:0] c_l_ecnt  = 4'h0;
reg  [14:0] c_l_bits  = 15'h0;
reg  [ 3:0] c_l_cnt   = 4'h0;

reg         c_h_en    = 1'b0;
reg  [11:0] c_h_ebits = 12'h0;
reg  [ 3:0] c_h_ecnt  = 4'h0;
reg  [14:0] c_h_bits  = 15'h0;
reg  [ 3:0] c_h_cnt   = 4'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        c_align <= 1'b0;
        c_eos   <= 1'b0;
        c_en    <= 1'b0;
        c_bits  <= 'h0;
        c_bitc  <= 6'h0;

        c_l_en    <= 1'b0;
        c_l_ebits <= 12'h0;
        c_l_ecnt  <= 4'h0;
        c_l_bits  <= 15'h0;
        c_l_cnt   <= 4'h0;

        c_h_en    <= 1'b0;
        c_h_ebits <= 12'h0;
        c_h_ecnt  <= 4'h0;
        c_h_bits  <= 15'h0;
        c_h_cnt   <= 4'h0;
    end else begin
        c_align <= b_align;
        c_eos   <= b_eos;
        c_en    <= b_en;
        c_bits  <= b_bits;
        c_bitc  <= b_bitc;
        
        c_l_en    <= b_l_en;
        c_l_ebits <= b_l_en ? b_l_ebits : 12'h0;
        c_l_ecnt  <= b_l_en ? b_l_ecnt  : 4'h0;
        
        if          (b_l_en && b_l_type==T_SYMBOL) begin
            if (b_dynamic) begin
                c_l_bits <= bit_reverse( {r_huffman_bits, b_l_symbol[0]}, r_huffman_len+4'd1 );
                c_l_cnt  <=                                               r_huffman_len+4'd1;
            end else begin
                c_l_bits <= {6'h0, b_l_sta_bits};
                c_l_cnt  <= b_l_sta_len;
            end
        end else if (b_l_en && b_l_type==T_LZ77A) begin
            if (b_dynamic) begin
                c_l_bits <= bit_reverse( {1'b0, r_huffman_bits}, r_huffman_len );
                c_l_cnt  <=                                      r_huffman_len;
            end else begin
                c_l_bits <= {10'h0, b_l_symbol[0], b_l_symbol[1], b_l_symbol[2], b_l_symbol[3], b_l_symbol[4]};
                c_l_cnt  <= 4'd5;
            end
        end else begin
            c_l_bits <= 15'h0;
            c_l_cnt  <= 4'd0;
        end
        
        c_h_en    <= b_h_en;
        c_h_ebits <= b_h_en ? b_h_ebits : 12'h0;
        c_h_ecnt  <= b_h_en ? b_h_ecnt  : 4'h0;
        
        if          (b_h_en && b_h_type==T_SYMBOL) begin
            if (b_dynamic) begin
                c_h_bits <= bit_reverse( {r_aux_huffman_bits, b_h_symbol[0]}, r_aux_huffman_len+4'd1 );
                c_h_cnt  <=                                                   r_aux_huffman_len+4'd1;
            end else begin
                c_h_bits <= {6'h0, b_h_sta_bits};
                c_h_cnt  <= b_h_sta_len;
            end
        end else if (b_h_en && b_h_type==T_LZ77A) begin
            if (b_dynamic) begin
                c_h_bits <= bit_reverse( {1'b0, r_aux_huffman_bits}, r_aux_huffman_len );
                c_h_cnt  <=                                          r_aux_huffman_len;
            end else begin
                c_h_bits <= {10'h0, b_h_symbol[0], b_h_symbol[1], b_h_symbol[2], b_h_symbol[3], b_h_symbol[4]};
                c_h_cnt  <= 4'd5;
            end
        end else begin
            c_h_bits <= 15'h0;
            c_h_cnt  <= 4'd0;
        end
    end




//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// output stream stage D : merge bits intra-cycle
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
reg         d_align = 1'b0;
reg         d_eos   = 1'b0;
reg         d_en    = 1'b0;
reg  [35:0] d_bits  = 36'h0;
reg  [ 5:0] d_bitc  = 6'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        d_align <= 1'b0;
        d_eos   <= 1'b0;
        d_en    <= 1'b0;
        d_bits  <= 36'h0;
        d_bitc  <= 6'h0;
    end else begin
        d_align <= c_align;
        d_eos   <= c_eos;
        if (c_en) begin
            d_en   <= 1'b1;
            d_bits <= {4'h0, c_bits};
            d_bitc <= c_bitc;
        end else begin
            d_en   <= c_l_en | c_h_en;
            d_bits <= ( {21'h0,c_h_bits} << ({2'h0,c_h_ecnt} + {2'h0,c_l_cnt} + {2'h0,c_l_ecnt}) ) | ( {24'h0,c_h_ebits} << ({2'h0,c_l_cnt} + {2'h0,c_l_ecnt}) ) | ( {21'h0,c_l_bits} << c_l_ecnt ) | c_l_ebits ;
            d_bitc <=   {2'h0, c_h_cnt}                                                              + {2'h0, c_h_ecnt}                                            + {2'h0, c_l_cnt}         + {2'h0, c_l_ecnt} ;
        end
    end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (c_l_en | c_h_en)
        if ( {2'h0, c_h_cnt} + {2'h0, c_h_ecnt} + {2'h0, c_l_cnt} + {2'h0, c_l_ecnt} > 6'd36 ) begin $display("*** error : bitc overflow"); $stop; end
end endgenerate




//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// output stream stage E : merge bits inter cycle, getting GZIP stream
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
reg  [ 5:0] rem_bitc = 6'h0;          // bit count left over from the previous cycle
reg  [34:0] rem_bits = 35'h0;         // bits      left over from the previous cycle

reg         e_en       = 1'b0;
reg  [31:0] e_data     = 32'h0;
reg  [ 1:0] e_byte_cnt = 2'h0;        // 0: 1 byte valid,   1: 2 bytes valid,   2: 3 bytes valid,   3: 4 bytes valid
reg         e_last     = 1'b0;

reg  [ 6:0] t_bitc;                   // not real register
reg  [66:0] t_bits;                   // not real register

always @ (*) begin
    t_bitc = { 1'b0, rem_bitc};
    t_bits = {32'h0, rem_bits};
    if (d_align) begin
        if (t_bitc[2:0] != 3'h0) begin
            t_bitc[6:3] = t_bitc[6:3] + 4'h1;
            t_bitc[2:0] = 3'h0;
        end
    end else if (d_en) begin
        t_bits = ( {31'h0, d_bits} << t_bitc ) | t_bits;
        t_bitc =                {1'b0,d_bitc } + t_bitc;
    end
end

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        rem_bitc   <= 6'h0;
        rem_bits   <= 35'h0;
        e_en       <= 1'b0;
        e_data     <= 32'h0;
        e_byte_cnt <= 2'h0;
        e_last     <= 1'b0;
    end else begin
        if ( t_bitc >= 7'd32 ) begin
            rem_bitc   <= t_bitc[5:0] - 6'd32;
            rem_bits   <= t_bits[66:32];
            e_data     <= t_bits[31:0];
            e_byte_cnt <= 2'h3;
            e_en       <= 1'b1;
            e_last     <= d_eos & (t_bitc == 7'd32);
        end else if (d_eos) begin
            rem_bitc   <= 6'h0;
            rem_bits   <= 35'h0;
            e_data     <= t_bits[31:0];
            e_byte_cnt <= (t_bitc > 7'd24) ? 2'h3 : (t_bitc > 7'd16) ? 2'h2 : (t_bitc > 7'd8) ? 2'h1 : 2'h0;
            e_en       <= (t_bitc > 7'd0);
            e_last     <= (t_bitc > 7'd0);
        end else begin
            rem_bitc   <= t_bitc[5:0];
            rem_bits   <= {3'h0, t_bits[31:0]};
            e_data     <= 32'h0;
            e_byte_cnt <= 2'h0;
            e_en       <= 1'b0;
            e_last     <= 1'b0;
        end
    end


generate if (SIMULATION) begin
always @ (posedge clk or negedge rstn)
    if (~rstn) begin
    end else begin
        t_bitc = { 1'b0, rem_bitc};
        if (d_align) begin
            if (t_bitc[2:0]!=3'h0) begin
                t_bitc[6:3] = t_bitc[6:3] + 4'h1;
                t_bitc[2:0] = 3'h0;
            end
            if (t_bitc > 7'd32) begin $display("*** error : align overflow"); $stop; end
        end else if (d_en) begin
            t_bitc = {1'b0,d_bitc } + t_bitc;
        end
        if ( t_bitc > 7'd67 ) begin $display("*** error : rem_bitc + d_bitc overflow 67"); $stop; end
    end
end endgenerate




//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// output signal to pins
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
assign o_en       = e_en;
assign o_data     = e_data;
assign o_byte_cnt = e_byte_cnt;
assign o_last     = e_last;




//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// generate stall signal (i_stall_n) for input stream : If the buffer of this module is almost full, let i_stall_n=0. If the buffer has enough space, release i_stall_n=1
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
localparam [15:0] THRESHOLD_SET_STALL   = 16'h7E00,
                  THRESHOLD_CLEAR_STALL = 16'h7A00,
                  THRESHOLD_OVERFLOW    = 16'h7F80;

wire [15:0] buffer_usage = (wptr - {rptr_base, 5'h0});

initial     i_stall_n = 1'b1;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        i_stall_n <= 1'b1;
    end else begin
        if (i_stall_n) begin
            if (buffer_usage >= THRESHOLD_SET_STALL  )
                i_stall_n <= 1'b0;
        end else begin
            if (buffer_usage <  THRESHOLD_CLEAR_STALL)
                i_stall_n <= 1'b1;
        end
    end




//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// report buffer usage, and report error when buffer overflows (only for simulation)
//----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
generate if (SIMULATION) begin
reg  [15:0] buffer_usage_max = 16'd128;
always @ (posedge clk) begin
    if ( buffer_usage >= buffer_usage_max ) begin
        buffer_usage_max = buffer_usage + 16'd128;
        //$display("huffman_compress : buffer_usage = %5d bytes", buffer_usage);
    end
    if ( buffer_usage >= THRESHOLD_OVERFLOW ) begin $display("*** error : buffer almost overflow"); $stop; end
end
end endgenerate


endmodule
