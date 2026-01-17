// Module which takes as input three 5-bit numbers representing a node, updates the hash table and outputs a corresponding node number.
module hash_table (
    input  wire         clk,
    input  wire         rst,

    input  wire [14:0]  i_node_str,
    input  wire         i_node_str_vld,
    output reg          o_stall,

	input  wire			i_stall,
    output reg          o_error, // Signal that goes high if the hash table is "full"
    output reg  [11:0]  o_node_num,
    output reg          o_node_num_vld
);

localparam HASH_RAM_DEPTH           =   512;
localparam HASH_RAM_ADDR_WIDTH      =   $clog2(HASH_RAM_DEPTH);

reg  [71:0]                         hash_ram[HASH_RAM_DEPTH-1:0];
reg  [HASH_RAM_ADDR_WIDTH-1:0]      hash_offset, hash_offset_n;

reg  [HASH_RAM_ADDR_WIDTH-1:0]      c_hash_raddr, c_hash_waddr;
reg  [HASH_RAM_ADDR_WIDTH-1:0]      hash_curr_data_addr;
reg                                 c_hash_ren, c_hash_wen;
reg  [71:0]                         hash_rdata, c_hash_wdata;
reg									r_nodenum_wait, n_nodenum_wait;

localparam HASH_IDLE                =   0;
localparam HASH_COMPUTE             =   1;
localparam STALL_WAIT				=	2;

reg                                 rst_in_progress;
reg [HASH_RAM_ADDR_WIDTH-1:0]       rst_counter;
reg                                 hash_state, hash_state_n;


reg                                 n_error;

// Temporary registers to use in memory parsing
reg  [7:0]                          t_ids[7:0];
reg  [3:0]							t_num_nodes;
reg  [3:0]							t_next_addr;
reg  [4:0]							t_curr_nodenum;
reg                                 t_match_found;
integer j;

