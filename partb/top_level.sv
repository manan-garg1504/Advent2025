module top_level #(
	parameter	NUM_PATHS_DW	=	64
) (
	input  wire						clk,
	input  wire						rst,

	input  wire						i_vld,
	input  wire [7:0]				i_char,
	output wire						o_stall,

	output wire						o_error,
	output wire [NUM_PATHS_DW-1:0]	o_result,
	output wire						o_result_vld
);

wire [11:0]			w_node_tag;
wire				w_node_tag_vld;

wire				w_startnode;
wire				w_endnode;
wire				w_fftnode;
wire				w_dacnode;

wire				w_list_complete;
wire [63:0]			w_initlist_stall;


input_driver input_driver_inst(
	.clk					(clk             ),
	.rst					(rst             ),

	.i_vld					(i_vld           ),
	.i_char					(i_char          ),
	.o_stall				(o_stall         ),

	.o_error				(o_error         ),

	.o_hashnum				(w_node_tag      ),
	.o_hashnum_vld			(w_node_tag_vld  ),

	.o_startnode			(w_startnode     ),
	.o_endnode				(w_endnode       ),
	.o_fftnode				(w_fftnode		 ),
	.o_dacnode				(w_dacnode		 ),

	.o_list_complete		(w_list_complete ),
	.i_initlist_stall		(w_initlist_stall)
);


localparam					READING_INPUT		=	0;
localparam					INITIATE_COUNTING	=	1;
localparam					RESULT_WAIT			=	2;
reg [1:0]					r_overall_state;
reg							r_start_counting;
reg	[11:0]					r_startnode_tag;
reg	[11:0]					r_dacnode_tag;
reg	[11:0]					r_fftnode_tag;
reg							r_send_startnode, r_startnode_sent;
always @(posedge clk) begin
	if (rst) begin
		r_overall_state		<=	READING_INPUT;
		r_start_counting	<=	1'b0;
		r_send_startnode	<=	1'b0;
	end
	else begin
		case (r_overall_state)
			READING_INPUT: begin
				if (~i_vld & w_reqs_complete & w_list_complete) begin
					r_overall_state	<=	INITIATE_COUNTING;
					r_start_counting<=	1'b1;
				end

				if (w_startnode & w_node_tag_vld) begin
					r_startnode_tag		<=	w_node_tag;
				end

				if (w_dacnode & w_node_tag_vld) begin
					r_dacnode_tag		<=	w_node_tag;
				end

				if (w_fftnode & w_node_tag_vld) begin
					r_fftnode_tag		<=	w_node_tag;
				end
			end
			INITIATE_COUNTING : begin
				r_overall_state		<=	RESULT_WAIT;
				r_send_startnode	<=	1'b1;
			end
			RESULT_WAIT: begin
				r_send_startnode	<=	1'b0;
			end
		endcase
	end

end

wire [11:0]					w_node_input 		= r_send_startnode ? r_startnode_tag : w_node_tag;
wire						w_node_input_vld 	= w_node_tag_vld | r_send_startnode;

// Assign correct values into the nodenetwork based on the state above
nodenetwork #(
	.NUM_PATHS_DW			(NUM_PATHS_DW	 )
) nodenet_inst(
	.clk					(clk             ),
	.rst					(rst             ),

	.i_node_tag				(w_node_input	 ),
	.i_node_tag_vld			(w_node_input_vld),
	.i_list_complete		(w_list_complete ),

	.i_startnode			(w_startnode | r_send_startnode),
	.i_endnode				(w_endnode &  (r_overall_state == READING_INPUT)),
	.o_initlist_stall		(w_initlist_stall),

	.i_start_counting		(r_start_counting),
	.i_fft_tag				(r_fftnode_tag),
	.i_dac_tag				(r_dacnode_tag),
	.o_reqs_complete		(w_reqs_complete ),

	.o_num_paths			(o_result	     ),
	.o_num_paths_vld		(o_result_vld	 )
);

endmodule
