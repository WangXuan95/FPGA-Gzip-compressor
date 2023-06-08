
//--------------------------------------------------------------------------------------------------------
// Module  : uart_rx
// Type    : synthesizable, IP's example
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: example of gzip_compressor_top
//           receive data from UART and push to gzip_compressor_top
//           meanwhile, get data from gzip_compressor_top and send to UART
//--------------------------------------------------------------------------------------------------------

module uart_gzip_compressor #(
    parameter  CLK_FREQ                  = 100000000,     // clk frequency, Unit : Hz
    parameter  UART_BAUD_RATE            = 115200         // Unit : Hz
) (
    input  wire       rstn,
    input  wire       clk,                                // 100MHz
    input  wire       i_uart_rx,
    output wire       o_uart_tx,
    output wire [3:0] led
);


wire        rx_tvalid;
wire [ 7:0] rx_tdata;

wire        raw_tready;
wire        raw_tvalid;
wire [ 7:0] raw_tdata;
wire        raw_tlast;

wire        gz_tready;
wire        gz_tvalid;
wire [31:0] gz_tdata;
wire [ 3:0] gz_tkeep;
wire        gz_tlast;


uart_rx #(
    .CLK_FREQ         ( CLK_FREQ       ),
    .BAUD_RATE        ( UART_BAUD_RATE ),
    .PARITY           ( "NONE"         ),
    .FIFO_EA          ( 0              )
) u_uart_rx (
    .rstn             ( rstn           ),
    .clk              ( clk            ),
    .i_uart_rx        ( i_uart_rx      ),
    .o_tready         ( 1'b0           ),
    .o_tvalid         ( rx_tvalid      ),
    .o_tdata          ( rx_tdata       ),
    .o_overflow       (                )
);


rx_parse_packet u_rx_parse_packet (
    .rstn             ( rstn           ),
    .clk              ( clk            ),
    .i_en             ( rx_tvalid      ),
    .i_data           ( rx_tdata       ),
    .o_en             ( raw_tvalid     ),
    .o_data           ( raw_tdata      ),
    .o_last           ( raw_tlast      ),
    .during_packet    ( led[1]         )
);


gzip_compressor_top u_gzip_compressor (
    .rstn             ( rstn           ),
    .clk              ( clk            ),
    .i_tready         ( raw_tready     ),
    .i_tvalid         ( raw_tvalid     ),
    .i_tdata          ( raw_tdata      ),
    .i_tlast          ( raw_tlast      ),
    .o_tready         ( gz_tready      ),
    .o_tvalid         ( gz_tvalid      ),
    .o_tdata          ( gz_tdata       ),
    .o_tlast          ( gz_tlast       ),
    .o_tkeep          ( gz_tkeep       )
);


uart_tx #(
    .CLK_FREQ         ( CLK_FREQ       ),
    .BAUD_RATE        ( UART_BAUD_RATE ),
    .PARITY           ( "NONE"         ),
    .STOP_BITS        ( 3              ),
    .BYTE_WIDTH       ( 4              ),
    .FIFO_EA          ( 0              ),
    .EXTRA_BYTE_AFTER_TRANSFER ( ""    ),
    .EXTRA_BYTE_AFTER_PACKET   ( ""    )
) u_uart_tx (
    .rstn             ( rstn           ),
    .clk              ( clk            ),
    .i_tready         ( gz_tready      ),
    .i_tvalid         ( gz_tvalid      ),
    .i_tdata          ( gz_tdata       ),
    .i_tkeep          ( gz_tkeep       ),
    .i_tlast          ( gz_tlast       ),
    .o_uart_tx        ( o_uart_tx      )
);


assign led[0] = rstn;


monostable_reg # (
    .TIME             ( (CLK_FREQ/1000) * 50 )     // 50ms
) u_monostable_reg_1 (
    .rstn             ( rstn                 ),
    .clk              ( clk                  ),
    .i_signal         ( gz_tready == 1'b0    ),
    .o_signal         ( led[2]               )
);


monostable_reg # (
    .TIME             ( (CLK_FREQ/1000) * 50 )     // 50ms
) u_monostable_reg_2 (
    .rstn             ( rstn                 ),
    .clk              ( clk                  ),
    .i_signal         ( raw_tready == 1'b0   ),
    .o_signal         ( led[3]               )
);


endmodule
