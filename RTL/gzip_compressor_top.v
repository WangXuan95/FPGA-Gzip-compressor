
//--------------------------------------------------------------------------------------------------------
// Module  : gzip_compressor_top
// Type    : synthesizable, IP's top
// Standard: Verilog 2001 (IEEE1364-2001)
// Author  : https://github.com/WangXuan95
// Function: GZIP compressor based on deflate compression algorithm
//           support 16384-byte-distance LZ77 compression,
//           and dynamic huffman compression
//--------------------------------------------------------------------------------------------------------

module gzip_compressor_top # (
    parameter          SIMULATION = 0     // 0:disable simulation assert (for normal use)  1: enable simulation assert (for simulation)
) (
    input  wire        rstn,              // asynchronous reset.   0:reset   1:normally use
    input  wire        clk,
    // input  stream : AXI-stream slave,  1 byte width (thus do not need tkeep and tstrb)
    output wire        i_tready,
    input  wire        i_tvalid,
    input  wire [ 7:0] i_tdata,
    input  wire        i_tlast,
    // output stream : AXI-stream master, 4 byte width
    input  wire        o_tready,
    output reg         o_tvalid,
    output reg  [31:0] o_tdata,
    output reg         o_tlast,
    output reg  [ 3:0] o_tkeep            // At the end of packet (tlast=1), tkeep may be 4'b0001, 4'b0011, 4'b0111, or 4'b1111. In other cases, tkeep can only be 4'b1111
);


wire        a_rdy;
wire        a_en;
wire        a_eos;
wire [ 7:0] a_byte;

wire        b_en;
wire        b_eos;
wire        b_eob;
wire [ 7:0] b_byte;

wire        c_en;
wire        c_eos;
wire        c_eob;
wire [ 7:0] c_byte;
wire        c_nlz_en;
wire        c_lz_en;
wire [ 7:0] c_lz_len_minus3;
wire [13:0] c_lz_dist_minus1;

wire        d_eos;
wire        d_eob;
wire [31:0] d_stream_len;
wire [31:0] d_stream_crc;
wire        d_symbol_en;
wire [ 8:0] d_symbol;
wire [ 4:0] d_len_ebits;
wire [ 4:0] d_dist_symbol;
wire [11:0] d_dist_ebits;

wire        e_stall_n;
wire        e_en;
wire [31:0] e_data;
wire [ 1:0] e_byte_cnt;
wire        e_last;

