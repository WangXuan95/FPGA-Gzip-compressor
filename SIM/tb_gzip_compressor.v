
module tb_gzip_compressor ();


//initial $dumpvars(1, tb_gzip_compressor);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// signals
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
reg         clk = 1'b0;
always #5   clk = ~clk;

wire        i_tready;
wire        i_tvalid;
wire [ 7:0] i_tdata;
wire        i_tlast;

reg         o_tready = 1'b0;
wire        o_tvalid;
wire [31:0] o_tdata;
wire        o_tlast;
wire [ 3:0] o_tkeep;


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// let simulation end when AXI stream have no any actions for a long time
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
reg  [31:0] count = 0;
always @ (posedge clk)
    if (i_tvalid === 1'b1 || o_tvalid === 1'b1) begin 
        count <= 0;
    end else if (count < 100000) begin
        count <= count + 1;
    end else begin
        $stop;
    end


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// generate random data packets to input to gzip_compressor_top
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
tb_random_data_source u_tb_random_data_source (
    .clk                ( clk                  ),
    .tready             ( i_tready             ),
    .tvalid             ( i_tvalid             ),
    .tdata              ( i_tdata              ),
    .tlast              ( i_tlast              )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// design under test
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
gzip_compressor_top # (
    .SIMULATION         ( 1                    )
) u_gzip_compressor (
    .rstn               ( 1'b1                 ),
    .clk                ( clk                  ),
    .i_tready           ( i_tready             ),
    .i_tvalid           ( i_tvalid             ),
    .i_tdata            ( i_tdata              ),
    .i_tlast            ( i_tlast              ),
    .o_tready           ( o_tready             ),
    .o_tvalid           ( o_tvalid             ),
    .o_tdata            ( o_tdata              ),
    .o_tlast            ( o_tlast              ),
    .o_tkeep            ( o_tkeep              )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// save output stream of gzip_compressor_top to files, getting .gz files
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
tb_save_result_to_file u_tb_save_result_to_file (
    .clk                ( clk                  ),
    .tready             ( o_tready             ),
    .tvalid             ( o_tvalid             ),
    .tdata              ( o_tdata              ),
    .tlast              ( o_tlast              ),
    .tkeep              ( o_tkeep              )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// calculate and print CRC32 of input data stream. You can compare this CRC with the CRC of the saved. gz file
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
tb_print_crc32 u_tb_print_crc32 (
    .clk                ( clk                  ),
    .tready             ( i_tready             ),
    .tvalid             ( i_tvalid             ),
    .tdata              ( i_tdata              ),
    .tlast              ( i_tlast              )
);


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// generate different tready behavior for output stream of gzip_compressor_top, to simulate receiver's handshake
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
initial begin
    while (1) begin
        repeat ( 1000000 ) begin
            @ (posedge clk);
            o_tready <= 1'b1;
        end
        repeat ( 500000 ) begin
            repeat (1) begin
                @ (posedge clk);
                o_tready <= 1'b0;
            end
            @ (posedge clk);
            o_tready <= 1'b1;
        end
        repeat ( 200000 ) begin
            repeat (2) begin
                @ (posedge clk);
                o_tready <= 1'b0;
            end
            @ (posedge clk);
            o_tready <= 1'b1;
        end
        repeat ( 50000 ) begin
            repeat (10) begin
                @ (posedge clk);
                o_tready <= 1'b0;
            end
            @ (posedge clk);
            o_tready <= 1'b1;
        end
        repeat ( 10000 ) begin
            repeat (50) begin
                @ (posedge clk);
                o_tready <= 1'b0;
            end
            @ (posedge clk);
            o_tready <= 1'b1;
        end
    end
end


//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// assert AXI stream behavior
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
tb_assert_axi_stream #(
    .ASSERT_SENDER_NOT_CHANGE_WHEN_HANDSHAKE_FAILED   ( 1 ),
    .ASSERT_RECEIVER_NOT_CHANGE_WHEN_HANDSHAKE_FAILED ( 1 ),
    .DWIDTH             ( 8                    )
) u_tb_assert_axi_stream_input (
    .rstn               ( 1'b1                 ),
    .clk                ( clk                  ),
    .tready             ( i_tready             ),
    .tvalid             ( i_tvalid             ),
    .tdata              ( i_tdata              ),
    .tlast              ( i_tlast              ),
    .tkeep              ( 1'b1                 )
);

tb_assert_axi_stream #(
    .ASSERT_SENDER_NOT_CHANGE_WHEN_HANDSHAKE_FAILED   ( 1 ),
    .ASSERT_RECEIVER_NOT_CHANGE_WHEN_HANDSHAKE_FAILED ( 0 ),
    .DWIDTH             ( 32                   )
) u_tb_assert_axi_stream_output (
    .rstn               ( 1'b1                 ),
    .clk                ( clk                  ),
    .tready             ( o_tready             ),
    .tvalid             ( o_tvalid             ),
    .tdata              ( o_tdata              ),
    .tlast              ( o_tlast              ),
    .tkeep              ( o_tkeep              )
);


endmodule
