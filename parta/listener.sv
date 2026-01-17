// Simple module to listen at the output port of the req_network and calculate the number of paths till the output
module listener #(
	parameter	NUM_PATHS_DW			=	16
)(
	input  wire							clk,
	input  wire							rst,

	input  wire							set_target_node,
	input  wire [11:0]					i_target_node,
	input  wire							i_start_counting,

	input  wire [63:0]					i_req_vld,
	input  wire [NUM_PATHS_DW-1:0]		i_req_paths[63:0],
	input  wire [12-1:0]				i_req_nodenum[63:0],

	output wire [NUM_PATHS_DW-1:0]		o_num_paths,
	output wire							o_num_paths_vld
);

integer i;
reg  [11:0]				r_target_node;

always @(posedge clk) begin
	if (set_target_node) begin
		r_target_node		<=		i_target_node;
	end
end

wire [7:0]					w_filtreq_vld;
wire [NUM_PATHS_DW-1:0]		w_filtreq_paths[7:0];
wire [12-1:0]				w_filtreq_nodenum[7:0];

reg  [7:0]					r_filtreq_vld;
reg  [NUM_PATHS_DW-1:0]		r_filtreq_paths[7:0];
reg  [12-1:0]				r_filtreq_nodenum[7:0];

genvar g;
generate
	for (g = 0; g < 8; g =g+1) begin
		reg  [7:0]					c_req_vld;
		reg  [NUM_PATHS_DW-1:0]		c_req_paths[7:0];
		reg  [12-1:0]				c_req_nodenum[7:0];

		always @(*) for (i = 0; i < 8; i =i+1) begin
			c_req_vld[i]		=	i_req_vld[8*g+i];
			c_req_paths[i]		=	i_req_paths[8*g+i];
			c_req_nodenum[i]	=	i_req_nodenum[8*g+i];
		end

		filter #(
				.PAYLOAD_WIDTH			(NUM_PATHS_DW)
		) filt_s1_inst(
				.i_req_vld				(c_req_vld		),
				.i_req_paths			(c_req_paths	),
				.i_req_nodenum			(c_req_nodenum	),

				.i_target_node			(r_target_node		),

				.o_filt_vld				(w_filtreq_vld[g]   ),
				.o_filt_paths			(w_filtreq_paths[g]	),
				.o_filt_nodenum			(w_filtreq_nodenum[g])
		);
	end
endgenerate

wire 						w_finalreq_vld;
wire [NUM_PATHS_DW-1:0]		w_finalreq_paths;
wire [12-1:0]				w_finalreq_nodenum;

reg  						r_finalreq_vld;
reg  [NUM_PATHS_DW-1:0]		r_finalreq_paths;
reg  [12-1:0]				r_finalreq_nodenum;
filter #(
		.PAYLOAD_WIDTH			(NUM_PATHS_DW)
) filt_s2_inst(
		.i_req_vld				(r_filtreq_vld		),
		.i_req_paths			(r_filtreq_paths	),
		.i_req_nodenum			(r_filtreq_nodenum	),

		.i_target_node			(r_target_node		),

		.o_filt_vld				(w_finalreq_vld		),
		.o_filt_paths			(w_finalreq_paths	),
		.o_filt_nodenum			(w_finalreq_nodenum	)
);

always @(posedge clk) begin
	for (i = 0; i < 8; i = i+1) begin
		r_filtreq_vld[i]			<=	w_filtreq_vld[i];
		r_filtreq_paths[i]			<=	w_filtreq_paths[i];
		r_filtreq_nodenum[i]		<=	w_filtreq_nodenum[i];
	end

	r_finalreq_vld					<=	w_finalreq_vld;
	r_finalreq_paths				<=	w_finalreq_paths;
	r_finalreq_nodenum				<=	w_finalreq_nodenum;
end

reg  [7:0]						r_in_count;
reg  [NUM_PATHS_DW-1:0]			r_num_paths;
reg								r_num_paths_vld;

always @(posedge clk) begin
	if (rst) begin
		r_in_count			<=	0;
		r_num_paths			<=	0;
		r_num_paths_vld		<=	0;
	end
	else begin
		if (~i_start_counting & r_finalreq_vld) begin
			r_in_count		<=	r_in_count + 1;
		end

		else if (i_start_counting & r_finalreq_vld) begin
			r_in_count		<=	r_in_count - 1;
			r_num_paths		<=	r_num_paths + r_finalreq_paths;

			if (r_in_count == 1) begin
				r_num_paths_vld	<=	1'b1;
			end
		end
	end
end

assign o_num_paths			=	r_num_paths;
assign o_num_paths_vld		=	r_num_paths_vld;

endmodule

