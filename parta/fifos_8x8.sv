module fifos_8x8 #(
	parameter DATA_WIDTH		= 12,
	parameter FIFO_DEPTH		= 4
) (
    input  wire         							clk,
    input  wire         							rst,
	
	input  wire	[3-1:0]							i_target_fifo[7:0],
	input  wire [7:0]							i_req_vld,
	input  wire [DATA_WIDTH-1:0]				i_data[7:0],
	output reg 	[7:0]							o_accept,

	output wire [7:0]							o_data_vld,
	output wire [DATA_WIDTH-1:0]				o_data[7:0],
	input  wire [7:0]							i_rden
);

// In this design, we don't really care about fairness - at all times, any request going forward is the same for us
// regardless of which point has been stalled for whatever time
// In fact, since we'll probably be generating a stream of requests that should be satified to free up the nodeset, it's better
// to use a fixed priority encoder which will stay on a single requester

genvar g;
integer i;

reg  [7:0]						c_choice[7:0]; // The final chosen requests from all arbiters - will be orred to get the accept vector

generate
	for (g = 0; g < 8; g = g + 1) begin

		// First, collect the data on which input nodes want to write to this fifo
		reg  [7:0]						wr_en_in;
		reg								fifo_wr_en;
		reg  [DATA_WIDTH-1:0]			fifo_din;
		wire							fifo_full;
		wire							fifo_empty;

		always @(*) begin
			for (i = 0; i < 8; i=i+1) begin
				wr_en_in[i]			=	(~fifo_full) & i_req_vld[i] & (i_target_fifo[i] == g[2:0]);
			end

			// Choose one to actually accept
			fifo_wr_en			=	1'b0;
			c_choice[g]			=	0;
			fifo_din			=	0;

			for (i = 0; i < 8; i =i+1) begin
				if (wr_en_in[i] & ~fifo_wr_en) begin
					fifo_wr_en		=	1'b1;
					c_choice[g][i]	=	1'b1;
					fifo_din		=	i_data[i];
				end
			end
		end

		wire [DATA_WIDTH-1:0]			fifo_dout;
		fifo #(
			.DEPTH						(FIFO_DEPTH),
			.WIDTH						(DATA_WIDTH) // We have removed the first 3 bits from the target address by deciding which fifo to put this data in
		) fifo_inst(
			.clk						(clk  			),
			.rst						(rst  			),
			.wr_en						(fifo_wr_en		),
			.rd_en						(i_rden[g]		),
			.din						(fifo_din		),
			.dout						(fifo_dout		),
			.empty						(fifo_empty		),
			.full						(fifo_full		)
		);

		assign o_data[g]			=	fifo_dout;
		assign o_data_vld[g]		=	~fifo_empty;
	end
endgenerate

always @(*) begin
	o_accept			=	0;

	for(i=0; i < 8; i=i+1) begin
		o_accept		=	o_accept | c_choice[i];
	end
end
endmodule
