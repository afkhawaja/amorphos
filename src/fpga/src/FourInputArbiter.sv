module FourInputArbiter
(
	// General signals
	input  clk,
	input  rst,
	// Request vector
	input[3:0] req,
	// Grant vector
	output[3:0] grant,
	// Request to next level arbiter
	output arb_req_out,
	// See if the next level arbiter granted you
	input  arb_grant_in
);

	// Intermediate connections
	wire arb_req[1:0];
	wire arb_grant[1:0];
	// Create 2 2 input arbiters
	TwoInputArbiter 
	rr_2in_arb_0
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req0(req[0]),
		.req1(req[1]),
		// Grant vector to requester
		.grant0(grant[0]),
		.grant1(grant[1]),
		// Request to next level arbiter
		.arb_req(arb_req[0]),
		// Connect to 2nd level arb
		.arb_grant(arb_grant[0])
	);
	TwoInputArbiter 
	rr_2in_arb_1
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req0(req[2]),
		.req1(req[3]),
		// Grant vector to requester
		.grant0(grant[2]),
		.grant1(grant[3]),
		// Request to next level arbiter
		.arb_req(arb_req[1]),
		// Connect to 2nd level arb
		.arb_grant(arb_grant[1])
	);		
	// 2nd level arbiter connecting them
	TwoInputArbiter 
	second_lvl_arb
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req0(arb_req[0]),
		.req1(arb_req[1]),
		// Grant vector to requester
		.grant0(arb_grant[0]),
		.grant1(arb_grant[1]),
		// Request to next level arbiter
		.arb_req(arb_req_out),
		// There is no next level
		.arb_grant(arb_grant_in)
	);	


endmodule
