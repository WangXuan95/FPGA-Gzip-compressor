
//--------------------------------------------------------------------------------------------------------
// Module  : uart_rx
// Type    : synthesizable, IP's top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: input  UART signal,
//           output AXI-stream (1 byte data width)
//--------------------------------------------------------------------------------------------------------

module uart_rx #(
    // clock frequency
    parameter  CLK_FREQ                  = 50000000,     // clk frequency, Unit : Hz
    // UART format
    parameter  BAUD_RATE                 = 115200,       // Unit : Hz
    parameter  PARITY                    = "NONE"        // "NONE", "ODD", or "EVEN"
) (
    input  wire        rstn,
    input  wire        clk,
    // UART RX input signal
    input  wire        i_uart_rx,
    // output AXI-stream master. Associated clock = clk. 
    // input  wire     o_tready        // Note that TREADY signal is omitted, which means it will not handle situations that the receiver cannot accept data (This is a situation allowed by the AXI-stream specification)
    output reg         o_tvalid,
    output reg  [ 7:0] o_tdata
);



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// Generate fractional precise upper limit for counter
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
localparam  BAUD_CYCLES      = ( (CLK_FREQ*10*2 + BAUD_RATE) / (BAUD_RATE*2) ) / 10 ;
localparam  BAUD_CYCLES_FRAC = ( (CLK_FREQ*10*2 + BAUD_RATE) / (BAUD_RATE*2) ) % 10 ;

localparam real IDEAL_BAUD_CYCLES        = (1.0*CLK_FREQ) / (1.0*BAUD_RATE);
localparam real ACTUAL_BAUD_CYCLES       = (10.0*BAUD_CYCLES + BAUD_CYCLES_FRAC) / 10.0;
localparam real ACTUAL_BAUD_RATE         = (1.0*CLK_FREQ) / ACTUAL_BAUD_CYCLES;
localparam real BAUD_RATE_ERROR          = (ACTUAL_BAUD_RATE > 1.0*BAUD_RATE) ? (ACTUAL_BAUD_RATE - 1.0*BAUD_RATE) : (1.0*BAUD_RATE - ACTUAL_BAUD_RATE);
localparam real BAUD_RATE_RELATIVE_ERROR = BAUD_RATE_ERROR / BAUD_RATE;


localparam           HALF_BAUD_CYCLES =  BAUD_CYCLES    / 2;
localparam  THREE_QUARTER_BAUD_CYCLES = (BAUD_CYCLES*3) / 4;

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
// Input beat
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
reg        rx_d1 = 1'b0;

