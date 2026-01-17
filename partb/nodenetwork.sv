module nodenetwork #(
	parameter	NUM_PATHS_DW			=	16
)(
	input  wire						clk,
	input  wire						rst,

	input  wire [11:0]				i_node_tag,
	input  wire						i_node_tag_vld,
	input  wire						i_list_complete,

	input  wire						i_startnode,
	input  wire						i_endnode,
	output wire [63:0]				o_initlist_stall,

	input  wire						i_start_counting,
	input  wire [11:0]				i_fft_tag,
	input  wire [11:0]				i_dac_tag,
	output reg						o_reqs_complete,

	output wire [NUM_PATHS_DW-1:0]	o_num_paths,
	output wire						o_num_paths_vld
);

genvar g;
integer i;
// Parametrize the widths of the below
wire [63:0]					w_reqs_complete;
always @(posedge clk) begin
	o_reqs_complete	<=	&w_reqs_complete;
end

wire [63:0]						req_gen_vld;
wire [NUM_PATHS_DW+1:0]			req_gen_paths[63:0];
wire [12-1:0]					req_gen_nodenum[63:0];
wire [63:0]						req_gen_ack;

wire [63:0]						req_rcv_vld;
wire [NUM_PATHS_DW+1:0]			req_rcv_paths[63:0];
wire [6-1:0]					req_rcv_nodenum[63:0];
wire [63:0]						req_rcv_ack;
generate
	for(g = 0; g < 64; g=g+1) begin
		nodeset #(
			.NODESET_NUM				(g			 ),
			.NUM_PATHS_DW				(NUM_PATHS_DW)
		) nodeset_inst(
			.clk						(clk            ),
			.rst						(rst            ),

			.i_node_tag					(i_node_tag		),
			.i_list_complete			(i_list_complete), // IMP: FLOP this till the last value is out from the hash table
			.i_node_tag_vld				(i_node_tag_vld ),

			.o_init_stall				(o_initlist_stall[g]),

			.i_req_vld					(req_rcv_vld[g] ),
			.i_req_payload				(req_rcv_paths[g]),
			.i_req_nodenum				(req_rcv_nodenum[g]),
			.o_req_ack					(req_rcv_ack[g] ),

			.o_req_vld					(req_gen_vld[g] ),
			.o_req_payload				(req_gen_paths[g]),
			.o_req_nodenum				(req_gen_nodenum[g]),
			.i_req_ack					(req_gen_ack[g] ),

			.i_startnode				(i_startnode	),
			.i_fft_tag					(i_fft_tag		),
			.i_dac_tag					(i_dac_tag		),
			.i_start_counting			(i_start_counting),
			.o_reqs_complete			(w_reqs_complete[g])
		);
	end
endgenerate

req_network #(
	.PAYLOAD_WIDTH						(NUM_PATHS_DW+2)
) switch_network_inst (
		.clk							(clk          ),
		.rst							(rst          ),

		.i_req_vld						(req_gen_vld   ),
		.i_req_payload					(req_gen_paths ),
		.i_req_nodenum					(req_gen_nodenum),
		.o_req_ack						(req_gen_ack   ),

		.o_req_vld						(req_rcv_vld  ),
		.o_req_payload					(req_rcv_paths),
		.o_req_nodenum					(req_rcv_nodenum),
		.i_req_ack						(req_rcv_ack  )
);


reg  [11:0]						c_listener_nodenums[63:0];
always @(*) begin
	for (i = 0; i < 64; i=i+1) begin
		c_listener_nodenums[i]	=	{i[5:0], req_rcv_nodenum[i]};
	end
end

// We assign the output reqs to this module, so that we don't get conflicting requests
listener #(
		.PAYLOAD_WIDTH			(NUM_PATHS_DW+2),
		.NUM_PATHS_DW			(NUM_PATHS_DW)
) get_answer_inst(
		.clk					(clk            ),
		.rst					(rst            ),

		.i_start_counting		(i_start_counting),
		.set_target_node		(i_endnode & i_node_tag_vld),
		.i_target_node			(i_node_tag		),

		.i_req_vld				(req_rcv_vld & req_rcv_ack),
		.i_req_payload			(req_rcv_paths),
		.i_req_nodenum			(c_listener_nodenums),

		.o_num_paths			(o_num_paths    ),
		.o_num_paths_vld		(o_num_paths_vld)
);
endmodule
