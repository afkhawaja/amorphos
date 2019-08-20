/*
	
	Top level module virtualizing the Soft Reg interface
	
	Author: Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module AOS_SR_1_to_2#(parameter SELECT_BIT_INDEX = 0, FIFO_LOG_DEPTH = 2, FIFO_TYPE = 0)
(
    input                               clk,
    input                               rst,
	//input								app_enable[1:0],
	// Incoming SoftReg request
	input  SoftRegReq					sr_req_in,
	// Routed to the correct destination
	output SoftRegReq                   sr_req_out_0,
	output SoftRegReq					sr_req_out_1

);

	// FIFO to buffer in the incoming requests
    logic       buffer_sr_req_FIFO_enq;
    logic       buffer_sr_req_FIFO_deq;
    wire        buffer_sr_req_FIFO_full;
    wire        buffer_sr_req_FIFO_empty;
    SoftRegReq  buffer_sr_req_FIFO_head;
	logic[5:0] selector_bits; // bits 15-10 of the address (inclusive)
	assign selector_bits = buffer_sr_req_FIFO_head.addr[15:10];
	
    HullFIFO
    #(
        .TYPE                   (FIFO_TYPE),
        .WIDTH                  ($bits(SoftRegReq)), // matches the data width
        .LOG_DEPTH              (FIFO_LOG_DEPTH)
    )
    buffer_sr_req_queue
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (buffer_sr_req_FIFO_enq),
        .data                   (sr_req_in),
        .full                   (buffer_sr_req_FIFO_full),
        .q                      (buffer_sr_req_FIFO_head),
        .empty                  (buffer_sr_req_FIFO_empty),
        .rdreq                  (buffer_sr_req_FIFO_deq)
    );

	// Route from the buffer to the correct port
	always_comb begin
		// default is to do nothing
		buffer_sr_req_FIFO_enq = 1'b0;
		buffer_sr_req_FIFO_deq = 1'b0;
		// Default values for the output ports
		sr_req_out_0.valid   = 1'b0;
		sr_req_out_0.isWrite = 1'b0;
		sr_req_out_0.addr    = 0;
		sr_req_out_0.data    = 0;
		sr_req_out_1.valid   = 1'b0;
		sr_req_out_1.isWrite = 1'b0;
		sr_req_out_1.addr    = 0;
		sr_req_out_1.data    = 0;
		// Route the head of the queue
		if (buffer_sr_req_FIFO_head.valid && !buffer_sr_req_FIFO_empty) begin
			// route to port 0
			if (selector_bits[SELECT_BIT_INDEX] == 1'b0) begin
				sr_req_out_0 = buffer_sr_req_FIFO_head;
			// route to port 1
			end else begin
				sr_req_out_1 = buffer_sr_req_FIFO_head;
			end
			// always dequeu
			buffer_sr_req_FIFO_deq = 1'b1;
		end
	end

	// Buffer incoming requests to be routed
	always_comb begin
		buffer_sr_req_FIFO_enq = 1'b0;
		if (sr_req_in.valid && !buffer_sr_req_FIFO_full) begin
			buffer_sr_req_FIFO_enq = 1'b1;
		end
	end
	
endmodule

module AOS_SR_2_to_1#(parameter FIFO_LOG_DEPTH = 2, FIFO_TYPE = 0)
(
    input                               clk,
    input                               rst,
	//input								app_enable[1:0],
	//  Two incoming SoftReg Responses
	input SoftRegResp                   sr_resp_in_0,
	input SoftRegResp                   sr_resp_in_1,
	// Merged output
	output SoftRegResp                  sr_resp_out
);

	// Two queues to buffer each incoming port
	wire             respQ_empty[1:0];
	wire             respQ_full[1:0];
	logic	         respQ_enq[1:0];
	logic            respQ_deq[1:0];
	SoftRegResp      respQ_head[1:0];

	HullFIFO
	#(
		.TYPE                   (FIFO_TYPE),
		.WIDTH                  ($bits(SoftRegResp)), // matches the data width
		.LOG_DEPTH              (FIFO_LOG_DEPTH)
	)
	buffer_sr_resp_queue_0
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (respQ_enq[0]),
		.data                   (sr_resp_in_0),
		.full                   (respQ_full[0]),
		.q                      (respQ_head[0]),
		.empty                  (respQ_empty[0]),
		.rdreq                  (respQ_deq[0])
	);

	HullFIFO
	#(
		.TYPE                   (FIFO_TYPE),
		.WIDTH                  ($bits(SoftRegResp)), // matches the data width
		.LOG_DEPTH              (FIFO_LOG_DEPTH)
	)
	buffer_sr_resp_queue_1
	(
		.clock                  (clk),
		.reset_n                (~rst),
		.wrreq                  (respQ_enq[1]),
		.data                   (sr_resp_in_1),
		.full                   (respQ_full[1]),
		.q                      (respQ_head[1]),
		.empty                  (respQ_empty[1]),
		.rdreq                  (respQ_deq[1])
	);
	
	// buffer incoming response
	always_comb begin
		respQ_enq[0] = 1'b0;
		respQ_enq[1] = 1'b0;
		if (sr_resp_in_0.valid && !respQ_full[0]) begin
			respQ_enq[0] = 1'b1;
		end
		if (sr_resp_in_1.valid && !respQ_full[1]) begin
			respQ_enq[1] = 1'b1;
		end
	end
	
	// arbitrate between queue 0 and 1
	always_comb begin
		respQ_deq[0] = 1'b0;
		respQ_deq[1] = 1'b0;
		sr_resp_out.valid = 1'b0;
		sr_resp_out.data  = respQ_head[0];
		// route from queue 0
		if (respQ_head[0].valid && !respQ_empty[0]) begin
			respQ_deq[0] = 1'b1;
			sr_resp_out.data  = respQ_head[0];
			sr_resp_out.valid = 1'b1;
		// route from queue 1
		end else if (respQ_head[1].valid && !respQ_empty[1]) begin
			respQ_deq[1] = 1'b1;
			sr_resp_out.data  = respQ_head[1];
			sr_resp_out.valid = 1'b1;
		end
	end
	
endmodule

module AOS_Request_RouteTree#(parameter SR_NUM_APPS = 2)
(
    // User clock and reset
    input                               clk,
    input                               rst,
	input								app_enable[SR_NUM_APPS-1:0],
	// Request from host
	input SoftRegReq                    sr_req_from_host,
	// Requests to each app
	output SoftRegReq                   sr_req_to_app[SR_NUM_APPS-1:0]
);

parameter NUM_LAYERS = (SR_NUM_APPS > 1 ? $clog2(SR_NUM_APPS) : 1);

genvar layer_num;
genvar inst_num;
genvar app_num;

// Max size is the number in the final layer
SoftRegReq connects[NUM_LAYERS-1:0][SR_NUM_APPS-1:0];

generate
	if (SR_NUM_APPS == 1) begin : only_one
		assign sr_req_to_app[0] = sr_req_from_host;
	end else begin : more_than_one
		// Special code to handle layer 0
		AOS_SR_1_to_2 #(.SELECT_BIT_INDEX(NUM_LAYERS-1)) aos_sr_1_to_2_layer_0_inst(
			.clk(clk),
			.rst(rst),
			//.app_enable(),
			.sr_req_in(sr_req_from_host),
			.sr_req_out_0(connects[0][0]),
			.sr_req_out_1(connects[0][1])
		);
		// build each layer
		for (layer_num = 1; layer_num < NUM_LAYERS; layer_num = layer_num + 1) begin : layer_gen
			// create all the instances for that layer
			for (inst_num = 0; inst_num < (2**layer_num); inst_num = inst_num + 1) begin : layer_inst_gen
				AOS_SR_1_to_2 #(.SELECT_BIT_INDEX(NUM_LAYERS-layer_num-1)) aos_sr_1_to_2_inst(
					.clk(clk),
					.rst(rst),
					//.app_enable(),
					.sr_req_in(connects[layer_num-1][inst_num]),
					.sr_req_out_0(connects[layer_num][(2*inst_num)]),
					.sr_req_out_1(connects[layer_num][(2*inst_num)+1])
				);
			end // inst loop
		end // layers loop
		// cleanup code for the final layer
		for (app_num = 0; app_num < SR_NUM_APPS; app_num = app_num + 1) begin : fixup_epilogue
			assign sr_req_to_app[app_num].valid   = connects[NUM_LAYERS-1][app_num].valid;
			assign sr_req_to_app[app_num].isWrite = connects[NUM_LAYERS-1][app_num].isWrite;
			assign sr_req_to_app[app_num].data    = connects[NUM_LAYERS-1][app_num].data;
			//Mask off the routing bits to the app
			assign sr_req_to_app[app_num].addr    = {{6{1'b0}}, connects[NUM_LAYERS-1][app_num].addr[9:0]}; // bits 15:10 are the routing bits
		end
	end // check if SR_NUM_APPS == 1

endgenerate

endmodule

module AOS_Response_RouteTree#(parameter SR_NUM_APPS = 2)
(
    // User clock and reset
    input                               clk,
    input                               rst,
	input								app_enable[SR_NUM_APPS-1:0],
	// Input from apps
	input  SoftRegResp                  sr_resp_from_app[SR_NUM_APPS-1:0],
	// Output to host
	output SoftRegResp                  sr_resp_to_host
);

parameter NUM_LAYERS = (SR_NUM_APPS > 1 ? $clog2(SR_NUM_APPS) : 1);

genvar layer_num;
genvar inst_num;
genvar app_num;

// Max size is the number in the final layer
SoftRegResp connects[NUM_LAYERS-1:0][SR_NUM_APPS-1:0];

generate
	if (SR_NUM_APPS == 1) begin : only_one
		assign sr_resp_to_host = sr_resp_from_app[0];
	end else begin : more_than_one
		// prologue to wire in the inputs
		for (inst_num = 0; inst_num < (SR_NUM_APPS / 2); inst_num = inst_num + 1) begin : layer0_gen
			AOS_SR_2_to_1 aos_sr_2_to_1_inst_layer_0(
				.clk(clk),
				.rst(rst),
				.sr_resp_in_0(sr_resp_from_app[(2*inst_num)]),
				.sr_resp_in_1(sr_resp_from_app[(2*inst_num)+1]),
				.sr_resp_out(connects[0][inst_num])
			);
		end
		// build each layer
		for (layer_num = 1; layer_num < NUM_LAYERS; layer_num = layer_num + 1) begin : layer_gen
			// create all the instances for that layer
			for (inst_num = 0; inst_num < (2**(NUM_LAYERS-layer_num-1)); inst_num = inst_num + 1) begin : layer_inst_gen
			AOS_SR_2_to_1 aos_sr_2_to_1_inst(
				.clk(clk),
				.rst(rst),
				.sr_resp_in_0(connects[layer_num-1][(2*inst_num)]),
				.sr_resp_in_1(connects[layer_num-1][(2*inst_num)+1]),
				.sr_resp_out(connects[layer_num][inst_num])
			);
			end // inst loop
		end // layers loop	
		// clean up code for the final layer
		assign sr_resp_to_host = connects[NUM_LAYERS-1][0];
	end // check if SR_NUM_APPS == 1

endgenerate

endmodule

module AmorphOSSoftReg_RouteTree#(parameter SR_NUM_APPS = 2)
(
    // User clock and reset
    input                               clk,
    input                               rst,
	input								app_enable[SR_NUM_APPS-1:0],
	// Interface to Host
	input  SoftRegReq					softreg_req,
	output SoftRegResp					softreg_resp,
	// Virtualized interface each app
	output SoftRegReq					app_softreg_req[SR_NUM_APPS-1:0],
	input  SoftRegResp					app_softreg_resp[SR_NUM_APPS-1:0]	
);

	// TODO: Wire the app_enables if we plan to run less apps than the size of the route tree
	AOS_Request_RouteTree #(.SR_NUM_APPS(SR_NUM_APPS)) aos_request_routetree_inst(
		.clk(clk),
		.rst(rst),
		.app_enable(app_enable),
		.sr_req_from_host(softreg_req),
		.sr_req_to_app(app_softreg_req)		
	);

	AOS_Response_RouteTree #(.SR_NUM_APPS(SR_NUM_APPS)) aos_response_routetree_inst(
		.clk(clk),
		.rst(rst),
		.app_enable(app_enable),
		.sr_resp_from_app(app_softreg_resp),
		.sr_resp_to_host(softreg_resp)
	);

endmodule
