
module lz77_past_byte_ram (
    input  wire        clk,
    input  wire        wen,
    input  wire [13:0] waddr,
    input  wire [ 7:0] wbyte,
    input  wire        ren,
    input  wire [13:0] raddr,
    input  wire [11:0] raddr_aux,       // raddr_aux = raddr[13:2] + {11'h0, raddr[1]}
    output wire [ 7:0] rbyte,
    output wire [ 7:0] rbyte1,
    output wire [ 7:0] rbyte2
);


reg  [ 7:0] buf0 [4095:0];
reg  [ 7:0] buf1 [4095:0];
reg  [ 7:0] buf2 [4095:0];
reg  [ 7:0] buf3 [4095:0];

always @ (posedge clk)
    if (wen) begin
        if (waddr[1:0] == 2'h0) buf0[waddr[13:2]] <= wbyte;
        if (waddr[1:0] == 2'h1) buf1[waddr[13:2]] <= wbyte;
        if (waddr[1:0] == 2'h2) buf2[waddr[13:2]] <= wbyte;
        if (waddr[1:0] == 2'h3) buf3[waddr[13:2]] <= wbyte;
    end

reg  [ 1:0] raddr_l_r;

wire [11:0] raddr_offset0 = raddr[13:2];
//wire [11:0] raddr_offset1 = raddr[13:2] + {11'h0, raddr[1]};        // this comb logic will get bad timing
wire [11:0] raddr_offset1 = raddr_aux;                                // so we use timing logic to generate raddr_offset1 (outside this module)

reg  [11:0] raddr_offset0_r;
reg  [11:0] raddr_offset1_r;

reg  [ 7:0] rdata0;
reg  [ 7:0] rdata1;
reg  [ 7:0] rdata2;
reg  [ 7:0] rdata3;

always @ (posedge clk)
    if (ren) begin
        raddr_l_r <= raddr[1:0];
        raddr_offset0_r <= raddr_offset0;
        raddr_offset1_r <= raddr_offset1;
    end

always @ (posedge clk) begin
    rdata0 <= buf0[ren ? raddr_offset1 : raddr_offset1_r];
    rdata1 <= buf1[ren ? raddr_offset1 : raddr_offset1_r];
    rdata2 <= buf2[ren ? raddr_offset0 : raddr_offset0_r];
    rdata3 <= buf3[ren ? raddr_offset0 : raddr_offset0_r];
end

assign {rbyte, rbyte1, rbyte2} = (raddr_l_r == 2'h0) ? {rdata0, rdata1, rdata2} : 
                                 (raddr_l_r == 2'h1) ? {rdata1, rdata2, rdata3} : 
                                 (raddr_l_r == 2'h2) ? {rdata2, rdata3, rdata0} : 
                                                       {rdata3, rdata0, rdata1} ;

endmodule
