module nodeset #(
    parameter NODESET_NUM		=	0,
	parameter NUM_PATHS_DW		=	16
) (
    input  wire							clk,
    input  wire							rst,

    input  wire [11:0]					i_node_tag,
    input  wire							i_node_tag_vld,
    input  wire							i_list_complete,

    output reg							o_init_stall, // Represents if the current input needs to be "held"

	input  wire							i_req_vld,
	input  wire [NUM_PATHS_DW+1:0]		i_req_payload,
	input  wire [5:0]					i_req_nodenum,
	output reg							o_req_ack,

	output reg							o_req_vld,
	output reg  [NUM_PATHS_DW+1:0]		o_req_payload,
	output reg  [11:0]					o_req_nodenum,
	input  wire							i_req_ack,

	input  wire							i_start_counting,
	input  wire							i_startnode,
	input  wire [11:0]					i_fft_tag,
	input  wire [11:0]					i_dac_tag,
	output reg							o_reqs_complete
);

// First, we just write the code to fill out the response children memory

integer i;
localparam	INIT_IDLE			=   0;
localparam	INIT_WRITING		=   1;
localparam	INIT_WRITE_COMPLETE	=   2;
localparam	INIT_ALTLIST_WAIT	=	3;

reg  [35:0]                 graph_ram[511:0];
reg                         graph_wen;
reg  [8:0]                  graph_waddr;
reg  [35:0]                 graph_wdata;
reg  [35:0]                 graph_rdata;
wire                        graph_rden;
wire [8:0]                  graph_raddr;

reg  [23:0]                 r_child_tags, n_child_tags;
reg  [1:0]                  r_numchild_mod3, n_numchild_mod3;
reg  [7:0]                  r_numchildren, n_numchildren;
reg  [8:0]                  r_free_addr, n_free_addr;
// Output data still needs to be assigned, and graph_waddr will also need some logic changes
reg  [5:0]                  r_par_tag, n_par_tag;
reg  [1:0]                  r_init_state, n_init_state;
reg  [63:0]					r_graph_complete, n_graph_complete;
reg  [8:0]                  c_init_raddr;
reg                         c_init_rden;


