`timescale 1ns/1ps

module tb;

    // ---------------------------------
    // Signals
    // ---------------------------------
    logic        clk;
    logic        rst;
    logic [7:0]  i_char;
    logic        i_vld;
    wire         o_stall;
	wire		 o_result_vld;
	wire [63:0]	 o_result;

	top_level dut_inst(
		.clk				(clk         ),
		.rst				(rst         ),

		.i_vld				(i_vld       ),
		.i_char				(i_char      ),
		.o_stall			(o_stall     ),

		.o_error			(o_error     ),
		.o_result			(o_result	 ),
		.o_result_vld		(o_result_vld)
	);

    // ---------------------------------
    // Clock (100 MHz)
    // ---------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------
    // File variables
    // ---------------------------------
    integer fd;
    integer c;

    // ---------------------------------
    // rst
    // ---------------------------------
    initial begin
		$dumpfile("top_level.fst");
		$dumpvars(0, tb);
	
        rst					= 1'b1;
        i_char				= 8'd0;
        i_vld				= 1'b0;

        repeat (5) @(posedge clk);
        rst					= 1'b0;
    end

    // ---------------------------------
    // Character streaming w/ backpressure
    // ---------------------------------
	logic [15:0]		counter;
    initial begin
        @(negedge rst);
		counter = 0;

        //fd = $fopen("main_input.txt", "r");
        fd = $fopen("input.txt", "r");
		if (fd == 0) begin
        	$display("ERROR: Could not open input.txt");
			$finish;
		end

        // Preload first character
        c = $fgetc(fd);

        while (c != -1) begin
            // Drive current character
            i_char		<= c[7:0];
            i_vld		<= 1'b1;

            // Wait until DUT accepts it
			@(posedge clk)
			while (o_stall)
				@(posedge clk);

			counter <= counter + 1;

            // Character accepted on this clock edge
            // Fetch next character
            c = $fgetc(fd);
        end

        // No more data
        @(posedge clk);
        i_vld			<= 1'b0;
        i_char			<= 7'd0;

        $fclose(fd);

		while (~o_result_vld)
			@(posedge clk);

		$display("Final answer : %0d", o_result);
        repeat (2) @(posedge clk);
        $display("TB completed");
        $finish;
    end

endmodule

