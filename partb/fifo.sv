// FIFO module taken from chipverify.com
module fifo #(
	parameter DEPTH				=	8,
	parameter WIDTH				=	16
) (
        input  wire            	rst,     
        input  wire         	clk,     
        input  wire         	wr_en, 	 
        input  wire         	rd_en, 	 
        input  wire [WIDTH-1:0] din, 	 
        output wire [WIDTH-1:0] dout, 	 
        output wire         	empty, 	 
    	output wire          	full 	 
);


reg  [$clog2(DEPTH)-1:0]	wptr;
wire [$clog2(DEPTH)-1:0]	wptr_n;
assign wptr_n			=	wptr + 1;

reg  [$clog2(DEPTH)-1:0]   rptr;

reg [WIDTH-1 : 0]    fifo[DEPTH-1:0];

always @ (posedge clk) begin
	if (rst) begin
		wptr <= 0;
	end 
	else if (wr_en & !full) begin
		fifo[wptr]	<= din;
		wptr		<= wptr_n;
	end
end

always @ (posedge clk) begin
	if (rst) begin
		rptr	<= 0;
	end 
	else if (rd_en & !empty) begin
		rptr	<= rptr + 1;
	end
end

assign dout  = fifo[rptr];
assign full  = (wptr_n == rptr);
assign empty = (wptr == rptr);

endmodule
