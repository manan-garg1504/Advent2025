// Module to take 8 reqs as input, and the target node num, 
// and forward reqs if the nodenum matches

module filter #(
	parameter	PAYLOAD_WIDTH			=	16
) (
	input  wire [7:0]					i_req_vld,
	input  wire [PAYLOAD_WIDTH-1:0]		i_req_paths[7:0],
	input  wire [12-1:0]				i_req_nodenum[7:0],

	input  wire [11:0]					i_target_node,

	output reg 							o_filt_vld,
	output reg  [PAYLOAD_WIDTH-1:0]		o_filt_paths,
	output reg  [12-1:0]				o_filt_nodenum
);
integer i;

always @(*) begin
	o_filt_vld		=	1'b0;
	o_filt_paths	=	i_req_paths[0];
	o_filt_nodenum	=	i_req_nodenum[0];

	for (i = 0; i < 8; i =i+1) begin
		if (i_req_nodenum[i] == i_target_node) begin
			o_filt_vld		=	i_req_vld[i];
			o_filt_paths	=	i_req_paths[i];
			o_filt_nodenum	=	i_req_nodenum[i];
		end
	end
end

endmodule