always @(*) begin
    n_init_state				=   r_init_state;
    graph_waddr					=   r_free_addr;
	n_graph_complete			=	r_graph_complete;
    graph_wen					=   1'b0;
    c_init_rden					=   1'b0;
    c_init_raddr				=   {3'd0, r_par_tag};
    n_child_tags            	=   r_child_tags;
    n_numchildren				=   r_numchildren;
    n_numchild_mod3				=   r_numchild_mod3;
    graph_wdata					=   {i_node_tag, r_child_tags};
    n_par_tag					=   r_par_tag;
	n_free_addr					=	r_free_addr;
    o_init_stall				=   1'b0;
	c_count_dec					=	0;
	o_req_ack					=	1'b1;

    case (r_init_state)
        INIT_IDLE: begin
			if (~r_start_counting &i_node_tag_vld & (i_node_tag[11:6] == NODESET_NUM)) begin
                n_init_state		=   INIT_WRITING;
                n_numchildren		=   0;
                n_numchild_mod3		=   0; 
                n_par_tag			=   i_node_tag[5:0];

                graph_wen			=	1'b1;
                graph_wdata			=	{27'd0, r_free_addr};
                graph_waddr			=	{3'd0, i_node_tag[5:0]};
            end
			else if (i_node_tag_vld) begin
				n_init_state		=	INIT_ALTLIST_WAIT;
			end
        end
        INIT_WRITING: begin
            if (i_list_complete) begin
                if (r_numchild_mod3 != 0) begin
                    graph_wen       =   1'b1;
                    graph_waddr     =   r_free_addr;
                    graph_wdata     =   {r_child_tags, 12'd0};

                    n_free_addr		=   r_free_addr + 1;
                end
 
                c_init_rden			=   1'b1;
                c_init_raddr		=   {3'd0, r_par_tag};
                n_init_state		=   INIT_WRITE_COMPLETE;
            end
            else if (i_node_tag_vld) begin
                n_child_tags		=   {i_node_tag, r_child_tags} >> 12;
                n_numchildren		=   r_numchildren + 1;
                n_numchild_mod3		=   (r_numchild_mod3 == 2) ? 0 : r_numchild_mod3 + 1;

                if (r_numchild_mod3 == 2) begin
                    graph_wen		=   1'b1;
                    graph_waddr		=   r_free_addr;
                    graph_wdata		=   {i_node_tag, r_child_tags};
                    n_free_addr		=   r_free_addr + 1;
                end
            end
        end
        INIT_WRITE_COMPLETE: begin
            graph_wen					=   1'b1;
            graph_waddr					=   {3'd0, r_par_tag};
            graph_wdata					=   graph_rdata;
            graph_wdata[9+:8]			=   r_numchildren; // 9 bits for the address node start, 8 bits to store num_nodes
            o_init_stall				=   1'b1;
			n_graph_complete[r_par_tag]	=	1'b1;
            n_init_state				=   INIT_IDLE;
        end
		INIT_ALTLIST_WAIT: begin
			if (i_list_complete) begin
				n_init_state		=	INIT_IDLE;
			end
		end
    endcase
end

localparam			CALC_IDLE		=	0;
localparam			CALC_INIT		=	1;
localparam			CALC_WAIT		=	2;
localparam			CALC_SENDING	=	3;

reg  [7:0]			r_in_count[63:0];
reg  [63:0]			c_count_inc;
reg  [63:0]			c_count_dec;

reg  [1:0]			r_calc_state, n_calc_state;
reg					c_calc_rden;
reg  [8:0]			c_calc_raddr;
reg  [7:0]			r_numchild_left, n_numchild_left;
reg  [8:0]			r_list_ptr, n_list_ptr;
reg  [1:0]			r_numdone_mod3, n_numdone_mod3;
reg  [35:0]			r_tags, n_tags;
reg					r_use_memreg, n_use_memreg;
reg  [63:0]			r_signal_sent, n_signal_sent;
reg  [63:0]			r_node_sendreq;
reg  [35:0]			t_tags;

// Separate memory for the calculated vals.
// This will most likely synth into a LUTRAM
reg  [NUM_PATHS_DW+1:0]		num_paths[63:0];
reg  [5:0]					num_paths_waddr;
reg  [5:0]					num_paths_raddr;
reg  [NUM_PATHS_DW+1:0]		num_paths_rdata;
reg  [NUM_PATHS_DW+1:0]		num_paths_wdata;
reg							num_paths_wen;
reg							num_paths_ren;
reg  [NUM_PATHS_DW+1:0]		r_new_payload, n_new_payload;
reg  [5:0]					r_newpaths_tag, n_newpaths_tag;
reg  [5:0]					r_sender_tag, n_sender_tag;
reg							r_add_paths, n_add_paths;
reg  [NUM_PATHS_DW+1:0]		n_req_payload;

always @(*) begin
	c_count_inc						=	0;
	c_count_dec						=	0;
	n_calc_state					=	r_calc_state;
	n_numchild_left					=	r_numchild_left;
	n_list_ptr						=	r_list_ptr;
	n_numdone_mod3					=	r_numdone_mod3;
	t_tags							=	r_use_memreg ? graph_rdata : r_tags;
	n_tags							=	t_tags;
	n_signal_sent					=	r_signal_sent;
	n_use_memreg					=	r_use_memreg;
	n_req_payload					=	o_req_payload;
	n_sender_tag					=	r_sender_tag;

	n_newpaths_tag					=	0;
	n_new_payload					=	0;
	n_add_paths						=	1'b0;
	
	c_calc_rden						=	1'b0;
    c_calc_raddr           	        =	0;

	o_req_vld						=	1'b0;
	o_req_nodenum					=	t_tags[0+:12];
	o_req_ack						=	1'b1;

	num_paths_wen					=	1'b0;
	num_paths_wdata					=	0;
	num_paths_waddr					=	0;
	num_paths_ren					=	1'b0;
	num_paths_raddr					=	0;

	// Code to service input requests, and handle writing of num_paths memory
	if (i_req_vld) begin
		c_count_inc[i_req_nodenum]	=	~r_start_counting;

		// Read, then write the new number of paths into memory in the next cycle
		if (r_start_counting) begin
			num_paths_ren			=	1'b1;
			num_paths_raddr			=	i_req_nodenum;
			n_add_paths				=	1'b1;
			n_new_payload			=	i_req_payload;
			n_newpaths_tag			=	i_req_nodenum;
		end
		else begin
			num_paths_waddr			=	i_req_nodenum;
			num_paths_wen			=	1'b1;
			num_paths_wdata			=	0;
		end
	end

	if (r_add_paths) begin
		num_paths_wen				=	1'b1;
		c_count_dec[r_newpaths_tag]	=	1'b1;
		num_paths_waddr				=	r_newpaths_tag;

		// Logic to update paths based on incoming request threshold
		if (num_paths_rdata[0+:2] == r_new_payload[0+:2]) begin
			num_paths_wdata			=	{num_paths_rdata[2+:NUM_PATHS_DW] + r_new_payload[2+:NUM_PATHS_DW], r_new_payload[0+:2]};
		end
		else if ((r_new_payload[0] & ~num_paths_rdata[0])| (r_new_payload[1] & ~num_paths_rdata[1])) begin
			num_paths_wdata			=	{r_new_payload[2+:NUM_PATHS_DW], (r_new_payload[0+:2] | num_paths_rdata[0+:2])};
		end
		// Ignore the packet if we're at a better threshold
		else begin
			num_paths_wen			=	1'b0;
		end
	end
	else if (r_start_counting & i_startnode & (i_node_tag[11:6] == NODESET_NUM)) begin
		num_paths_waddr				=	i_node_tag[5:0];
		num_paths_wen				=	1'b1;
		num_paths_wdata				=	1 << 2; // 2 bits extra for thresholds
		c_count_dec[i_node_tag[5:0]]=	1'b1;
		//$display("%0h", c_count_dec);
	end


	// Starting to write the children of startnode. Set the no. of incoming edges to 1, so that the info starts propogating
	if (i_node_tag_vld & (i_node_tag[11:6] == NODESET_NUM) & (r_init_state == INIT_IDLE)) begin
		c_count_inc[i_node_tag[5:0]]	=	i_startnode & ~r_start_counting;
	end

	// Code to handle sending requests to other nodes - this gets lesser priority than accepting requests when both want to access the graph mem
	case (r_calc_state)
		CALC_IDLE: begin
			for (i = 0; i < 64; i=i+1) begin
				// If we've started counting, then c_init_rden can't be 1
				if (r_node_sendreq[i] & ((~c_init_rden & ~r_start_counting) | (r_start_counting & ~num_paths_ren))) begin
					n_calc_state	=	CALC_INIT;
					c_calc_rden		=	1'b1;
					c_calc_raddr	=	{3'd0, i[5:0]};
					n_signal_sent[i]=	1'b1;
					n_sender_tag	=	i;

					num_paths_ren	=	1'b1;
					num_paths_raddr	=	{3'd0, i[5:0]};
				end
			end
		end
		CALC_INIT : begin
			// Parse the field here to get the address of children list, and the number of children
			n_list_ptr				=	graph_rdata[0+:9];
			n_numchild_left			=	graph_rdata[9+:8];
			n_numdone_mod3			=	0;

			if (c_init_rden) begin
				n_calc_state		=	CALC_WAIT;
			end
			else begin
				c_calc_rden			=	1'b1;
				c_calc_raddr		=	graph_rdata[0+:9];
				n_calc_state		=	CALC_SENDING;
				n_use_memreg		=	1'b1;
				
				// We will always enter this condition when start_counting is 1
				n_req_payload			=	num_paths_rdata;
				if ({NODESET_NUM[5:0], r_sender_tag} == i_fft_tag)
					n_req_payload[0]	=	1'b1;
				if ({NODESET_NUM[5:0], r_sender_tag} == i_dac_tag)
					n_req_payload[1]	=	1'b1;
			end
		end
		CALC_WAIT : begin
			// State to wait while the graph_init process is reading memory
			// This state only occurs during graph init stage
			if (~c_init_rden) begin
				n_numdone_mod3		=	0;
				c_calc_rden			=	1'b1;
				c_calc_raddr		=	r_list_ptr;
				n_calc_state		=	CALC_SENDING;
				n_use_memreg		=	1'b1;
			end
		end
		CALC_SENDING : begin
			// This can progress as it is in both counting and non-counting stages
			n_use_memreg			=	1'b0;
			o_req_vld				=	1'b1;
			o_req_nodenum			=	t_tags[24+:12];

			if (i_req_ack) begin
				n_tags				=	t_tags << 12;
				n_numdone_mod3		=	r_numdone_mod3 + 1;
				n_numchild_left		=	r_numchild_left - 1;

				if (r_numdone_mod3 == 2) begin
					n_numdone_mod3		=	0;
					n_list_ptr			=	r_list_ptr + 1;
					if (c_init_rden) begin
						n_calc_state	=	CALC_WAIT;
					end
					else begin
						c_calc_rden		=	1'b1;
						c_calc_raddr	=	r_list_ptr + 1;
						n_use_memreg	=	1'b1;
					end
				end

				if (r_numchild_left == 1) begin
					n_calc_state		=	CALC_IDLE;
				end
			end
		end
	endcase

	o_reqs_complete		=	~(|r_node_sendreq) & (r_calc_state == CALC_IDLE) & (r_init_state == INIT_IDLE);

	if (i_start_counting & ~r_start_counting) begin
		n_signal_sent	=	0;
	end

	// if (o_req_vld & i_req_ack & r_start_counting) begin
	// 	$display("%0h sent to %0h, %0d paths time %0t",{NODESET_NUM[5:0], r_sender_tag}, o_req_nodenum, o_req_paths ,$time);
	// end
end


assign	graph_rden		=	c_calc_rden | c_init_rden;
assign	graph_raddr		=	c_init_rden ? c_init_raddr : c_calc_raddr;

reg			r_start_counting;
reg [63:0]	r_graph_marked;
always @(posedge clk) begin
    if (rst) begin
        r_init_state		<=	INIT_IDLE;
        r_free_addr			<=	64; // 64 possible nodes per nodeset
		r_graph_complete	<=	0;
		r_signal_sent		<=	0;
		r_node_sendreq		<=	0;
		r_calc_state		<=	CALC_IDLE;
		r_start_counting	<=	0;
		r_graph_marked		<=	0;

		for(i = 0; i < 64; i=i+1) begin
			r_in_count[i]	<=	0;
		end
	end
    else begin
        r_init_state		<=	n_init_state;
        r_free_addr			<=	n_free_addr;
		r_graph_complete	<=	n_graph_complete;
		r_signal_sent		<=	n_signal_sent;
		r_calc_state		<=	n_calc_state;
		r_start_counting	<=	i_start_counting;

		for(i=0; i < 64; i=i+1) begin
			if (c_count_inc[i]) begin
				r_in_count[i]	<=	r_in_count[i] + 1;
				r_graph_marked[i]<=	1'b1;
			end
			else if (c_count_dec[i]) begin
				r_in_count[i]	<=	r_in_count[i] - 1;
			end

			// Depending on the stage of processing, the request sending condition changes
			if (i_start_counting) begin
				r_node_sendreq[i]<=	(r_in_count[i] == 0) & ((r_graph_marked[i] & r_graph_complete[i]) & ~n_signal_sent[i]);
			end
			else begin
				r_node_sendreq[i]<=	(r_in_count[i] > 0) & (n_graph_complete[i] & ~n_signal_sent[i]);
			end
		end
    end

	r_use_memreg			<=	n_use_memreg;
    r_child_tags          	<=	n_child_tags;
    r_numchildren           <=	n_numchildren;
    r_numchild_mod3         <=	n_numchild_mod3;
    r_par_tag               <=	n_par_tag;
	r_numchild_left			<=	n_numchild_left;
	r_list_ptr				<=	n_list_ptr;
	r_numdone_mod3			<=	n_numdone_mod3;
	r_tags					<=	n_tags;
	r_sender_tag			<=	n_sender_tag;

	r_newpaths_tag			<=	n_newpaths_tag;
	r_add_paths				<=	n_add_paths;
	r_new_payload			<=	n_new_payload;
	o_req_payload			<=	n_req_payload;

    if (graph_wen)
        graph_ram[graph_waddr]	<=	graph_wdata;

    if (graph_rden)
        graph_rdata				<=  graph_ram[graph_raddr];

	if (num_paths_wen)
		num_paths[num_paths_waddr]	<=	num_paths_wdata;

	if (num_paths_ren) begin
		if (num_paths_wen & (num_paths_raddr == num_paths_waddr)) begin
			num_paths_rdata			<=	num_paths_wdata;
		end
		else begin
			num_paths_rdata			<=	num_paths[num_paths_raddr];
		end
	end
end

endmodule
