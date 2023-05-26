
module lz77_hash_table_ram #(
    parameter          HASH_BITS = 12
) (
    input  wire                 clk,
    input  wire [HASH_BITS-1:0] addr,
    input  wire                 wen,
    input  wire [         13:0] wdata,
    input  wire                 ren,
    output wire [         13:0] rdata
);


reg  [13:0] rdata_ram;
reg  [13:0] rdata_reg = 14'h0;
reg         ren_r     = 1'b0;

reg  [13:0] ram [ ((1<<HASH_BITS)-1) : 0 ];

always @ (posedge clk)
    if (wen)                        // RAM w_enable
        ram[addr] <= wdata;         // RAM[w_addr] <= w_data

always @ (posedge clk)
    rdata_ram <= ram[addr];         // r_data <= RAM[r_addr]

always @ (posedge clk) begin
    if (ren_r)
        rdata_reg <= rdata_ram;
    ren_r <= ren;
end

assign rdata = ren_r ? rdata_ram : rdata_reg;

endmodule