always @ (posedge clk or negedge rstn)
    if (~rstn)
        rx_d1 <= 1'b0;
    else
        rx_d1 <= i_uart_rx;



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// count continuous '1'
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
reg [31:0] count1 = 0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        count1 <= 0;
    end else begin
        if (rx_d1)
            count1 <= (count1 < 'hFFFFFFFF) ? (count1 + 1) : count1;
        else
            count1 <= 0;
    end



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// main FSM
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
localparam [ 3:0] TOTAL_BITS_MINUS1 = (PARITY == "ODD" || PARITY == "EVEN") ? 4'd9 : 4'd8;

localparam [ 1:0] S_IDLE     = 2'd0 ,
                  S_RX       = 2'd1 ,
                  S_STOP_BIT = 2'd2 ;

reg        [ 1:0] state   = S_IDLE;
reg        [ 8:0] rxbits  = 9'b0;
reg        [ 3:0] rxcnt   = 4'd0;
reg        [31:0] cycle   = 1;
reg        [32:0] countp  = 33'h1_0000_0000;       // countp>=0x100000000 means '1' is majority       , countp<0x100000000 means '0' is majority
wire              rxbit   = countp[32];            // countp>=0x100000000 corresponds to countp[32]==1, countp<0x100000000 corresponds to countp[32]==0

wire [ 7:0] rbyte   = (PARITY == "ODD" ) ? rxbits[7:0] : 
                      (PARITY == "EVEN") ? rxbits[7:0] : 
                    /*(PARITY == "NONE")*/ rxbits[8:1] ;

wire parity_correct = (PARITY == "ODD" ) ? ((~(^(rbyte))) == rxbits[8]) : 
                      (PARITY == "EVEN") ? (  (^(rbyte))  == rxbits[8]) : 
                    /*(PARITY == "NONE")*/      1'b1                    ;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        state    <= S_IDLE;
        rxbits   <= 9'b0;
        rxcnt    <= 4'd0;
        cycle    <= 1;
        countp   <= 33'h1_0000_0000;
    end else begin
        case (state)
            S_IDLE : begin
                if ((count1 >= THREE_QUARTER_BAUD_CYCLES) && (rx_d1 == 1'b0))  // receive a '0' which is followed by continuous '1' for half baud cycles
                    state <= S_RX;
                rxcnt  <= 4'd0;
                cycle  <= 2;                                                   // we've already receive a '0', so here cycle  = 2
                countp <= (33'h1_0000_0000 - 33'd1);                           // we've already receive a '0', so here countp = initial_value - 1
            end
            
            S_RX :
                if ( cycle < cycles[rxcnt] ) begin                             // cycle loop from 1 to cycles[rxcnt]
                    cycle  <= cycle + 1;
                    countp <= rx_d1 ? (countp + 33'd1) : (countp - 33'd1);
                end else begin
                    cycle  <= 1;                                               // reset counter
                    countp <= 33'h1_0000_0000;                                 // reset counter
                    
                    if ( rxcnt < TOTAL_BITS_MINUS1 ) begin                     // rxcnt loop from 0 to TOTAL_BITS_MINUS1
                        rxcnt <= rxcnt + 4'd1;
                        if ((rxcnt == 4'd0) && (rxbit == 1'b1))                // except start bit, but get '1'
                            state <= S_IDLE;                                   // RX failed, back to IDLE
                    end else begin
                        rxcnt <= 4'd0;
                        state <= S_STOP_BIT;
                    end
                    
                    rxbits <= {rxbit, rxbits[8:1]};                            // put current rxbit to MSB of rxbits, and right shift other bits
                end
            
            default :  // S_STOP_BIT
                if ( cycle < THREE_QUARTER_BAUD_CYCLES) begin                  // cycle loop from 1 to THREE_QUARTER_BAUD_CYCLES
                    cycle <= cycle + 1;
                end else begin
                    cycle <= 1;                                                // reset counter
                    state <= S_IDLE;                                           // back to IDLE
                end
        endcase
    end



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// generate output AXI-stream
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
initial o_tvalid = 1'b0;
initial o_tdata  = 8'h0;

always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        o_tvalid <= 1'b0;
        o_tdata  <= 8'h0;
    end else begin
        o_tvalid <= 1'b0;
        o_tdata  <= 8'h0;
        if (state == S_STOP_BIT) begin
            if ( cycle < THREE_QUARTER_BAUD_CYCLES) begin
            end else begin
                if ((count1 >= HALF_BAUD_CYCLES) && parity_correct) begin  // stop bit have enough '1', and parity correct
                    o_tvalid <= 1'b1;
                    o_tdata  <= rbyte;                                     // received a correct byte, output it
                end
            end
        end
    end



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// parameter checking
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
initial begin
    // print information
    $display ("uart_rx :                  clock frequency = %10d Hz" , CLK_FREQ                 );
    $display ("uart_rx :                desired baud rate = %10d Hz" , BAUD_RATE                );
    $display ("uart_rx :  ideal frequency division factor = %.6f"    , IDEAL_BAUD_CYCLES        );
    $display ("uart_rx : actual frequency division factor = %.6f"    , ACTUAL_BAUD_CYCLES       );
    $display ("uart_rx :                 actual baud rate = %.3f Hz" , ACTUAL_BAUD_RATE         );
    $display ("uart_rx :      relative error of baud rate = %.6f%%"  , BAUD_RATE_RELATIVE_ERROR*100 );
    
    if (BAUD_CYCLES < 32) begin
        $error("*** error : uart_rx : invalid parameter : BAUD_CYCLES < 32, please use a faster driving clock");
        $stop;
    end
    
    if ( BAUD_RATE_RELATIVE_ERROR > 0.003 ) begin
        $error("*** error : uart_tx : relative error of baud rate is too large, please use faster driving clock, or integer multiple of baud rate.");
        $stop;
    end
end


endmodule
