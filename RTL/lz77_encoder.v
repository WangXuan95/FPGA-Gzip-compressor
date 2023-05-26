
module lz77_encoder #(
    parameter SIMULATION = 0
) (
    input  wire        rstn,
    input  wire        clk,
    // input stream
    input  wire        i_en,
    input  wire        i_eos,           // end of stream (current byte is the last byte of this stream), a stream that is larger than 16384 bytes is splitted to multiple blocks (done by previous modules).
    input  wire        i_eob,           // end of block  (current byte is the last byte of this block) , a block must not be larger than 16384 bytes.
    input  wire [ 7:0] i_byte,
    // output stream
    output wire        o_en,
    output wire        o_eos,
    output wire        o_eob,
    output wire [ 7:0] o_byte,
    output wire        o_nlz_en,
    output wire        o_lz77_en,
    output wire [ 7:0] o_lz77_len_minus3,
    output wire [13:0] o_lz77_dist_minus1
);


localparam       HASH_BITS    = 12;

localparam [8:0] MAX_LZ77_LEN = 9'd258;



function  [HASH_BITS-1:0] hash;
    input [ 7:0] byte0, byte1, byte2;
    reg   [23:0] v;
    reg   [23:0] tmp;
begin
    v = {byte0, byte1, byte2};
    tmp  = v >> HASH_BITS;
    hash = v[HASH_BITS-1:0] + tmp[HASH_BITS-1:0]+ tmp[HASH_BITS:1];
end
endfunction



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// the following code are multiple pipeline stages, named : A,B,C,D,E,F,G,H,K,P,Q,R
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////



// stage A : pipeline global control -------------------------------------------------------------------------------
reg         a_during_block = 1'b0;
reg         a_pipe_en      = 1'b0;
reg         a_en           = 1'b0;
reg         a_eos          = 1'b0;
reg         a_eob          = 1'b0;
reg  [ 7:0] a_byte         = 8'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        a_during_block <= 1'b0;
        a_pipe_en      <= 1'b0;
        a_en           <= 1'b0;
        a_eos          <= 1'b0;
        a_eob          <= 1'b0;
        a_byte         <= 8'h0;
    end else begin
        if (~a_during_block) begin              // if not during a packet
            if (i_en & ~i_eob)                  // if meet a new packet, and its length is not only 1 byte
                a_during_block <= 1'b1;         // 
            a_pipe_en <= 1'b1;                  // when not during a packet, always run the pipeline, the goal is to flush the data remained in pipeline
            a_en      <= i_en;
        end else begin
            if (i_en & i_eob)
                a_during_block <= 1'b0;
            a_pipe_en <= i_en;
            a_en      <= 1'b1;
        end
        a_eos  <= i_en ? i_eos  : 1'b0;
        a_eob  <= i_en ? i_eob  : 1'b0;
        a_byte <= i_en ? i_byte : 8'h0;
    end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (i_en & i_eos & ~i_eob) begin  $display("*** error : meet i_eos=1 but i_eob=0");  $stop;  end
end endgenerate



// stage B : multi-stages latency -------------------------------------------------------------------------------
localparam LATENCY = 23;

integer i;

reg  [LATENCY:0] b_en;
reg  [LATENCY:0] b_eos;
reg  [LATENCY:0] b_eob;
reg  [      7:0] b_byte [LATENCY:0];

initial for (i=0; i<=LATENCY; i=i+1) begin
            b_en  [i] = 1'h0;
            b_eos [i] = 1'h0;
            b_eob [i] = 1'h0;
            b_byte[i] = 8'h0;
        end

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        for (i=0; i<=LATENCY; i=i+1) begin
            b_en  [i] <= 1'h0;
            b_eos [i] <= 1'h0;
            b_eob [i] <= 1'h0;
            b_byte[i] <= 8'h0;
        end
    end else begin
        if (a_pipe_en) begin
            for (i=0; i<LATENCY; i=i+1) begin
                b_en  [i] <= b_en  [i+1];
                b_eos [i] <= b_eos [i+1];
                b_eob [i] <= b_eob [i+1];
                b_byte[i] <= b_byte[i+1];
            end
            b_en  [LATENCY] <= a_en;
            b_eos [LATENCY] <= a_eos;
            b_eob [LATENCY] <= a_eob;
            b_byte[LATENCY] <= a_byte;
        end
    end