wire        f_en;
wire [31:0] f_data;
wire [ 1:0] f_byte_cnt;
wire        f_last;


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// input flow control
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
fifo2_for_input u_fifo2_for_input (
    .rstn               ( rstn                         ),
    .clk                ( clk                          ),
    .i_rdy              ( i_tready                     ),
    .i_en               ( i_tvalid                     ),
    .i_data             ( {i_tdata, i_tlast}           ),
    .o_rdy              ( a_rdy                        ),
    .o_en               ( a_en                         ),
    .o_data             ( {a_byte , a_eos}             )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// split input stream to one or multiple blocks (maximum length of each block is 16384 bytes)
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
split_stream_to_block u_split_stream_to_block (
    .rstn               ( rstn                         ),
    .clk                ( clk                          ),
    .i_en               ( a_en & a_rdy                 ),
    .i_eos              ( a_eos                        ),
    .i_byte             ( a_byte                       ),
    .o_en               ( b_en                         ),
    .o_eos              ( b_eos                        ),
    .o_eob              ( b_eob                        ),
    .o_byte             ( b_byte                       )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// LZ77 encode, input input stream, output LZ77 stream (byte, or {len, dist})
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
lz77_encoder #(
    .SIMULATION         ( SIMULATION                   )
) u_lz77_encoder (
    .rstn               ( rstn                         ),
    .clk                ( clk                          ),
    .i_en               ( b_en                         ),
    .i_eos              ( b_eos                        ),
    .i_eob              ( b_eob                        ),
    .i_byte             ( b_byte                       ),
    .o_en               ( c_en                         ),
    .o_eos              ( c_eos                        ),
    .o_eob              ( c_eob                        ),
    .o_byte             ( c_byte                       ),
    .o_nlz_en           ( c_nlz_en                     ),
    .o_lz77_en          ( c_lz_en                      ),
    .o_lz77_len_minus3  ( c_lz_len_minus3              ),
    .o_lz77_dist_minus1 ( c_lz_dist_minus1             )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// calculate stream length, and stream CRC32
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
calc_length_and_crc32 u_calc_length_and_crc32 (
    .rstn               ( rstn                         ),
    .clk                ( clk                          ),
    .i_en               ( c_en                         ),
    .i_eos              ( c_eos                        ),
    .i_eob              ( c_eob                        ),
    .i_byte             ( c_byte                       ),
    .o_eos              ( d_eos                        ),
    .o_eob              ( d_eob                        ),
    .o_stream_len       ( d_stream_len                 ),
    .o_stream_crc       ( d_stream_crc                 )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// convert LZ77 length to {symbol, len_ebits, len_ecnt}, convert LZ77 distance to {dist_symbol, dist_ebits, dist_ecnt}
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
convert_lz77_to_symbols u_convert_lz77_to_symbols (
    .rstn               ( rstn                         ),
    .clk                ( clk                          ),
    .i_byte             ( c_byte                       ),
    .i_nlz_en           ( c_nlz_en                     ),
    .i_lz_en            ( c_lz_en                      ),
    .i_lz_len_minus3    ( c_lz_len_minus3              ),
    .i_lz_dist_minus1   ( c_lz_dist_minus1             ),
    .o_symbol_en        ( d_symbol_en                  ),
    .o_symbol           ( d_symbol                     ),
    .o_len_ebits        ( d_len_ebits                  ),
    .o_len_ecnt         (                              ),
    .o_dist_symbol      ( d_dist_symbol                ),
    .o_dist_ebits       ( d_dist_ebits                 ),
    .o_dist_ecnt        (                              )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// huffman compressor, both static huffman and dynamic huffman are supported, including dynamic huffman tree buliding.
// the output stream is GZIP formatted, including GZIP header and footer
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
huffman_compress #(
    .SIMULATION         ( SIMULATION                   )
) u_huffman_compress (
    .rstn               ( rstn                         ),
    .clk                ( clk                          ),
    .i_stall_n          ( a_rdy                        ),        // when i_stall_n=0, indicate internal buffer is almost full, need to stall input stream (elastic)
    .i_eos              ( d_eos                        ),
    .i_eob              ( d_eob                        ),
    .i_stream_len       ( d_stream_len                 ),
    .i_stream_crc       ( d_stream_crc                 ),
    .i_symbol_en        ( d_symbol_en                  ),
    .i_symbol           ( d_symbol                     ),
    .i_len_ebits        ( d_len_ebits                  ),
    .i_dist_symbol      ( d_dist_symbol                ),
    .i_dist_ebits       ( d_dist_ebits                 ),
    .o_stall_n          ( e_stall_n                    ),
    .o_en               ( e_en                         ),
    .o_data             ( e_data                       ),
    .o_byte_cnt         ( e_byte_cnt                   ),
    .o_last             ( e_last                       )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// output stream buffer, the goal is elastic flow control
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
elastic_fifo_for_output #(
    .SIMULATION         ( SIMULATION                   )
) u_elastic_fifo_for_output (
    .rstn               ( rstn                         ),
    .clk                ( clk                          ),
    .i_stall_n          ( e_stall_n                    ),        // when i_elastic_full_n=0, indicate internal buffer is almost full, need to stall output stream (elastic)
    .i_data             ( {e_last, e_byte_cnt, e_data} ),
    .i_en               ( e_en                         ),
    .o_data             ( {f_last, f_byte_cnt, f_data} ),
    .o_en               ( f_en                         ),
    .o_rdy              ( ~o_tvalid | o_tready         )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// output stage, convert internal stream format to standard AXI-stream
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        o_tvalid <= 1'b0;
        o_tdata  <= 32'b0;
        o_tlast  <= 1'b0;
        o_tkeep  <= 4'b0;
    end else begin
        if (~o_tvalid | o_tready) begin
            o_tvalid <= f_en;
            o_tdata  <= f_data;
            if (f_en) begin
                o_tlast <= f_last;
                o_tkeep <= (f_byte_cnt==2'h3) ? 4'b1111 : (f_byte_cnt==2'h2) ? 4'b0111 : (f_byte_cnt==2'h1) ? 4'b0011 : 4'b0001 ;
            end else begin
                o_tlast <= 1'b0;
                o_tkeep <= 4'b0;
            end
        end
    end

initial o_tvalid = 1'b0;
initial o_tdata  = 32'b0;
initial o_tlast  = 1'b0;
initial o_tkeep  = 4'b0;


endmodule
