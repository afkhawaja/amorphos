/*

	Arbitrates which requests to accept and send down the pipeline
	
	Author: Ahmed Khawaja


*/

import ShellTypes::*;
import AMITypes::*;

module ChannelArbiter
(
    // User clock and reset
    input                               clk,
    input                               rst,
	// Interface from each application, all requests map to the same channel
	input AMIReq						ami_mem_req_in[AMI_NUM_APPS-1:0],
	output logic						ami_mem_req_grant_out[AMI_NUM_APPS-1:0],
	// Interface to AMI2SimpleDRAM
	output AMIRequest					mem_req_out,
	input								mem_req_grant_in,
	input AMIResponse                   mem_resp_sd,
	output                              mem_resp_grant_sd,
	// Interface to RespBuffer
	output								mem_resp_select_valid[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	output AMIResp                      mem_resp_sys,
	input								mem_resp_grant_sys[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0]
);

	// Queue of requests that need to be submitted, already arbitrated
	wire             reqQ_empty;
	wire             reqQ_full;
	logic            reqQ_enq;
	wire             reqQ_deq;
	AMIReq           reqQ_in;
	AMIReq           reqQ_out;

	// Tag queue of submitted read requests to know where to direct them to
	wire             tagQ_empty;
	wire             tagQ_full;
	logic            tagQ_enq;
	wire             tagQ_deq;
	AMITag           tagQ_in;
	AMITag           tagQ_out;
	
	// Response queue
	wire             respQ_empty;
	wire             respQ_full;
	wire             respQ_enq;
	wire             respQ_deq;
	AMIResponse      respQ_in;
	AMIResponse      respQ_out;
    
	// Create the FIFOs
	
	generate
		if (1'b1) begin : SoftFIFOs
			SoftFIFO
			#(
				.WIDTH					($bits(AMIReq)),
				//.LOG_DEPTH				(CHAN_ARB_REQ_Q_DEPTH)
				.LOG_DEPTH				(2)
			)
			chanArbReqQ
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

			SoftFIFO
			#(
				.WIDTH					($bits(AMITag)),
				.LOG_DEPTH				(2)
			)
			respTagQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(tagQ_enq),
				.data                   (tagQ_in),
				.full                   (tagQ_full),
				.q                      (tagQ_out),
				.empty                  (tagQ_empty),
				.rdreq                  (tagQ_deq)
			);

			SoftFIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(2)
			)
			memReadRespQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(respQ_enq),
				.data                   (respQ_in),
				.full                   (respQ_full),
				.q                      (respQ_out),
				.empty                  (respQ_empty),
				.rdreq                  (respQ_deq)
			);	
		end else begin : FIFOs
			FIFO
			#(
				.WIDTH					($bits(AMIReq)),
				.LOG_DEPTH				(CHAN_ARB_REQ_Q_DEPTH)
			)
			chanArbReqQ
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


			FIFO
			#(
				.WIDTH					($bits(AMITag)),
				.LOG_DEPTH				(CHAN_ARB_TAG_Q_DEPTH)
			)
			respTagQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(tagQ_enq),
				.data                   (tagQ_in),
				.full                   (tagQ_full),
				.q                      (tagQ_out),
				.empty                  (tagQ_empty),
				.rdreq                  (tagQ_deq)
			);

			FIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(CHAN_ARB_RESP_Q_DEPTH)
			)
			memReadRespQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(respQ_enq),
				.data                   (respQ_in),
				.full                   (respQ_full),
				.q                      (respQ_out),
				.empty                  (respQ_empty),
				.rdreq                  (respQ_deq)
			);	
		end
	endgenerate
	
	// Send out requests to SimpleDRAM
	wire req2sd_valid;
	assign req2sd_valid = reqQ_out.valid && !reqQ_empty;
	assign mem_req_out  = '{valid: req2sd_valid, isWrite: reqQ_out.isWrite, addr: reqQ_out.addr, data: reqQ_out.data, size : reqQ_out.size };
	assign reqQ_deq     = reqQ_out.valid && !reqQ_empty && mem_req_grant_in;
	
	// Accept responses from SimpleDRAM
	assign respQ_in  = mem_resp_sd;
	assign respQ_enq = mem_resp_sd.valid && !respQ_full;
	assign mem_resp_grant_sd = respQ_enq;
	
	logic[AMI_NUM_APPS-1:0] req;
	wire[AMI_NUM_APPS-1:0]  grant;
	
	RRWCArbiter 
	#(
		.N(AMI_NUM_APPS)
	)
	ami_req__arbiter
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req(req),
		// Grant vector
		.grant(grant)
	);

	genvar app_num;
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : arb_in_logic
			assign req[app_num] = ami_mem_req_in[app_num].valid && !reqQ_full && (ami_mem_req_in[app_num].isWrite ? 1'b1 : !tagQ_full);
			assign ami_mem_req_grant_out[app_num] = grant[app_num];
		end
	endgenerate
	
	// Mux in the correct request
	/*OneHotMux
	#(
		.WIDTH($bits(AMIReq)),
		.N(AMI_NUM_APPS)
	)
	req_select_mux
	(
		.data(ami_mem_req_in),
		.select(grant),
		.out(reqQ_in)
	);*/
	localparam MUX_BITS1 = AMI_NUM_APPS > 1 ? $clog2(AMI_NUM_APPS) : 1;
	logic[MUX_BITS1-1:0] mux_select1;
	OneHotEncoder
	#(
		.ONE_HOTS(AMI_NUM_APPS),
		.MUX_SELECTS(MUX_BITS1)
	)
	one_hot_encoder1
	(
		.one_hots(grant),
		.mux_select(mux_select1)
	);

	always_comb begin
		reqQ_in = ami_mem_req_in[0];
		if (AMI_NUM_APPS == 1) begin
			reqQ_in = ami_mem_req_in[0];
		end else if (AMI_NUM_APPS == 2) begin
			if (mux_select1 == 1'b1) begin
				reqQ_in = ami_mem_req_in[1];
			end else begin 
				reqQ_in = ami_mem_req_in[0];
			end
		end else if (AMI_NUM_APPS == 4) begin
			if (mux_select1 == 2'b11) begin
				reqQ_in = ami_mem_req_in[3];
			end else if (mux_select1 == 2'b10) begin 
				reqQ_in = ami_mem_req_in[2];
			end else if (mux_select1 == 2'b01) begin
				reqQ_in = ami_mem_req_in[1];
			end else begin
				reqQ_in = ami_mem_req_in[0];
			end
		end else if (AMI_NUM_APPS == 8) begin
			if (mux_select1 == 3'b111) begin
				reqQ_in = ami_mem_req_in[7];
			end else if (mux_select1 == 3'b110) begin
				reqQ_in = ami_mem_req_in[6];
			end else if (mux_select1 == 3'b101) begin
				reqQ_in = ami_mem_req_in[5];
			end else if (mux_select1 == 3'b100) begin
				reqQ_in = ami_mem_req_in[4];
			end else if (mux_select1 == 3'b011) begin
				reqQ_in = ami_mem_req_in[3];
			end else if (mux_select1 == 3'b010) begin
				reqQ_in = ami_mem_req_in[2];
			end else if (mux_select1 == 3'b001) begin
				reqQ_in = ami_mem_req_in[1];
			end else begin // 3'b000
				reqQ_in = ami_mem_req_in[0];
			end
		end
	end

	// If anyone receives a grant, then there is a request to enqueue
	assign reqQ_enq = (|grant);
	
	// Group up potential new tags
	AMITag tmpTag[AMI_NUM_APPS-1:0];
	
	// Generate the tmp tags
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : tmp_tag_logic
			assign tmpTag[app_num].valid   = grant[app_num] && (ami_mem_req_in[app_num].isWrite ? 1'b0 : !tagQ_full);
			assign tmpTag[app_num].srcPort = ami_mem_req_in[app_num].srcPort;
			assign tmpTag[app_num].srcApp  = ami_mem_req_in[app_num].srcApp;
			assign tmpTag[app_num].channel = ami_mem_req_in[app_num].channel;
			assign tmpTag[app_num].size    = ami_mem_req_in[app_num].size;
		end
	endgenerate
	
	// Mux in the correct new tag
	/*OneHotMux
	#(
		.WIDTH($bits(AMITag)),
		.N(AMI_NUM_APPS)
	)
	new_tag_select_mux
	(
		.data(tmpTag),
		.select(grant),
		.out(tagQ_in)
	);*/
	localparam MUX_BITS2 = AMI_NUM_APPS > 1 ? $clog2(AMI_NUM_APPS) : 1;
	logic[MUX_BITS2-1:0] mux_select2;
	OneHotEncoder
	#(
		.ONE_HOTS(AMI_NUM_APPS),
		.MUX_SELECTS(MUX_BITS2)
	)
	one_hot_encoder2
	(
		.one_hots(grant),
		.mux_select(mux_select2)
	);

	always_comb begin
		tagQ_in = tmpTag[0];
		if (AMI_NUM_APPS == 1) begin
			tagQ_in = tmpTag[0];
		end else if (AMI_NUM_APPS == 2) begin
			if (mux_select2 == 1'b1) begin
				tagQ_in = tmpTag[1];
			end else begin 
				tagQ_in = tmpTag[0];
			end
		end else if (AMI_NUM_APPS == 4) begin
			if (mux_select2 == 2'b11) begin
				tagQ_in = tmpTag[3];
			end else if (mux_select2 == 2'b10) begin 
				tagQ_in = tmpTag[2];
			end else if (mux_select2 == 2'b01) begin
				tagQ_in = tmpTag[1];
			end else begin
				tagQ_in = tmpTag[0];
			end
		end else if (AMI_NUM_APPS == 8) begin
			if (mux_select2 == 3'b111) begin
				tagQ_in = tmpTag[7];
			end else if (mux_select2 == 3'b110) begin
				tagQ_in = tmpTag[6];
			end else if (mux_select2 == 3'b101) begin
				tagQ_in = tmpTag[5];
			end else if (mux_select2 == 3'b100) begin
				tagQ_in = tmpTag[4];
			end else if (mux_select2 == 3'b011) begin
				tagQ_in = tmpTag[3];
			end else if (mux_select2 == 3'b010) begin
				tagQ_in = tmpTag[2];
			end else if (mux_select2 == 3'b001) begin
				tagQ_in = tmpTag[1];
			end else begin // 3'b000
				tagQ_in = tmpTag[0];
			end
		end
	end

	// If the request granted is a write, allocate a new tag
	assign tagQ_enq = (|grant) && tagQ_in.valid;

	// Route completed read requests to the correct application and port
	wire routable;
	wire acceptable;
	wire deq_tag_resp;
	wire[AMI_APP_BITS-1:0]  dst_app;
	wire[AMI_PORT_BITS-1:0] dst_port;

	assign dst_app  = tagQ_out.srcApp;
	assign dst_port = tagQ_out.srcPort;
	assign routable = (!tagQ_empty && !respQ_empty) && tagQ_out.valid && respQ_out.valid; // valid request and tag ready

	assign mem_resp_sys.valid   = routable;
	assign mem_resp_sys.data    = respQ_out.data;
	assign mem_resp_sys.channel = tagQ_out.channel;
	assign mem_resp_sys.srcPort = tagQ_out.srcPort;
	assign mem_resp_sys.srcApp  = tagQ_out.srcApp;
	assign mem_resp_sys.size    = tagQ_out.size;
				
	genvar port_num;
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : routing_logic_app_gen
			for (port_num = 0; port_num < AMI_NUM_PORTS; port_num = port_num + 1) begin : routing_logc_port_gen
				assign mem_resp_select_valid[app_num][port_num] = (dst_app == app_num[AMI_APP_BITS-1:0]) && (dst_port == port_num[AMI_PORT_BITS-1:0]);
			end
		end
	endgenerate

	// Deque the response and the tag
	assign acceptable   = mem_resp_grant_sys[dst_app][dst_port];
	assign deq_tag_resp = routable && acceptable;
	assign respQ_deq    = deq_tag_resp;
	assign tagQ_deq     = deq_tag_resp;
	
endmodule