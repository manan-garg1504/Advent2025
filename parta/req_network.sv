// A simple network of FIFOs to get data from one nodeset to the other, in the case where we know the target nodenum
module req_network #(
    parameter TOTAL_NODESETS	= 64,
	parameter NODENUM_WIDTH		= 12,

	parameter PAYLOAD_WIDTH		= 16,
	parameter NODETAG_WIDTH		= 6
) (
    input  wire         					clk,
    input  wire         					rst,
	
	input  wire [TOTAL_NODESETS-1:0]		i_req_vld,
	input  wire [PAYLOAD_WIDTH-1:0]			i_req_payload[TOTAL_NODESETS-1:0],
	input  wire [NODENUM_WIDTH-1:0]			i_req_nodenum[TOTAL_NODESETS-1:0],
	output reg 	[TOTAL_NODESETS-1:0]		o_req_ack,

	output wire [TOTAL_NODESETS-1:0]		o_req_vld,
	output reg  [PAYLOAD_WIDTH-1:0]			o_req_payload[TOTAL_NODESETS-1:0],
	output reg  [NODETAG_WIDTH-1:0]			o_req_nodenum[TOTAL_NODESETS-1:0],
	input  wire	[TOTAL_NODESETS-1:0]		i_req_ack
);

genvar g;
integer i;

// Instantiate the first layer of FIFOs
localparam	DW_FIRST_LAYER			= NODENUM_WIDTH-3 + PAYLOAD_WIDTH;
wire [TOTAL_NODESETS-1:0]			fl_vld_out;
reg  [DW_FIRST_LAYER-1:0]			fl_data_out[TOTAL_NODESETS-1:0];
reg  [TOTAL_NODESETS-1:0]			fl_ack_in;

generate
	for (g = 0; g < TOTAL_NODESETS/8; g=g+1) begin
		reg  [3-1:0]					fl_addr_in[7:0];
		reg  [DW_FIRST_LAYER-1:0]		fl_data_in[7:0];
		reg  [7:0]						fl_vld_in;
		wire [7:0]						fl_ack_out;

		integer j;
		always @(*) begin
			for(i = 0; i < 8; i=i+1) begin
				j								=	g + i*(TOTAL_NODESETS/8);
				{fl_addr_in[i], fl_data_in[i]}	=	{i_req_nodenum[j], i_req_payload[j]};
				fl_vld_in[i]					=	i_req_vld[j];
				o_req_ack[j]					=	fl_ack_out[i];
			end
		end

		wire [DW_FIRST_LAYER-1:0]		fifo_data_out[7:0];
		fifos_8x8 #(
			.DATA_WIDTH					(DW_FIRST_LAYER),
			.FIFO_DEPTH					(4)
		) first_layer_fifos(
			.clk						(clk          ),
			.rst						(rst          ),

			.i_target_fifo				(fl_addr_in		),
			.i_req_vld					(fl_vld_in		),
			.i_data						(fl_data_in		),
			.o_accept					(fl_ack_out		),

			.o_data_vld					(fl_vld_out[8*g+:8]),
			.o_data						(fifo_data_out	),
			.i_rden						(fl_ack_in[8*g+:8] )
		);

		always @(*) for(i = 0; i < 8; i =i+1) begin
			fl_data_out[8*g+i]		=	fifo_data_out[i];
		end
	end
endgenerate

// next layer: again the same number of fifos, but this time we sort according to the next three bits of address
// The inputs to the next 8x8 fifo module are the outputs of the previous stage, skipping a multiple of 8 each time to ensure that the first three bits of the target address are the same

localparam	DW_SEC_LAYER			=	NODENUM_WIDTH-6 + PAYLOAD_WIDTH;
wire [TOTAL_NODESETS-1:0]			sl_vld_out;
reg  [DW_SEC_LAYER-1:0]				sl_data_out[TOTAL_NODESETS-1:0];
reg  [TOTAL_NODESETS-1:0]			sl_ack_in;

generate
	for (g = 0; g < TOTAL_NODESETS/8; g=g+1) begin
		reg  [3-1:0]					sl_addr_in[7:0];
		reg  [DW_SEC_LAYER-1:0]			sl_data_in[7:0];
		reg  [7:0]						sl_vld_in;
		wire [7:0]						sl_ack_out;

		integer j;

		always @(*) begin
			for(i = 0; i < 8; i=i+1) begin
				j								=	g + i*(TOTAL_NODESETS/8);
				{sl_addr_in[i], sl_data_in[i]}	=	fl_data_out[j];
				sl_vld_in[i]					=	fl_vld_out[j];
				fl_ack_in[j]					=	sl_ack_out[i];
			end
		end
		
		wire [DW_SEC_LAYER-1:0]			fifo_data_out[7:0];
		fifos_8x8 #(
			.DATA_WIDTH					(DW_SEC_LAYER),
			.FIFO_DEPTH					(2)
		) second_layer_fifos(
			.clk						(clk          ),
			.rst						(rst          ),

			.i_target_fifo				(sl_addr_in		),
			.i_req_vld					(sl_vld_in		),
			.i_data						(sl_data_in		),
			.o_accept					(sl_ack_out		),

			.o_data_vld					(sl_vld_out[8*g+:8]),
			.o_data						(fifo_data_out	),
			.i_rden						(sl_ack_in[8*g+:8])
		);

		always @(*) for(i = 0; i < 8; i =i+1) begin
			sl_data_out[8*g+i]		=	fifo_data_out[i];
		end
	end
endgenerate

// If we had more NODESETS, we could set up arbiters below to send the output data to nodesets
// For example, with 128, We'd at this point have two FIFOs for each pair of output nodesets.
// If we got to 512, we could instantiate another 8x8 FIFO layer.
// This might not be the most elegant solution, and we need to edit this file depending on the nodesets we have,
// but it is scalable to whatever we need

assign	o_req_vld		=	sl_vld_out;
reg  [DW_SEC_LAYER-1:0]		t_data_out;

always @(*) begin
	sl_ack_in				=	i_req_ack;
	for (i = 0; i < TOTAL_NODESETS; i = i+1) begin
		t_data_out			=	sl_data_out[i];
		o_req_payload[i]	=	t_data_out[0+:PAYLOAD_WIDTH];
		o_req_nodenum[i]	=	t_data_out[PAYLOAD_WIDTH+:NODETAG_WIDTH];
	end
end

endmodule