// stage C : calculate hash and count block bytes -------------------------------------------------------------------------------
reg                  c_en      = 1'b0;
reg                  c_eos     = 1'b0;
reg                  c_eob     = 1'b0;
reg  [          7:0] c_byte    = 8'h0;
reg                  c_hash_en = 1'b0;
reg  [HASH_BITS-1:0] c_hash    = 0;
reg  [         13:0] c_ptr     = 14'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        c_en      <= 1'b0;
        c_eos     <= 1'b0;
        c_eob     <= 1'b0;
        c_byte    <= 8'h0;
        c_hash_en <= 1'b0;
        c_hash    <= 0;
        c_ptr     <= 14'h0;
    end else begin
        if (a_pipe_en) begin
            c_en      <= b_en[0];
            c_eos     <= b_eos[0];
            c_eob     <= b_eob[0];
            c_byte    <= b_byte[0];
            c_hash_en <= b_en[0] & b_en[1] & b_en[2] & ~b_eob[0] & ~b_eob[1] & ~b_eob[2];   // hash valid only when previous 3 bytes is all valid, and they are all not the last byte of a block (not at the block border)
            c_hash    <= hash(b_byte[0], b_byte[1], b_byte[2]);                             // calculate hash value
            if (~c_en | c_eob) begin                                                        // maintain a byte counter in block
                c_ptr <= 14'h0;                                                             // not in a block, or meeting block end, clear the counter
            end else begin
                c_ptr <= c_ptr + 14'h1;                                                     // counter + 1
            end
        end
    end

generate if (SIMULATION) begin
always @ (posedge clk)
    if (a_pipe_en) begin
        if (~c_en | c_eob) begin
        end else begin
            if (c_ptr == 14'h3fff) begin  $display("*** error : block length overflow 16384, previous module must be wrong!");  $stop;  end
        end
    end
end endgenerate




// stage D : read/write hash table -------------------------------------------------------------------------------
reg         d_en      = 1'b0;
reg         d_eos     = 1'b0;
reg         d_eob     = 1'b0;
reg  [ 7:0] d_byte    = 8'h0;
reg         d_hash_en = 1'b0;
reg  [13:0] d_ptr     = 14'h0;
wire [13:0] d_past;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        d_en      <= 1'b0;
        d_eos     <= 1'b0;
        d_eob     <= 1'b0;
        d_byte    <= 8'h0;
        d_hash_en <= 1'b0;
        d_ptr     <= 14'h0;
    end else begin
        if (a_pipe_en) begin
            d_en      <= c_en;
            d_eos     <= c_eos;
            d_eob     <= c_eob;
            d_byte    <= c_byte;
            d_hash_en <= c_hash_en;
            d_ptr     <= c_ptr;
        end
    end

lz77_hash_table_ram #(
    .HASH_BITS          ( HASH_BITS                      )
) u_lz77_hash_table_ram (
    .clk                ( clk                            ),
    .addr               ( c_hash                         ),
    .wen                ( a_pipe_en & c_hash_en          ),
    .wdata              ( c_ptr                          ),
    .ren                ( a_pipe_en                      ),
    .rdata              ( d_past                         )
);



