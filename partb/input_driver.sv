module input_driver (
	input  wire			clk,
	input  wire			rst,

	input  wire			i_vld,
	input  wire [7:0]	i_char,
	output wire			o_stall,

	output wire			o_error,

	output wire [11:0]	o_hashnum,
	output wire			o_hashnum_vld,

	output wire			o_startnode,
	output wire			o_endnode,
	output wire			o_fftnode,
	output wire			o_dacnode,
	
	output wire			o_list_complete,
	input  wire [63:0]	i_initlist_stall
);

wire			w_node_vld;
wire [14:0]		w_node_str;
wire			w_newline;
wire			w_parser_stall;

parser input_parser_inst(
		.clk					(clk       ),
		.rst					(rst       ),

		.i_vld					(i_vld     ),
		.i_char					(i_char    ),
		.o_stall				(o_stall   ),

		.o_node_vld				(w_node_vld),
		.o_node_str				(w_node_str),
		.o_newline				(w_newline ),
		.i_stall				(w_parser_stall)
);

wire			initfifo_rden;
wire [15:0]		initfifo_rdata;
wire			initfifo_empty;
wire			initfifo_rdata_vld		=	~initfifo_empty;

fifo #(
	.DEPTH				(8),
	.WIDTH				(15 + 1)
) initlist_fifo(
	.rst				(rst					),
	.clk				(clk					),
	.wr_en				(w_node_vld				),
	.din				({w_newline, w_node_str}),
	.dout				(initfifo_rdata			),
	.rd_en				(initfifo_rden			),
	.empty				(initfifo_empty			),
	.full				(w_parser_stall			)
);

wire dbg;
assign dbg = initfifo_rden & (initfifo_rdata[14:0] == 15'h246c);


wire			w_hash_stall;
assign	initfifo_rden		=	~w_hash_stall & initfifo_rdata_vld;

wire			w_initproc_stalled;
// Next target: Re-write and fix the below
hash_table nodenum_calc_inst(
		.clk					(clk			),
		.rst					(rst			),

		.i_node_str				(initfifo_rdata[14:0]),
		.i_node_str_vld			(initfifo_rdata_vld & ~o_list_complete),
		.o_stall				(w_hash_stall	),

		.o_error				(o_error		), 

		.o_node_num				(o_hashnum		),
		.o_node_num_vld			(o_hashnum_vld	),
		.i_stall				(w_initproc_stalled)
);

assign	o_startnode			=	(initfifo_rdata[14:0] == {5'd18, 5'd21, 5'd17}) & initfifo_rdata_vld; // svr
assign	o_endnode			=	(initfifo_rdata[14:0] == {5'd14, 5'd20, 5'd19}) & initfifo_rdata_vld; // out
assign	o_fftnode			=	(initfifo_rdata[14:0] == { 5'd5,  5'd5, 5'd19}) & initfifo_rdata_vld; // fft
assign	o_dacnode			=	(initfifo_rdata[14:0] == { 5'd3,  5'd0,  5'd2}) & initfifo_rdata_vld; // dac

assign	o_list_complete		=	initfifo_rdata[15] & initfifo_rdata_vld;
assign	w_initproc_stalled	=	o_hashnum_vld & i_initlist_stall[o_hashnum[11:6]];

endmodule
