// testbench for the FIFO
`timescale 1 ns / 1 ns

module TwoInputArbTest();

	reg clk;
	reg rst;
	
	reg req0,req1;
	reg arb_grant;
	wire grant0,grant1;
	wire arb_req;

	TwoInputArbiter arb2input
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req0(req0),
		.req1(req1),
		// Grant vector to requester
		.grant0(grant0),
		.grant1(grant1),
		// Request to next level arbiter
		.arb_req(arb_req),
		// See if the next level arbiter granted you
		.arb_grant(arb_grant)
	);


	
always #1 clk = !clk;


initial begin
	$display("Starting up here!\n");
	arb_grant = 1'b1;
	req0 = 1'b0;
	req1 = 1'b0;
	clk = 1'b0;
	rst = 1'b1;
	#2
	rst = 1'b0;
	$display("Test 1");
	req0 = 1'b1;
	req1 = 1'b1;
	for (int i = 0; i < 8; i = i + 1) begin
		#2
		$display("req0=%b req1=%b, grant0=%b grant1=%b", req0, req1, grant0, grant1);
	end
end


endmodule