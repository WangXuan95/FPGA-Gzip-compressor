
module split_stream_to_block (
    input  wire        rstn,
    input  wire        clk,
    // input stream
    input  wire        i_en,
    input  wire        i_eos,           // end of stream (current byte is the last byte of this stream), a stream that is larger than 16384 bytes is splitted to multiple blocks (done by previous modules).
    input  wire [ 7:0] i_byte,
    // output stream
    output reg         o_en,
    output reg         o_eos,           // end of stream (current byte is the last byte of this stream), a stream that is larger than 16384 bytes is splitted to multiple blocks (done by previous modules).
    output reg         o_eob,           // end of block  (current byte is the last byte of this block) , a block must not be larger than 16384 bytes.
    output reg  [ 7:0] o_byte
);


localparam [13:0] BLOCK_LEN_MINUS1 = 14'h3FFF;


initial  o_en   = 1'b0;
initial  o_eos  = 1'b0;
initial  o_eob  = 1'b0;
initial  o_byte = 8'h0;


reg  [13:0] counter = 14'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        counter <= 14'h0;
        o_en   <= 1'b0;
        o_eos  <= 1'b0;
        o_eob  <= 1'b0;
        o_byte <= 8'h0;
    end else begin
        o_en   <= 1'b0;
        o_eos  <= 1'b0;
        o_eob  <= 1'b0;
        o_byte <= 8'h0;
        if (i_en) begin
            o_en   <= 1'b1;
            o_eos  <= i_eos;
            o_byte <= i_byte;
            if (i_eos || (counter >= BLOCK_LEN_MINUS1)) begin
                o_eob <= 1'b1;
                counter <= 14'h0;
            end else
                counter <= counter + 14'h1;
        end
    end


endmodule
