// testbench for the FIFO
`timescale 1 ns / 1 ns
module arbiter_test();

	reg clk;
	reg rst;

	reg[4-1:0] req;
	wire[4-1:0] grant;
	
	RRWCArbiter 
	#(
	.N(4)
	)
	test_arbiter
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req(req),
		// Grant vector
		.grant(grant)
	);

	

	
always #1 clk = !clk;


initial begin
	$display("Starting up here!\n");
	req = 4'b0_0_0_0;
	clk = 1'b1;
	rst = 1'b1;
	#2
	rst = 1'b0;
	$display("Test 1");
	req = 4'b1_1_1_1;
	for (int i = 0; i < 16; i = i + 1) begin
		#2
		$display("req=%b , grant=%b", req, grant);
	end
end
	
	
endmodule