
module tb_assert_axi_stream #(
    parameter   ASSERT_SENDER_NOT_CHANGE_WHEN_HANDSHAKE_FAILED   = 1,
    parameter   ASSERT_RECEIVER_NOT_CHANGE_WHEN_HANDSHAKE_FAILED = 0,
    parameter   DWIDTH                                           = 32
) (
    input  wire                  rstn,
    input  wire                  clk,
    input  wire                  tready,
    input  wire                  tvalid,
    input  wire [ DWIDTH   -1:0] tdata,
    input  wire                  tlast,
    input  wire [(DWIDTH/8)-1:0] tkeep
);



reg                   tready_d = 1'b0;
reg                   tvalid_d = 1'b0;
reg  [ DWIDTH   -1:0] tdata_d  = 0;
reg                   tlast_d  = 1'b0;
reg  [(DWIDTH/8)-1:0] tkeep_d  = 0;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        tready_d <= 1'b0;
        tvalid_d <= 1'b0;
        tdata_d  <= 0;
        tlast_d  <= 1'b0;
        tkeep_d  <= 0;
    end else begin
        tready_d <= tready;
        tvalid_d <= tvalid;
        tdata_d  <= tdata;
        tlast_d  <= tlast;
        tkeep_d  <= tkeep;
    end


generate if (ASSERT_SENDER_NOT_CHANGE_WHEN_HANDSHAKE_FAILED) begin
always @ (posedge clk or negedge rstn)
    if (~rstn) begin
    end else begin
        if ((~tready_d) & tvalid_d) begin         // At last cycle, sender sended a data, but receiver not avaiable, assert that sender is still sending a data at this cycle, and assert that data not change
            if (   1'b1 !== tvalid) begin $display("*** error : AXI-stream sender behavior abnormal : Illegal withdraw tvalid"); $stop; end
            if (tdata_d !== tdata ) begin $display("*** error : AXI-stream sender behavior abnormal : Illegal change in tdata"); $stop; end
            if (tlast_d !== tlast ) begin $display("*** error : AXI-stream sender behavior abnormal : Illegal change in tlast"); $stop; end
            if (tkeep_d !== tkeep ) begin $display("*** error : AXI-stream sender behavior abnormal : Illegal change in tkeep"); $stop; end
        end
    end
end endgenerate


generate if (ASSERT_RECEIVER_NOT_CHANGE_WHEN_HANDSHAKE_FAILED) begin
always @ (posedge clk or negedge rstn)
    if (~rstn) begin
    end else begin
        if (tready_d & (~tvalid_d)) begin         // At last cycle, receiver avaiable, but sender not sended a data, assert that receiver is still avaiable at this cycle
            if (1'b1 !== tready) begin $display("*** warning : AXI-stream receiver behavior abnormal : Illegal withdraw tvalid"); $stop; end
        end
    end
end endgenerate


endmodule
