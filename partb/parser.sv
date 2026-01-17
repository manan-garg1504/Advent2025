// Simple parser to get node strings from input ASCII
module parser (
	input  wire			clk,
	input  wire			rst,

	input  wire			i_vld,
	input  wire [7:0]	i_char,
	output wire			o_stall,

	output reg 			o_node_vld,
	output reg [14:0]	o_node_str,
	output reg			o_newline,
	input  wire			i_stall
);

reg						n_node_vld;
reg 					n_newline;
reg  [14:0]				n_node_str;
assign o_stall			=	i_stall & o_node_vld;

reg  [1:0]				r_parsed_chars, n_parsed_chars;

localparam	ASCII_a		=	97;
localparam	ASCII_NL	=	10;

reg  [4:0]				temp_chr;
always @(*) begin
	n_newline			=	o_newline;
	n_node_str			=	o_node_str;
	n_node_vld			=	o_node_vld;
	n_parsed_chars		=	r_parsed_chars;

	if (i_vld & (~o_stall)) begin
		n_node_vld		=	1'b0;
		if ((i_char >= ASCII_a) & (i_char < ASCII_a + 26)) begin
			temp_chr			=	i_char - ASCII_a;
			n_node_str			=	{o_node_str, temp_chr};
			n_parsed_chars		=	r_parsed_chars + 1;

			if (r_parsed_chars == 2) begin
				n_node_vld		=	1'b1;
				n_parsed_chars	=	0;
				n_newline		=	1'b0;
			end
		end
		else if (i_char == ASCII_NL) begin
			n_newline		=	1'b1;
			n_node_vld		=	1'b1;
			n_node_str		=	0;
		end
	end
	
end

always @(posedge clk) begin
	if (rst) begin
		o_node_vld			<=	1'b0;
		r_parsed_chars		<=	0;
	end
	else if (~o_stall) begin
		o_node_vld			<=	n_node_vld;
		r_parsed_chars		<=	n_parsed_chars;
	end

	o_newline				<=	n_newline;
	o_node_str				<=	n_node_str;
end

endmodule
