
module calc_length_and_crc32 (
    input  wire        rstn,
    input  wire        clk,
    // input stream
    input  wire        i_en,
    input  wire        i_eos,
    input  wire        i_eob,
    input  wire [ 7:0] i_byte,
    // output information
    output reg         o_eos,
    output reg         o_eob,
    output reg  [31:0] o_stream_len,
    output reg  [31:0] o_stream_crc
);



function  [31:0] calculate_crc;
    input [31:0] crc;
    input [ 7:0] inbyte;
    reg   [31:0] TABLE_CRC [15:0];
begin
    TABLE_CRC[0] = 'h00000000;    TABLE_CRC[1] = 'h1db71064;    TABLE_CRC[2] = 'h3b6e20c8;    TABLE_CRC[3] = 'h26d930ac;
    TABLE_CRC[4] = 'h76dc4190;    TABLE_CRC[5] = 'h6b6b51f4;    TABLE_CRC[6] = 'h4db26158;    TABLE_CRC[7] = 'h5005713c;
    TABLE_CRC[8] = 'hedb88320;    TABLE_CRC[9] = 'hf00f9344;    TABLE_CRC[10]= 'hd6d6a3e8;    TABLE_CRC[11]= 'hcb61b38c;
    TABLE_CRC[12]= 'h9b64c2b0;    TABLE_CRC[13]= 'h86d3d2d4;    TABLE_CRC[14]= 'ha00ae278;    TABLE_CRC[15]= 'hbdbdf21c;
    calculate_crc = crc ^ {24'h0, inbyte};
    calculate_crc = TABLE_CRC[calculate_crc[3:0]] ^ (calculate_crc >> 4);
    calculate_crc = TABLE_CRC[calculate_crc[3:0]] ^ (calculate_crc >> 4);
end
endfunction


initial o_eos = 1'b0;
initial o_eob = 1'b0;
initial o_stream_len = 0;
initial o_stream_crc = 0;


reg  [31:0] stream_len = 0;
reg  [31:0] stream_crc = 'hFFFFFFFF;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        stream_len   <= 0;
        stream_crc   <= 'hFFFFFFFF;
        o_stream_len <= 0;
        o_stream_crc <= 0;
    end else begin
        if (i_en) begin
            if (i_eos) begin
                stream_len   <= 0;
                stream_crc   <= 'hFFFFFFFF;
                o_stream_len <= stream_len + 1;
                o_stream_crc <= ~calculate_crc(stream_crc, i_byte);     // Note : Ultimately, the CRC needs to be reversed
            end else begin
                stream_len   <= stream_len + 1;
                stream_crc   <=  calculate_crc(stream_crc, i_byte);
            end
        end
    end


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        o_eos <= 1'b0;
        o_eob <= 1'b0;
    end else begin
        o_eos <= i_en ? i_eos : 1'b0;
        o_eob <= i_en ? i_eob : 1'b0;
    end


endmodule
