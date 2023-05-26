
//--------------------------------------------------------------------------------------------------------
// Module  : uart_tx
// Type    : synthesizable, IP's top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: input  AXI-stream (configurable data width),
//           output UART signal
//--------------------------------------------------------------------------------------------------------

module uart_tx #(
    // clock frequency
    parameter  CLK_FREQ                  = 50000000,     // clk frequency, Unit : Hz
    // UART format
    parameter  BAUD_RATE                 = 115200,       // Unit : Hz
    parameter  PARITY                    = "NONE",       // "NONE", "ODD", or "EVEN"
    parameter  STOP_BITS                 = 2,            // can be 1, 2, 3, 4, ...
    // AXI stream data width
    parameter  BYTE_WIDTH                = 1,            // can be 1, 2, 3, 4, ...
    // do you want to send extra byte after each AXI-stream transfer or packet?
    parameter  EXTRA_BYTE_AFTER_TRANSFER = "",           // specify a extra byte to send after each AXI-stream transfer. when ="", do not send this extra byte
    parameter  EXTRA_BYTE_AFTER_PACKET   = ""            // specify a extra byte to send after each AXI-stream packet  . when ="", do not send this extra byte
) (
    input  wire                    rstn,
    input  wire                    clk,
    // input  stream : AXI-stream slave. Associated clock = clk
    output wire                    i_tready,
    input  wire                    i_tvalid,
    input  wire [8*BYTE_WIDTH-1:0] i_tdata,
    input  wire [  BYTE_WIDTH-1:0] i_tkeep,
    input  wire                    i_tlast,
    // UART TX output signal
    output reg                     o_uart_tx
);




//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// Generate fractional precise upper limit for counter
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
localparam      BAUD_CYCLES              = ( (CLK_FREQ*10*2 + BAUD_RATE) / (BAUD_RATE*2) ) / 10 ;
localparam      BAUD_CYCLES_FRAC         = ( (CLK_FREQ*10*2 + BAUD_RATE) / (BAUD_RATE*2) ) % 10 ;

localparam real IDEAL_BAUD_CYCLES        = (1.0*CLK_FREQ) / (1.0*BAUD_RATE);
localparam real ACTUAL_BAUD_CYCLES       = (10.0*BAUD_CYCLES + BAUD_CYCLES_FRAC) / 10.0;
localparam real ACTUAL_BAUD_RATE         = (1.0*CLK_FREQ) / ACTUAL_BAUD_CYCLES;
localparam real BAUD_RATE_ERROR          = (ACTUAL_BAUD_RATE > 1.0*BAUD_RATE) ? (ACTUAL_BAUD_RATE - 1.0*BAUD_RATE) : (1.0*BAUD_RATE - ACTUAL_BAUD_RATE);
localparam real BAUD_RATE_RELATIVE_ERROR = BAUD_RATE_ERROR / BAUD_RATE;


localparam      STOP_BIT_CYCLES          = (BAUD_CYCLES_FRAC == 0) ? BAUD_CYCLES : (BAUD_CYCLES + 1);


wire [31:0] cycles [9:0];

generate if (BAUD_CYCLES_FRAC == 0) begin
    assign cycles[0] = BAUD_CYCLES    ;
    assign cycles[1] = BAUD_CYCLES    ;
    assign cycles[2] = BAUD_CYCLES    ;
    assign cycles[3] = BAUD_CYCLES    ;
    assign cycles[4] = BAUD_CYCLES    ;
    assign cycles[5] = BAUD_CYCLES    ;
    assign cycles[6] = BAUD_CYCLES    ;
    assign cycles[7] = BAUD_CYCLES    ;
    assign cycles[8] = BAUD_CYCLES    ;
    assign cycles[9] = BAUD_CYCLES    ;
end else if (BAUD_CYCLES_FRAC == 1) begin
    assign cycles[0] = BAUD_CYCLES    ;
    assign cycles[1] = BAUD_CYCLES    ;
    assign cycles[2] = BAUD_CYCLES    ;
    assign cycles[3] = BAUD_CYCLES    ;
    assign cycles[4] = BAUD_CYCLES + 1;
    assign cycles[5] = BAUD_CYCLES    ;
    assign cycles[6] = BAUD_CYCLES    ;
    assign cycles[7] = BAUD_CYCLES    ;
    assign cycles[8] = BAUD_CYCLES    ;
    assign cycles[9] = BAUD_CYCLES    ;
