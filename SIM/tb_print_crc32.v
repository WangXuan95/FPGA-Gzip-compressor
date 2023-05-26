
module tb_print_crc32 (
    input  wire        clk,
    // input : AXI-stream
    input  wire        tready,
    input  wire        tvalid,
    input  wire [ 7:0] tdata,
    input  wire        tlast
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


reg [31:0] stream_index = 1;
reg [31:0] stream_len = 0;
reg [31:0] stream_crc = 'hFFFFFFFF;
always @ (posedge clk)
    if (tvalid & tready) begin
        stream_len = stream_len + 1;
        stream_crc = calculate_crc(stream_crc, tdata);
        if (tlast) begin
            if (stream_len < 32) begin
                $display("stream (ignored) length=%10d  CRC=%08x"              , stream_len, ~stream_crc);
            end else begin
                $display("stream %3d       length=%10d  CRC=%08x", stream_index, stream_len, ~stream_crc);
                stream_index = stream_index + 1;
            end
            stream_len = 0;
            stream_crc = 'hFFFFFFFF;
        end
    end


endmodule
