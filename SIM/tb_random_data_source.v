
`define FILE_COUNT 10


module tb_random_data_source (
    input  wire        clk,
    // output : AXI stream
    input  wire        tready,
    output reg         tvalid,
    output reg  [ 7:0] tdata,
    output reg         tlast
);



initial tvalid = 1'b0;
initial tdata  = 1'b0;
initial tlast  = 1'b0;



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// function : generate random unsigned integer
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
function  [31:0] randuint;
    input [31:0] min;
    input [31:0] max;
begin
    randuint = $random;
    if ( min != 0 || max != 'hFFFFFFFF )
        randuint = (randuint % (1+max-min)) + min;
end
endfunction



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// tasks : send random data
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
task gen_chunk_rand;
    input [31:0] max_bubble_cnt;
    input [31:0] length;
    input [ 7:0] min;
    input [ 7:0] max;
begin
    while (length>0) begin
        @ (posedge clk);
        if (tready) begin
            repeat (randuint(0, max_bubble_cnt)) begin
                tvalid <= 1'b0;
                @ (posedge clk);
            end
        end
        if (~tvalid | tready) begin
            length = length - 1;
            tvalid <= 1'b1;
            tlast  <= 1'b0;
            tdata <= randuint(min, max);
        end
    end
end
endtask


task gen_chunk_sqrt4_rand;
    input [31:0] max_bubble_cnt;
    input [31:0] length;
begin
    while (length>0) begin
        @ (posedge clk);
        if (tready) begin
            repeat (randuint(0, max_bubble_cnt)) begin
                tvalid <= 1'b0;
                @ (posedge clk);
            end
        end
        if (~tvalid | tready) begin
            length = length - 1;
            tvalid <= 1'b1;
            tlast  <= 1'b0;
            tdata  <= $sqrt($sqrt(randuint(0, 'hFFFFFFFF)));
        end
    end
end
endtask


task gen_chunk_inc;
    input [31:0] max_bubble_cnt;
    input [31:0] length;
    input [ 7:0] min;
    input [ 7:0] max;
begin
    while (length>0) begin
        @ (posedge clk);
        if (tready) begin
            repeat (randuint(0, max_bubble_cnt)) begin
                tvalid <= 1'b0;
                @ (posedge clk);
            end
        end
        if (~tvalid | tready) begin
            length = length - 1;
            tvalid <= 1'b1;
            tlast  <= 1'b0;
            if ( randuint(0,1) )
                tdata <= tdata + randuint(min, max);
            else
                tdata <= tdata - randuint(min, max);
        end
    end
end
endtask


task gen_chunk_scatter;
    input [31:0] max_bubble_cnt;
    input [31:0] length;
    input [31:0] prob;
begin
    while (length>0) begin
        @ (posedge clk);
        if (tready) begin
            repeat (randuint(0, max_bubble_cnt)) begin
                tvalid <= 1'b0;
                @ (posedge clk);
            end
        end
        if (~tvalid | tready) begin
            length = length - 1;
            tvalid <= 1'b1;
            tlast  <= 1'b0;
            if ( randuint(0, prob) == 0 )
                tdata <= randuint(1, 255);
            else
                tdata <= 8'h0;
        end
    end
end
endtask


task gen_stream;
    input [31:0] length;
    input [31:0] max_bubble_cnt;
    reg   [31:0] remain_length;
    reg   [31:0] chunk_length;
    reg   [ 7:0] min;
    reg   [ 7:0] max;
begin
    if (length > 0) begin
        remain_length = length - 1;
        
        while (remain_length > 0) begin
            chunk_length   = randuint(1, 10000);
            if (chunk_length > remain_length)
                chunk_length = remain_length;
            remain_length = remain_length - chunk_length;
            
            case ( randuint(0, 3) )
                0       : begin
                    min = randuint(0  , 255);
                    max = randuint(min, 255);
                    gen_chunk_rand      (max_bubble_cnt, chunk_length, min, max);
                end
                1       :
                    gen_chunk_sqrt4_rand(max_bubble_cnt, chunk_length);
                2       : begin
                    min = randuint(1  , 3);
                    max = randuint(min, 4);
                    gen_chunk_inc       (max_bubble_cnt, chunk_length, min, max);
                end
                default :
                    gen_chunk_scatter   (max_bubble_cnt, chunk_length, randuint(1, 600));
            endcase
        end
        
        remain_length = 1;
        while (remain_length>0) begin
            @ (posedge clk);
            if (~tvalid | tready) begin
                remain_length = 0;
                tvalid <= 1'b1;
                tlast  <= 1'b1;
                tdata  <= randuint(0,255);
            end
        end
    end
end
endtask



//---------------------------------------------------------------------------------------------------------------------------------------------------------------
// send random data
//---------------------------------------------------------------------------------------------------------------------------------------------------------------
initial begin
    repeat (1000) @ (posedge clk);
    
    repeat (`FILE_COUNT) begin
        case ( randuint(0,7) )
            0       : gen_stream(randuint(32, 1000000)    , randuint(0,3) );
            1       : gen_stream(32  +randuint(0,2)       , randuint(0,3) );
            2       : gen_stream(4095+randuint(0,2)       , randuint(0,3) );
            3       : gen_stream(randuint(1, 2)*16384 - 1 , randuint(0,3) );
            4       : gen_stream(randuint(1, 2)*16384     , randuint(0,3) );
            5       : gen_stream(randuint(1, 2)*16384 + 1 , randuint(0,3) );
            6       : gen_stream(randuint(9,20)*16384 + 1 , randuint(0,3) );
            7       : gen_stream(randuint(32, 32768)      , randuint(50,100) );
            8       : gen_stream(randuint(1,31)           , randuint(0,3) );     // the stream shorter than 32 will be ignore
        endcase
    end
    
    @ (posedge clk);
    while ( !(~tvalid | tready) ) begin
        @ (posedge clk);
    end
    tvalid <= 1'b0;
end


endmodule