end else if (BAUD_CYCLES_FRAC == 2) begin
    assign cycles[0] = BAUD_CYCLES    ;
    assign cycles[1] = BAUD_CYCLES    ;
    assign cycles[2] = BAUD_CYCLES + 1;
    assign cycles[3] = BAUD_CYCLES    ;
    assign cycles[4] = BAUD_CYCLES    ;
    assign cycles[5] = BAUD_CYCLES    ;
    assign cycles[6] = BAUD_CYCLES    ;
    assign cycles[7] = BAUD_CYCLES + 1;
    assign cycles[8] = BAUD_CYCLES    ;
    assign cycles[9] = BAUD_CYCLES    ;
end else if (BAUD_CYCLES_FRAC == 3) begin
    assign cycles[0] = BAUD_CYCLES    ;
    assign cycles[1] = BAUD_CYCLES + 1;
    assign cycles[2] = BAUD_CYCLES    ;
    assign cycles[3] = BAUD_CYCLES    ;
    assign cycles[4] = BAUD_CYCLES + 1;
    assign cycles[5] = BAUD_CYCLES    ;
    assign cycles[6] = BAUD_CYCLES    ;
    assign cycles[7] = BAUD_CYCLES + 1;
    assign cycles[8] = BAUD_CYCLES    ;
    assign cycles[9] = BAUD_CYCLES    ;
end else if (BAUD_CYCLES_FRAC == 4) begin
    assign cycles[0] = BAUD_CYCLES    ;
    assign cycles[1] = BAUD_CYCLES + 1;
    assign cycles[2] = BAUD_CYCLES    ;
    assign cycles[3] = BAUD_CYCLES + 1;
    assign cycles[4] = BAUD_CYCLES    ;
    assign cycles[5] = BAUD_CYCLES    ;
    assign cycles[6] = BAUD_CYCLES + 1;
    assign cycles[7] = BAUD_CYCLES    ;
    assign cycles[8] = BAUD_CYCLES + 1;
    assign cycles[9] = BAUD_CYCLES    ;
end else if (BAUD_CYCLES_FRAC == 5) begin
    assign cycles[0] = BAUD_CYCLES + 1;
    assign cycles[1] = BAUD_CYCLES    ;
    assign cycles[2] = BAUD_CYCLES + 1;
    assign cycles[3] = BAUD_CYCLES    ;
    assign cycles[4] = BAUD_CYCLES + 1;
    assign cycles[5] = BAUD_CYCLES    ;
    assign cycles[6] = BAUD_CYCLES + 1;
    assign cycles[7] = BAUD_CYCLES    ;
    assign cycles[8] = BAUD_CYCLES + 1;
    assign cycles[9] = BAUD_CYCLES    ;
end else if (BAUD_CYCLES_FRAC == 6) begin
    assign cycles[0] = BAUD_CYCLES + 1;
    assign cycles[1] = BAUD_CYCLES    ;
    assign cycles[2] = BAUD_CYCLES + 1;
    assign cycles[3] = BAUD_CYCLES    ;
    assign cycles[4] = BAUD_CYCLES + 1;
    assign cycles[5] = BAUD_CYCLES + 1;
    assign cycles[6] = BAUD_CYCLES    ;
    assign cycles[7] = BAUD_CYCLES + 1;
    assign cycles[8] = BAUD_CYCLES    ;
    assign cycles[9] = BAUD_CYCLES + 1;
end else if (BAUD_CYCLES_FRAC == 7) begin
    assign cycles[0] = BAUD_CYCLES + 1;
    assign cycles[1] = BAUD_CYCLES    ;
    assign cycles[2] = BAUD_CYCLES + 1;
    assign cycles[3] = BAUD_CYCLES + 1;
    assign cycles[4] = BAUD_CYCLES    ;
    assign cycles[5] = BAUD_CYCLES + 1;
    assign cycles[6] = BAUD_CYCLES + 1;
    assign cycles[7] = BAUD_CYCLES    ;
    assign cycles[8] = BAUD_CYCLES + 1;
    assign cycles[9] = BAUD_CYCLES + 1;
