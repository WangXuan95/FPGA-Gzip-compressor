
module monostable_reg # (
    parameter     TIME = 50000
) (
    input  wire   rstn,
    input  wire   clk,
    input  wire   i_signal,
    output reg    o_signal
);


initial    o_signal = 1'b0;

reg        i_signal_d = 1'b0;
reg [31:0] counter = 0;


always @ (posedge clk or negedge rstn)
    if (~rstn)
        i_signal_d <= 1'b0;
    else
        i_signal_d <= i_signal;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        counter <= 0;
        o_signal <= 1'b0;
    end else begin
        if (i_signal_d)
            counter <= TIME;
        else if (counter > 0)
            counter <= counter - 1;
        o_signal <= (counter > 0);
    end


endmodule
