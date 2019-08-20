/*

	Arbitrates which requests to accept, can be connected
	in a multi-level tree of 2-input arbiters
	
	Author: Ahmed Khawaja


*/

module TwoInputArbiter
(
	// General signals
	input  clk,
	input  rst,
	// Request vector
	input req0,
	input req1,
	// Grant vector to requester
	output logic grant0,
	output logic grant1,
	// Request to next level arbiter
	output logic arb_req,
	// See if the next level arbiter granted you
	input  arb_grant
);

	logic last_serviced;
	logic new_last_serviced;
	
	always@(posedge clk) begin
		if (rst) begin
			last_serviced <= 1'b1;
		end else begin
			last_serviced <= new_last_serviced;
		end
	end
	
	always_comb begin
		arb_req = req0 || req1;
		if (req0 && ((last_serviced != 1'b0) || !req1)) begin
			grant0 = arb_grant;
			grant1 = 1'b0;
			new_last_serviced = arb_grant ? 1'b0 : last_serviced;
		end else if (req1 && ((last_serviced != 1'b1) || !req0)) begin
			grant0 = 1'b0;
			grant1 = arb_grant;
			new_last_serviced = arb_grant ? 1'b1 : last_serviced;
		end else begin
			grant0 = 1'b0;
			grant1 = 1'b0;
			new_last_serviced = last_serviced;
		end
	end

endmodule