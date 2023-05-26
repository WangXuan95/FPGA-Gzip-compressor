
module fpga_top (
    input  wire       rstn_btn,
    input  wire       clk100m,
    input  wire       i_uart_rx,
    output wire       o_uart_tx,
    output wire [3:0] led
);


reg rstn_d1 = 1'b0;
reg rstn_d2 = 1'b0;


always @ (posedge clk100m) begin
    rstn_d1 <= rstn_btn;             // sync reset
    rstn_d2 <= rstn_d1;
end


uart_gzip_compressor u_uart_gzip_compressor (
    .rstn            ( rstn_d2      ),
    .clk             ( clk100m      ),
    .i_uart_rx       ( i_uart_rx    ),
    .o_uart_tx       ( o_uart_tx    ),
    .led             ( led          )
);


endmodule