// State machine
always @(*) begin
    c_hash_ren                      =   1'b0;
    c_hash_wen                      =   1'b0;
    o_stall                         =   1'b1; // In most states, we can't accept new input
    o_node_num_vld					=   1'b0;
    n_error							=   1'b0;
    hash_state_n                    =   hash_state;
    hash_offset_n                   =   hash_offset;
	n_nodenum_wait					=	r_nodenum_wait;

    c_hash_raddr                    =   {i_node_str[14:10], i_node_str[5], i_node_str[0], 2'd0}; // 4 mem levels for each sub-group
    c_hash_waddr                    =   hash_curr_data_addr;
    o_node_num                      =   0;

    case (hash_state)
        HASH_IDLE: begin
            o_stall                 =   1'b0;
            if (i_node_str_vld) begin
                c_hash_ren          =   1'b1;
                c_hash_raddr        =   {i_node_str[14:10], i_node_str[5], i_node_str[0], 2'd0};
                hash_state_n        =   HASH_COMPUTE;
                o_stall             =   1'b1;
            end
        end
        HASH_COMPUTE: begin
            // Parse the newly obtained string to see if we get a hit
            for (j = 0 ; j < 8; j++) begin
                t_ids[j]            =   hash_rdata[8*j+:8];
            end
			t_num_nodes				=	hash_rdata[64+:4];
			t_next_addr				=	hash_rdata[68+:4];

            // First, we check if there was a match in the currently present identifiers
            t_match_found           =   1'b0;
            for (j = 0; j < 8; j++) begin
                if ((t_ids[j] == {i_node_str[9:6],i_node_str[4:1]}) & (t_num_nodes > j)) begin
                    o_node_num_vld  =   1'b1;
					t_curr_nodenum	=	9*hash_curr_data_addr[1:0] + j; 
                    o_node_num      =   {hash_curr_data_addr[8:2], t_curr_nodenum};
					n_nodenum_wait	=	{hash_curr_data_addr[8:2], t_curr_nodenum};
                    hash_state_n    =   i_stall ? STALL_WAIT : HASH_IDLE;
                    o_stall         =   1'b0;

                    t_match_found   =   1'b1;
                end
            end

            if (~t_match_found) begin
                if (t_num_nodes[3]) begin
                    // t_num_nodes == 9 indicates that a new level has been created
                    if (t_num_nodes[0]) begin
                        // No change to this level
                        c_hash_ren      =   1'b1;
                        c_hash_raddr    =   (hash_curr_data_addr[1:0] == 3) ? ((t_next_addr+104)*4) : (hash_curr_data_addr + 1);
                    end
                    else begin
                        // create a new level
                        t_num_nodes[0]  =   1'b1;
                        c_hash_wen      =   1'b1;
                        c_hash_waddr    =   hash_curr_data_addr;

                        c_hash_ren      =   1'b1;
						if (hash_curr_data_addr[1:0] == 3) begin
                        	t_next_addr		=   hash_offset;
                        	hash_offset_n   =	hash_offset + 1;
							c_hash_raddr	=	(hash_offset + 104)*4;

							if (hash_offset == 13)
								n_error		=   1'b1;
						end
						else begin
							c_hash_raddr	=	hash_curr_data_addr + 1;
						end
                    end
                end
                else begin
					// First send the output
                    o_node_num_vld      =   1'b1;
					t_curr_nodenum		=	9*hash_curr_data_addr[1:0] + t_num_nodes; 
                    o_node_num			=   {hash_curr_data_addr[8:2], t_curr_nodenum};

                    // Update the relevant parts of the memory
                    t_ids[t_num_nodes]  =   {i_node_str[9:6],i_node_str[4:1]};
                    t_num_nodes         =   t_num_nodes + 1;
                    c_hash_wen          =   1'b1;
                    c_hash_waddr        =   hash_curr_data_addr;

                    hash_state_n    	=   i_stall ? STALL_WAIT : HASH_IDLE;
                    n_nodenum_wait		=   {hash_curr_data_addr[8:2], t_curr_nodenum};
                    o_stall             =   1'b0;
                end
            end

            // We can create wdata using the temporary fields we've defined and the modifications made above
            for (j = 0 ; j < 8; j++) begin
                c_hash_wdata[8*j+:8]	=   t_ids[j];
            end
            c_hash_wdata[64+:4]			=   t_num_nodes;
			c_hash_wdata[68+:4]			=	t_next_addr;
        end
		STALL_WAIT : begin
			o_node_num_vld				=	1'b1;
			o_node_num					=	r_nodenum_wait;

			if (~i_stall)
				hash_state_n			=	HASH_IDLE;
		end
    endcase

    if (o_error) begin
        n_error				=   1'b1;
    end
        
    // Reset handling: overrides all the above, writes 1's to the entire memory
    if (rst_in_progress) begin
        o_stall				=	1'b1;
        c_hash_ren			=	1'b0;
        c_hash_wen			=	1'b1;
        c_hash_waddr		=	rst_counter;
        c_hash_wdata		=	0;
        o_node_num_vld		=	1'b0;

        hash_state_n		=	HASH_IDLE;
        hash_offset_n		=	0;
	end
end

always @(posedge clk) begin
    if (rst) begin
        hash_offset             <=	0;
        hash_state              <=  HASH_IDLE;
        rst_in_progress         <=  1'b1;
        rst_counter             <=  0;
        o_error         	    <=  1'b0;
    end
    else begin
        if (rst_in_progress) begin
            rst_counter         <=  rst_counter + 1;
            if (rst_counter == HASH_RAM_DEPTH-1)
                rst_in_progress <=  0;
        end

        hash_state              <=  hash_state_n;
        hash_offset             <=  hash_offset_n;
		r_nodenum_wait			<=	n_nodenum_wait;
        o_error      	        <=  n_error;
    end

    // Memory-related assignments
    if (c_hash_ren) begin
        hash_rdata              <=  hash_ram[c_hash_raddr];
        hash_curr_data_addr     <=  c_hash_raddr;
    end

    if (c_hash_wen) begin
        hash_ram[c_hash_waddr]  <=  c_hash_wdata;
    end
end

endmodule