end else if (BAUD_CYCLES_FRAC == 8) begin
    assign cycles[0] = BAUD_CYCLES + 1;
    assign cycles[1] = BAUD_CYCLES + 1;
    assign cycles[2] = BAUD_CYCLES    ;
    assign cycles[3] = BAUD_CYCLES + 1;
    assign cycles[4] = BAUD_CYCLES + 1;
    assign cycles[5] = BAUD_CYCLES + 1;
    assign cycles[6] = BAUD_CYCLES + 1;
    assign cycles[7] = BAUD_CYCLES    ;
    assign cycles[8] = BAUD_CYCLES + 1;
    assign cycles[9] = BAUD_CYCLES + 1;
end else /*if (BAUD_CYCLES_FRAC == 9)*/ begin
    assign cycles[0] = BAUD_CYCLES + 1;
    assign cycles[1] = BAUD_CYCLES + 1;
    assign cycles[2] = BAUD_CYCLES + 1;
    assign cycles[3] = BAUD_CYCLES + 1;
    assign cycles[4] = BAUD_CYCLES    ;
    assign cycles[5] = BAUD_CYCLES + 1;
    assign cycles[6] = BAUD_CYCLES + 1;
    assign cycles[7] = BAUD_CYCLES + 1;
    assign cycles[8] = BAUD_CYCLES + 1;
    assign cycles[9] = BAUD_CYCLES + 1;
end endgenerate



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// 
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
localparam [BYTE_WIDTH-1:0] ZERO_KEEP   = 0;

