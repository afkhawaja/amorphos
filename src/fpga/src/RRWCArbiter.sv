import ShellTypes::*;
import AMITypes::*;

// Currently only supports N = 4,2,1
module RRWCArbiter #(parameter N = 2)
(
	// General signals
	input  clk,
	input  rst,
	// Request vector
	input[N-1:0] req,
	// Grant vector
	output[N-1:0] grant
);

	wire dummy;

	generate
		if (N == 8) begin: using_2_4in_arb
			// Intermediate connections
			wire arb_req[1:0];
			wire arb_grant[1:0];	
			// Create 2 4 input arbiters
			FourInputArbiter 
			rr_4in_arb_0
			(
				// General signals
				.clk(clk),
				.rst(rst),
				// Request vector
				.req(req[3:0]),
				// Grant vector to requester
				.grant(grant[3:0]),
				// Request to next level arbiter
				.arb_req_out(arb_req[0]),
				// Connect to 2nd level arb
				.arb_grant_in(arb_grant[0])
			);	
			FourInputArbiter 
			rr_4in_arb_1
			(
				// General signals
				.clk(clk),
				.rst(rst),
				// Request vector
				.req(req[7:4]),
				// Grant vector to requester
				.grant(grant[7:4]),
				// Request to next level arbiter
				.arb_req_out(arb_req[1]),
				// Connect to 2nd level arb
				.arb_grant_in(arb_grant[1])
			);
			// 2nd level arbiter connecting them
			TwoInputArbiter 
			second_lvl_arb_0
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
				.arb_req(dummy),
				// There is no next level
				.arb_grant(1'b1)
			);
		end else if (N == 4) begin : using_2_2in_arb
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
				.arb_req(dummy),
				// There is no next level
				.arb_grant(1'b1)
			);	
		end else if (N == 2) begin : using_2in_arb
			TwoInputArbiter 
			rr_2in_arb
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
				.arb_req(dummy),
				// There is no next level
				.arb_grant(1'b1)
			);
		end else begin : no_arb_needed// N < 2, must be 1
			assign grant[0] = req[0];
		end
	endgenerate
		
endmodule