// stage E -------------------------------------------------------------------------------
reg         e_en      = 1'b0;
reg         e_eos     = 1'b0;
reg         e_eob     = 1'b0;
reg  [ 7:0] e_byte    = 8'h0;
reg         e_past_en = 1'b0;
reg  [13:0] e_ptr     = 14'h0;
reg  [13:0] e_past    = 14'h0;
reg  [11:0] e_past_aux= 12'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        e_en      <= 1'b0;
        e_eos     <= 1'b0;
        e_eob     <= 1'b0;
        e_byte    <= 8'h0;
        e_past_en <= 1'b0;
        e_ptr     <= 14'h0;
        e_past    <= 14'h0;
        e_past_aux<= 12'h0;
    end else begin
        if (a_pipe_en) begin
            e_en      <= d_en;
            e_eos     <= d_eos;
            e_eob     <= d_eob;
            e_byte    <= d_byte;
            e_past_en <= 1'b0;
            if (d_ptr > d_past)                // if current position is larger than the position from hash table
                e_past_en <= d_hash_en;        // LZ77 may be valid, otherwise LZ77 is disabled
            e_ptr     <= d_ptr;
            e_past    <= d_past;
            e_past_aux<= (d_past[13:2] + {11'h0, d_past[1]});   // same as : assign e_past_aux = e_past[13:2] + {11'h0, e_past[1]}
        end
    end



// stage F & G -------------------------------------------------------------------------------
reg         f_en      = 1'b0;
reg         f_eos     = 1'b0;
reg         f_eob     = 1'b0;
reg  [ 7:0] f_byte    = 8'h0;
reg         f_past_en = 1'b0;
reg  [13:0] f_ptr     = 14'h0;
reg  [13:0] f_past    = 14'h0;
reg  [11:0] f_past_aux= 12'h0;
wire [13:0] f_past_a1 = f_past + 14'h1;

reg         g_en      = 1'b0;
reg         g_eos     = 1'b0;
reg         g_eob     = 1'b0;
reg  [ 7:0] g_byte    = 8'h0;
reg         g_nlz_en  = 1'b0;
reg         g_lz_en   = 1'b0;
reg  [ 8:0] g_lz_len  = 9'h0;
reg         g_lz_len_reach_max = 1'b0;
reg  [13:0] g_lz_dist = 14'h0;

wire [ 7:0] f_past_byte0, f_past_byte1, f_past_byte2;

reg         f_match                 = 1'b0;                                                                                                         // 0:not matching   1:matching
reg         f_match_just_started    = 1'b0;
wire        f_match_start           = (~f_past_en) ? 1'b0 : ({f_past_byte0, f_past_byte1, f_past_byte2} == {f_byte, e_byte, d_byte}) ? 1'b1 : 1'b0;
//wire        f_match_final         = ((f_past_byte2 != e_byte) || (g_lz_len == MAX_LZ77_LEN) || e_eob) && (g_lz_len != 2);                         // if mismatch, or LZ77 length reach MAX_LZ77_LEN, or meeting a end of block, LZ77 must be end
wire        f_match_final           = ((f_past_byte2 != e_byte) || g_lz_len_reach_max || e_eob) && (~f_match_just_started);                         // after timing optimize
wire        f_match_next            = f_match ? (~f_match_final) : f_match_start;                                                                   //(f_match_start | (f_match & ~f_match_final));
wire        f_match_addr_sel_f_past = f_match ? (~f_match_final) : 1'b0;

lz77_past_byte_ram u_lz77_past_byte_ram (
    .clk                ( clk                            ),
    .wen                ( a_pipe_en & c_en               ),
    .waddr              ( c_ptr                          ),
    .wbyte              ( c_byte                         ),
    .ren                ( a_pipe_en                      ),
    .raddr              ( f_match_addr_sel_f_past ? f_past     : e_past     ),
    .raddr_aux          ( f_match_addr_sel_f_past ? f_past_aux : e_past_aux ),
    .rbyte              ( f_past_byte0                   ),
    .rbyte1             ( f_past_byte1                   ),
    .rbyte2             ( f_past_byte2                   )
);

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        f_en      <= 1'b0;
        f_eos     <= 1'b0;
        f_eob     <= 1'b0;
        f_byte    <= 8'h0;
        f_past_en <= 1'b0;
        f_ptr     <= 14'h0;
        f_past    <= 14'h0;
        f_past_aux<= 12'h0;
        f_match   <= 1'b0;
        f_match_just_started <= 1'b0;
    end else begin
        if (a_pipe_en) begin
            f_en      <= e_en;
            f_eos     <= e_eos;
            f_eob     <= e_eob;
            f_byte    <= e_byte;
            f_past_en <= e_past_en;
            f_ptr     <= e_ptr;
            f_past    <= f_match_next ? f_past_a1 : e_past;
            f_past_aux<= f_match_next ? (f_past_a1[13:2] + {11'h0, f_past_a1[1]}) : e_past_aux;    // same as : assign f_past_aux = f_past[13:2] + {11'h0, f_past[1]}
            f_match   <= f_match_next;
            f_match_just_started <= f_match_start & ~f_match;
        end
    end

generate if (SIMULATION) begin
always @ (posedge clk)
    if (a_pipe_en) begin
        if (f_match & ~e_en) begin $display("*** error: meeting e_en=0 when running, something must be wrong!");  $stop;  end
    end
end endgenerate


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        g_en      <= 1'b0;
        g_eos     <= 1'b0;
        g_eob     <= 1'b0;
        g_byte    <= 8'h0;
        g_nlz_en  <= 1'b0;
        g_lz_en   <= 1'b0;
        g_lz_len  <= 9'h0;
        g_lz_len_reach_max <= 1'b0;
        g_lz_dist <= 14'h0;
    end else begin
        if (a_pipe_en) begin
            g_en     <= f_en;
            g_eos    <= f_eos;
            g_eob    <= f_eob;
            g_byte   <= f_byte;
            g_nlz_en <= 1'b0;
            g_lz_en  <= 1'b0;
            g_lz_len_reach_max <= 1'b0;
            
            if (~f_match) begin
                g_nlz_en  <= f_en ? ~f_match_start : 1'b0;
                g_lz_dist <= f_ptr - f_past;
                g_lz_len  <= 9'd2;
            end else if (f_match_final) begin
                g_lz_en   <= 1'b1;
            end else begin
                g_lz_len  <= g_lz_len + 9'h1;
                g_lz_len_reach_max <= (g_lz_len == (MAX_LZ77_LEN-9'd1));
            end
        end
    end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (a_pipe_en) begin
        if (~f_match) begin
            if (f_en) if (f_match_start === 1'bz) begin $display("***error : f_match_start not sure when f_en=1"); $stop; end
        end else if (f_match_final) begin
        end else begin
            if ( (g_lz_len == 9'd2) !== f_match_just_started ) begin $display("***error : (g_lz_len == 9'd2) !== f_match_just_started"); $stop; end
            if ( (g_lz_len == 9'd2) && e_eob                 ) begin $display("***error : (g_lz_len == 9'd2) && e_eob"); $stop; end
        end
    end
end endgenerate



// stage H -------------------------------------------------------------------------------
reg         h_en     = 1'b0;
reg         h_eos    = 1'b0;
reg         h_eob    = 1'b0;
reg  [ 7:0] h_byte   = 8'h0;
reg         h_nlz_en = 1'b0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        h_en     <= 1'b0;
        h_eos    <= 1'b0;
        h_eob    <= 1'b0;
        h_byte   <= 8'h0;
        h_nlz_en <= 1'b0;
    end else begin
        if (a_pipe_en) begin
            h_en     <= g_en;
            h_eos    <= g_eos;
            h_eob    <= g_eob;
            h_byte   <= g_byte;
            h_nlz_en <= g_nlz_en;
        end
    end



// stage J -------------------------------------------------------------------------------
reg         j_en     = 1'b0;
reg         j_eos    = 1'b0;
reg         j_eob    = 1'b0;
reg  [ 7:0] j_byte   = 8'h0;
reg         j_nlz_en = 1'b0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        j_en     <= 1'b0;
        j_eos    <= 1'b0;
        j_eob    <= 1'b0;
        j_byte   <= 8'h0;
        j_nlz_en <= 1'b0;
    end else begin
        if (a_pipe_en) begin
            j_en     <= h_en;
            j_eos    <= h_eos;
            j_eob    <= h_eob;
            j_byte   <= h_byte;
            j_nlz_en <= h_nlz_en;
        end
    end



// stage K -------------------------------------------------------------------------------
reg         k_en      = 1'b0;
reg         k_eos     = 1'b0;
reg         k_eob     = 1'b0;
reg  [ 7:0] k_byte    = 8'h0;
reg         k_nlz_en  = 1'b0;
reg         k_lz_en   = 1'b0;
reg  [ 7:0] k_lz_len_minus3  = 8'h0;
reg  [13:0] k_lz_dist_minus1 = 14'h0;

reg         k_during_stream = 1'b0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        k_en      <= 1'b0;
        k_eos     <= 1'b0;
        k_eob     <= 1'b0;
        k_byte    <= 8'h0;
        k_nlz_en  <= 1'b0;
        k_lz_en   <= 1'b0;
        k_lz_len_minus3  <= 8'h0;
        k_lz_dist_minus1 <= 14'h0;
        k_during_stream <= 1'b0;
    end else begin
        k_en      <= 1'b0;
        k_eos     <= 1'b0;
        k_eob     <= 1'b0;
        k_byte    <= 8'h0;
        k_nlz_en  <= 1'b0;
        k_lz_en   <= 1'b0;
        k_lz_len_minus3  <= 8'h0;
        k_lz_dist_minus1 <= 14'h0;
        
        if (a_pipe_en) begin
            k_en   <= j_en;
            k_eos  <= j_eos;
            k_eob  <= j_eob;
            k_byte <= j_byte;
            
            if (~k_during_stream) begin
                if (j_en) begin
                    k_nlz_en <= 1'b1;
                    k_during_stream <= 1'b1;
                    
                    if (j_eos | h_eos | g_eos | f_eos | e_eos | d_eos | c_eos) begin   // if stream length = 1~7
                        k_nlz_en <= 1'b0;
                        k_during_stream <= 1'b0;
                    end
                    
                    for (i=0; i<=LATENCY; i=i+1)                                       // if stream length = 8 ~ 8+LATENCY
                        if ( b_eos[i] ) begin
                            k_nlz_en <= 1'b0;
                            k_during_stream <= 1'b0;
                        end
                end
            end else begin
                k_nlz_en  <= j_nlz_en;
                k_lz_en   <= g_lz_en;
                k_lz_len_minus3  <= g_lz_len[7:0] - 8'd3;
                k_lz_dist_minus1 <= g_lz_dist     - 14'd1;
                
                if (j_eos)
                    k_during_stream <= 1'b0;
            end
        end
    end


generate if (SIMULATION) begin
always @ (posedge clk)
    if (a_pipe_en) begin
        if (~k_during_stream) begin
        end else begin
            if (j_eos  & ~j_nlz_en) begin $display("*** error : j_eos=1 but j_nlz_en=0 at the last byte of stream, something must be wrong!"); $stop; end
            if (g_lz_en & j_nlz_en) begin $display("*** error : g_lz_en=1 and j_nlz_en=1 at same time, something must be wrong!"); $stop; end
            if (g_lz_en & j_eos   ) begin $display("*** error : g_lz_en=1 and j_eos=1    at same time, something must be wrong!"); $stop; end
            if (g_lz_en & j_eob   ) begin $display("*** error : g_lz_en=1 and j_eob=1    at same time, something must be wrong!"); $stop; end
            if (g_lz_en & g_lz_len < 9'd3        ) begin $display("*** error : g_lz_len < 3"); $stop; end
            if (g_lz_en & g_lz_len > MAX_LZ77_LEN) begin $display("*** error : g_lz_len > MAX_LZ77_LEN"); $stop; end
            if (g_lz_en & g_lz_dist < 14'd1      ) begin $display("*** error : g_lz_dist < 1"); $stop; end
        end
    end
end endgenerate





// stage output -------------------------------------------------------------------------------
assign o_en               = k_en;
assign o_eos              = k_eos;
assign o_eob              = k_eob;
assign o_byte             = k_byte;
assign o_nlz_en           = k_nlz_en;
assign o_lz77_en          = k_lz_en;
assign o_lz77_len_minus3  = k_lz_len_minus3;
assign o_lz77_dist_minus1 = k_lz_dist_minus1;


endmodule
