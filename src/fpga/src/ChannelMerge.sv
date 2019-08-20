/*

	Merges requests to the same channel from different ports of the same app
	

	Author: Ahmed Khawaja


*/

import ShellTypes::*;
import AMITypes::*;

module ChannelMerge
(
    // User clock and reset
    input                   clk,
    input                   rst,
	// Interface from each port mapping to the same channel for the same app
	input AMIReq			ami_mem_req_in[AMI_NUM_PORTS-1:0],
	output logic			ami_mem_req_grant_out[AMI_NUM_PORTS-1:0],
	// Interface to the channel arbiters for translated requests per channel
	output AMIReq			ami_mem_req_out,
	input				    ami_mem_req_grant_in
);

	// Queue for requests coming from the user that need to be translated
	wire             reqQ_empty;
	wire             reqQ_full;
	logic            reqQ_enq;
	logic            reqQ_deq;
	AMIReq           reqQ_in;
	AMIReq           reqQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_chmergeReqQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIReq)),
				.LOG_DEPTH				(CHANNEL_MERGE_Q_DEPTH)
			)
			chmergeReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(reqQ_enq),
				.data                   (reqQ_in),
				.full                   (reqQ_full),
				.q                      (reqQ_out),
				.empty                  (reqQ_empty),
				.rdreq                  (reqQ_deq)
			);
		end else begin : FIFO_chmergeReqQ
			FIFO
			#(
				.WIDTH					($bits(AMIReq)),
				.LOG_DEPTH				(CHANNEL_MERGE_Q_DEPTH)
			)
			chmergeReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(reqQ_enq),
				.data                   (reqQ_in),
				.full                   (reqQ_full),
				.q                      (reqQ_out),
				.empty                  (reqQ_empty),
				.rdreq                  (reqQ_deq)
			);
		end
	endgenerate
	
	// Determine which request to put in the Queue
	// Arbiter for requests from address translation
	logic[AMI_NUM_PORTS-1:0] req;
	wire[AMI_NUM_PORTS-1:0]  grant;
	
	RRWCArbiter 
	#(
		.N(AMI_NUM_PORTS)
	)
	port_arbiter
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req(req),
		// Grant vector
		.grant(grant)
	);

	genvar i;
	generate
		for (i = 0; i < AMI_NUM_PORTS; i = i + 1) begin : requests
			assign req[i] = ami_mem_req_in[i].valid && !reqQ_full;
			assign ami_mem_req_grant_out[i] = grant[i] && !reqQ_full;
		end
	endgenerate
	
	assign reqQ_enq = (|grant) && !reqQ_full;
	
	// Mux in the correct request
	/*OneHotMux
	#(
		.WIDTH($bits(AMIReq)),
		.N(AMI_NUM_PORTS)
	)
	port_select_mux
	(
		.data(ami_mem_req_in),
		.select(grant),
		.out(reqQ_in)
	);*/
	localparam MUX_BITS = AMI_NUM_PORTS > 1 ? $clog2(AMI_NUM_PORTS) : 1;
	logic[MUX_BITS-1:0] mux_select;
	OneHotEncoder
	#(
		.ONE_HOTS(AMI_NUM_PORTS),
		.MUX_SELECTS(MUX_BITS)
	)
	one_hot_encoder
	(
		.one_hots(grant),
		.mux_select(mux_select)
	);

	always_comb begin
		reqQ_in = ami_mem_req_in[0];
		if (AMI_NUM_PORTS == 1) begin
			reqQ_in = ami_mem_req_in[0];
		end else if (AMI_NUM_PORTS == 2) begin
			if (mux_select == 1'b1) begin
				reqQ_in = ami_mem_req_in[1];
			end else begin 
				reqQ_in = ami_mem_req_in[0];
			end
		end else if (AMI_NUM_PORTS == 4) begin
			if (mux_select == 2'b11) begin
				reqQ_in = ami_mem_req_in[3];
			end else if (mux_select == 2'b10) begin 
				reqQ_in = ami_mem_req_in[2];
			end else if (mux_select == 2'b01) begin
				reqQ_in = ami_mem_req_in[1];
			end else begin
				reqQ_in = ami_mem_req_in[0];
			end
		end else if (AMI_NUM_PORTS == 8) begin
			if (mux_select == 3'b111) begin
				reqQ_in = ami_mem_req_in[7];
			end else if (mux_select == 3'b110) begin
				reqQ_in = ami_mem_req_in[6];
			end else if (mux_select == 3'b101) begin
				reqQ_in = ami_mem_req_in[5];
			end else if (mux_select == 3'b100) begin
				reqQ_in = ami_mem_req_in[4];
			end else if (mux_select == 3'b011) begin
				reqQ_in = ami_mem_req_in[3];
			end else if (mux_select == 3'b010) begin
				reqQ_in = ami_mem_req_in[2];
			end else if (mux_select == 3'b001) begin
				reqQ_in = ami_mem_req_in[1];
			end else begin // 3'b000
				reqQ_in = ami_mem_req_in[0];
			end
		end
	end

	// Check if the request is accepted by the next stage and remove it from the queue if so
	logic deq_ok;
    AMIReq disabled_req;
	assign disabled_req = '{valid: 1'b0, isWrite: 1'b0, srcPort: 0, srcApp: 0, channel: 0, addr: 0, size: 0, data: 0};
	assign deq_ok = ami_mem_req_grant_in && reqQ_out.valid && !reqQ_empty;
	assign reqQ_deq = deq_ok;
	assign ami_mem_req_out = (!reqQ_empty ? reqQ_out : disabled_req);
	
endmodule
