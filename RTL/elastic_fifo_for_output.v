
module elastic_fifo_for_output #(
    parameter SIMULATION = 0
) (
    input  wire        rstn,
    input  wire        clk,
    output reg         i_stall_n,
    input  wire [34:0] i_data,
    input  wire        i_en,
    output reg  [34:0] o_data,
    output reg         o_en,
    input  wire        o_rdy
);



initial i_stall_n = 1'b1;
initial o_en = 1'b0;


localparam [10:0] THRESHOLD_SET_STALL   = 11'd832,
                  THRESHOLD_CLEAR_STALL = 11'd768,
                  THRESHOLD_OVERFLOW    = 11'd1016;

reg  [10:0] wptr   = 11'd0;
reg  [10:0] wptr_d = 11'd0;
reg  [10:0] rptr   = 11'd0;
reg  [10:0] rptr1  = 11'd1;
wire [10:0] rptr_next = (o_en & o_rdy) ? rptr1 : rptr;
wire [10:0] buffer_usage = (wptr - rptr);

reg  [34:0] buffer [1023:0];


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        i_stall_n <= 1'b1;
    end else begin
        if (i_stall_n) begin
            if (buffer_usage >= THRESHOLD_SET_STALL && i_en)
                i_stall_n <= 1'b0;
        end else begin
            if (buffer_usage <  THRESHOLD_CLEAR_STALL)
                i_stall_n <= 1'b1;
        end
    end


generate if (SIMULATION) begin
reg  [10:0] buffer_usage_max = 11'd32;
always @ (posedge clk) begin
    if ( buffer_usage >= buffer_usage_max ) begin
        buffer_usage_max = buffer_usage + 11'd32;
        //$display("elastic_fifo_for_output : buffer_usage = %4d bytes", buffer_usage);
    end
    if (buffer_usage >= THRESHOLD_OVERFLOW && i_en) begin $display("*** error : elastic_fifo almost overflow!!"); $stop; end
end
end endgenerate


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        wptr   <= 11'h0;
        wptr_d <= 11'h0;
    end else begin
        if (i_en)
            wptr <= wptr + 11'h1;
        wptr_d <= wptr;
    end


always @ (posedge clk)
    if (i_en)
        buffer[wptr[9:0]] <= i_data;


always @ (posedge clk or negedge rstn)
    if (~rstn) begin
        rptr  <= 11'h0;
        rptr1 <= 11'h1;
        o_en  <= 1'b0;
    end else begin
        rptr  <= rptr_next;
        rptr1 <= rptr_next + 11'h1;
        o_en  <= (rptr_next != wptr_d);
    end


always @ (posedge clk)
    o_data <= buffer[rptr_next[9:0]];


endmodule