localparam           [31:0] PARITY_BITS = (PARITY == "ODD" || PARITY == "EVEN") ? 1 : 0;
localparam           [31:0] TOTAL_BITS  = (STOP_BITS >= ('hFFFFFFFF-9-PARITY_BITS)) ? 'hFFFFFFFF : (PARITY_BITS+STOP_BITS+9);

localparam           [ 0:0] BYTE_T_EN   = (EXTRA_BYTE_AFTER_TRANSFER == "") ? 1'b0 : 1'b1;
localparam           [ 0:0] BYTE_B_EN   = (EXTRA_BYTE_AFTER_PACKET   == "") ? 1'b0 : 1'b1;
localparam           [ 7:0] BYTE_T      =  EXTRA_BYTE_AFTER_TRANSFER;
localparam           [ 7:0] BYTE_P      =  EXTRA_BYTE_AFTER_PACKET;



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// function for calculate parity bit
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
function  [0:0] get_parity;
    input [7:0] data;
begin
    get_parity = (PARITY == "ODD" ) ? (~(^(data[7:0]))) : 
                 (PARITY == "EVEN") ?   (^(data[7:0]))  : 
               /*(PARITY == "NONE")*/      1'b1         ;
end
endfunction



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// main FSM
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
localparam [       1:0] S_IDLE     = 2'b01 ,       // only in state S_IDLE, state[0]==1, the goal is to make i_tready pure register-out
                        S_PREPARE  = 2'b00 ,
                        S_TX       = 2'b10 ;

reg  [             1:0] state      = S_IDLE;       // FSM state register

reg  [8*BYTE_WIDTH-1:0] data       = 0;
reg  [  BYTE_WIDTH-1:0] keep       = 0;
reg                     byte_t_en  = 1'b0;
reg                     byte_p_en  = 1'b0;
reg  [             9:0] txbits     = 10'b0;
reg  [            31:0] txcnt      = 0;
reg  [            31:0] cycle      = 1;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        state      <= S_IDLE;
        data       <= 0;
        keep       <= 0;
        byte_t_en  <= 1'b0;
        byte_p_en  <= 1'b0;
        txbits     <= 10'b0;
        txcnt      <= 0;
        cycle      <= 1;
    end else begin
        case (state)
            S_IDLE : begin
                state      <= i_tvalid ? S_PREPARE : S_IDLE;
                data       <= i_tdata;
                keep       <= i_tkeep;
                byte_t_en  <= BYTE_T_EN;
                byte_p_en  <= BYTE_B_EN & i_tlast;
                txbits     <= 10'b0;
                txcnt      <= 0;
                cycle      <= 1;
            end
            
            S_PREPARE : begin
                data <= (data >> 8);
                keep <= (keep >> 1);
                if          ( keep[0] == 1'b1   ) begin
                    txbits     <= {get_parity(data[7:0]), data[7:0], 1'b0};
                    state      <= S_TX;
                end else if ( keep != ZERO_KEEP ) begin
                    state      <= S_PREPARE;
                end else if ( byte_t_en         ) begin
                    byte_t_en <= 1'b0;
                    txbits     <= {get_parity(BYTE_T), BYTE_T, 1'b0};
                    state      <= S_TX;
                end else if ( byte_p_en         ) begin
                    byte_p_en <= 1'b0;
                    txbits     <= {get_parity(BYTE_P), BYTE_P, 1'b0};
                    state      <= S_TX;
                end else begin
                    state      <= S_IDLE;
                end
                txcnt <= 0;
                cycle <= 1;
            end
            
            default : begin  // S_TX
                if (keep[0] == 1'b0) begin
                    data <= (data >> 8);
                    keep <= (keep >> 1);
                end
                if ( cycle < ((txcnt<=9) ? cycles[txcnt] : STOP_BIT_CYCLES) ) begin      // cycle loop from 1 to ((txcnt<=9) ? cycles[txcnt] : STOP_BIT_CYCLES)
                    cycle  <= cycle + 1;
                end else begin
                    cycle  <= 1;
                    txbits <= {1'b1, txbits[9:1]};                                       // right shift txbits, and fill '1' to MSB
                    if ( txcnt < (TOTAL_BITS-1) ) begin                                  // txcnt loop from 0 to (TOTAL_BITS-1)
                        txcnt <= txcnt + 1;
                    end else begin
                        txcnt <= 0;
                        state <= S_PREPARE;
                    end
                end
            end
        endcase
    end



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// generate UART output
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
initial o_uart_tx = 1'b1;

always @ (posedge clk or negedge rstn)
    if (~rstn)
        o_uart_tx <= 1'b1;
    else
        o_uart_tx <= (state == S_TX) ? txbits[0] : 1'b1;



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// generate AXI-stream TREADY
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
assign i_tready = state[0];   // (state == S_IDLE)



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// parameter checking
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
initial begin
    if (BYTE_WIDTH <= 0) begin
        $error("*** error : uart_tx : invalid parameter : BYTE_WIDTH<=0");
        $stop;
    end
    
    if (STOP_BITS  <= 0) begin
        $error("*** error : uart_tx : invalid parameter : STOP_BITS <=0");
        $stop;
    end
    
    // print information
    $display ("uart_tx :                  clock frequency = %10d Hz" , CLK_FREQ                 );
    $display ("uart_tx :                desired baud rate = %10d Hz" , BAUD_RATE                );
    $display ("uart_tx :  ideal frequency division factor = %.6f"    , IDEAL_BAUD_CYCLES        );
    $display ("uart_tx : actual frequency division factor = %.6f"    , ACTUAL_BAUD_CYCLES       );
    $display ("uart_tx :                 actual baud rate = %.3f Hz" , ACTUAL_BAUD_RATE         );
    $display ("uart_tx :      relative error of baud rate = %.6f%%"  , BAUD_RATE_RELATIVE_ERROR*100 );
    
    if (BAUD_CYCLES < 1) begin
        $error("*** error : uart_tx : invalid parameter : BAUD_CYCLES < 1, please use a faster driving clock");
        $stop;
    end
    
    if ( BAUD_RATE_RELATIVE_ERROR > 0.005 ) begin
        $error("*** error : uart_tx : relative error of baud rate is too large, please use faster driving clock, or integer multiple of baud rate.");
        $stop;
    end
end


endmodule
