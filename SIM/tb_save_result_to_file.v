

`define   OUT_FILE_PATH      "./sim_data"
`define   OUT_FILE_FORMAT    "out%03d.hex.gz"


module tb_save_result_to_file (
    input  wire        clk,
    // input : AXI-stream
    input  wire        tready,
    input  wire        tvalid,
    input  wire [31:0] tdata,
    input  wire        tlast,
    input  wire [ 3:0] tkeep
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// save output stream to file
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
integer        fidx = 0;
integer        fptr = 0;
reg [1024*8:1] fname;           // 1024 bytes string buffer
reg [1024*8:1] f_path_format;   // 1024 bytes string buffer

initial $sformat(f_path_format, "%s\\%s", `OUT_FILE_PATH, `OUT_FILE_FORMAT);

always @ (posedge clk)
    if (tready & tvalid) begin
        if (fptr == 0) begin
            fidx = fidx + 1;
            $sformat(fname, f_path_format, fidx);
            fptr = $fopen(fname, "wb");
            if (fptr == 0) begin
                $display("***error : cannot open %s", fname);
                $stop;
            end
        end
        if (tkeep[0]) $fwrite(fptr, "%c", tdata[ 7: 0] );
        if (tkeep[1]) $fwrite(fptr, "%c", tdata[15: 8] );
        if (tkeep[2]) $fwrite(fptr, "%c", tdata[23:16]);
        if (tkeep[3]) $fwrite(fptr, "%c", tdata[31:24]);
        if (tlast) begin
            $fclose(fptr);
            fptr = 0;
        end
    end


endmodule
