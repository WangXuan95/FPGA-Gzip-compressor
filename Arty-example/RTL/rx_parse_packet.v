
module rx_parse_packet (
    input  wire        rstn,
    input  wire        clk,
    input  wire        i_en,
    input  wire [ 7:0] i_data,
    output reg         o_en,
    output reg  [ 7:0] o_data,
    output reg         o_last,
    output wire        during_packet
);


initial o_en   = 1'b0;
initial o_data = 8'b0;
initial o_last = 1'b0;


localparam [3:0] HDR_0 = 0,
                 HDR_1 = 1,
                 HDR_2 = 2,
                 HDR_3 = 3,
                 HDR_4 = 4,
                 HDR_5 = 5,
                 HDR_6 = 6,
                 HDR_7 = 7,
                 LEN_0 = 8,
                 LEN_1 = 9,
                 LEN_2 = 10,
                 ZERO  = 11,
                 DATA  = 12;

reg [ 3:0] state = HDR_0;

assign during_packet = (state == DATA);

reg [23:0] pkt_len = 24'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        state   <= HDR_0;
        pkt_len <= 24'h0;
        o_en   <= 1'b0;
        o_data <= 8'b0;
        o_last <= 1'b0;
    end else begin
        o_en   <= 1'b0;
        o_data <= 8'b0;
        o_last <= 1'b0;
        if (i_en) begin
            case (state)
                HDR_0 :
                    state <= (i_data==8'hEB) ? HDR_1 : HDR_0;
                HDR_1 :
                    state <= (i_data==8'h9A) ? HDR_2 : HDR_0;
                HDR_2 :
                    state <= (i_data==8'hFC) ? HDR_3 : HDR_0;
                HDR_3 :
                    state <= (i_data==8'h1D) ? HDR_4 : HDR_0;
                HDR_4 :
                    state <= (i_data==8'h98) ? HDR_5 : HDR_0;
                HDR_5 :
                    state <= (i_data==8'h30) ? HDR_6 : HDR_0;
                HDR_6 :
                    state <= (i_data==8'hB7) ? HDR_7 : HDR_0;
                HDR_7 :
                    state <= (i_data==8'h06) ? LEN_0 : HDR_0;
                LEN_0 : begin
                    state <= LEN_1;
                    pkt_len[ 7: 0] <= i_data;
                end
                LEN_1 : begin
                    state <= LEN_2;
                    pkt_len[15: 8] <= i_data;
                end
                LEN_2 : begin
                    state <= ZERO ;
                    pkt_len[23:16] <= i_data;
                end
                ZERO  :
                    state <= (i_data==8'h00) ? DATA  : HDR_0;
                default : begin // DATA :
                    pkt_len <= pkt_len - 24'd1;
                    o_en   <= 1'b1;
                    o_data <= i_data;
                    if (pkt_len <= 24'd1) begin
                        o_last <= 1'b1;
                        state <= HDR_0;
                    end
                end
            endcase
        end
    end


endmodule
