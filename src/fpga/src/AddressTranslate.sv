/*

	One port facing the user which connects to the RespMerge, AppLevelTranslate, 
	and a per channel ChannelMerge. This unit is responsible for determining
	which channel a translated request maps to.
	
	Author: Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;

module AddressTranslate
(
	// Enable signal
	input								enabled,
    // User clock and reset
    input                               clk,
    input                               rst,
	// Identify port of origin  and app
	input [AMI_APP_BITS-1:0]			srcApp, // refers to the physical app not by its app ID
	input [AMI_PORT_BITS-1:0]			srcPort,
	// SimpleDRAM interface
	input AMIRequest					mem_req_in,
	output								mem_req_grant_out,
	// Interface to the per App combined translation unit
	output AMIRequest					ami_mem_req_to_xlate,
	input								ami_mem_req_to_xlate_accepted,
	input  AMIRequest					ami_mem_req_xlated,
	output logic						ami_mem_req_xlated_grant,
	// Interface to queues for translated requests per channel
	output AMIReq						ami_mem_req_out[AMI_NUM_CHANNELS-1:0],
	input 								ami_mem_req_grant_in[AMI_NUM_CHANNELS-1:0],
	// Interface to the response merge units
	output AMITag						ami_mem_resp_tag_out,
	input								ami_mem_resp_tag_grant_in,
	input								ami_mem_tagQ_full_in
);

	// Queue for requests coming from the user that need to be translated
	wire             reqQ_empty;
	wire             reqQ_full;
	wire             reqQ_enq;
	wire             reqQ_deq;
	AMIRequest       reqQ_in;
	AMIRequest       reqQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_memReqQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(ADDR_XLAT_Q_DEPTH)
			)
			memReqQ
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
		end else begin : FIFO_memReqQ
			FIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(ADDR_XLAT_Q_DEPTH)
			)
			memReqQ
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
	
	// Queue for requests coming from the user that need to be translated
	wire             xlated_reqQ_empty;
	wire             xlated_reqQ_full;
	wire             xlated_reqQ_enq;
	wire             xlated_reqQ_deq;
	AMIRequest       xlated_reqQ_in;
	AMIRequest       xlated_reqQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_xlated_memReqQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(ADDR_XLATED_Q_DEPTH)
			)
			xlated_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(xlated_reqQ_enq),
				.data                   (xlated_reqQ_in),
				.full                   (xlated_reqQ_full),
				.q                      (xlated_reqQ_out),
				.empty                  (xlated_reqQ_empty),
				.rdreq                  (xlated_reqQ_deq)
			);
		end else begin : FIFO_xlated_memReqQ
			FIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(ADDR_XLATED_Q_DEPTH)
			)
			xlated_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(xlated_reqQ_enq),
				.data                   (xlated_reqQ_in),
				.full                   (xlated_reqQ_full),
				.q                      (xlated_reqQ_out),
				.empty                  (xlated_reqQ_empty),
				.rdreq                  (xlated_reqQ_deq)
			);
		end
	endgenerate
	
	// Determine if the queue should accept a request
	assign reqQ_enq = enabled && mem_req_in.valid && !reqQ_full;
	assign reqQ_in  = mem_req_in;
	assign mem_req_grant_out = reqQ_enq;
	
	// Address Translation
	// Present request to app level translation unit
	assign ami_mem_req_to_xlate.valid   = reqQ_out.valid && !reqQ_empty; // important since the queues don't reset to 0 (necessarily)
	assign ami_mem_req_to_xlate.isWrite = reqQ_out.isWrite;
	assign ami_mem_req_to_xlate.addr    = reqQ_out.addr;
	assign ami_mem_req_to_xlate.data    = reqQ_out.data;
	assign ami_mem_req_to_xlate.size    = reqQ_out.size;
	
	assign reqQ_deq = ami_mem_req_to_xlate_accepted;
	
	// Accept translated request
	assign xlated_reqQ_in  = ami_mem_req_xlated;
	assign xlated_reqQ_enq = ami_mem_req_xlated.valid && !xlated_reqQ_full;
	assign ami_mem_req_xlated_grant = xlated_reqQ_enq;
	
	// Address translation from front of queue
	logic[AMI_ADDR_WIDTH-1:0]   translated_addr;
	logic[AMI_CHANNEL_BITS-1:0] channel_select;	
	logic xlated_deq_ok;
	AMITag newTag;
	logic isValidRead;
	
	// ONLY FOR DEBUG
	assign translated_addr     = (DISABLE_INTERLEAVE ? xlated_reqQ_out.addr : {{AMI_CHANNEL_BITS{1'b0}},xlated_reqQ_out.addr[63:(AMI_CHANNEL_BITS+6)],xlated_reqQ_out.addr[5:0]}); // Conversion for channel
	//assign channel_select      = (AMI_NUM_CHANNELS == 1 ? 0 : ( (DISABLE_INTERLEAVE ? srcPort : xlated_reqQ_out.addr[AMI_CHANNEL_BITS+5:6]) ));
	
	always_comb begin
	    channel_select = {AMI_CHANNEL_BITS{1'b0}};
	    if (AMI_NUM_CHANNELS == 1) begin
		channel_select = 1'b0;
            end else if (DISABLE_INTERLEAVE == 1'b1) begin
		channel_select = srcPort;
	    end else begin
                channel_select = xlated_reqQ_out.addr[AMI_CHANNEL_BITS+5:6];
	        if (xlated_deq_ok == 1'b1) begin
		    $display("XLATE: Submitted addr: %h on channel %d", xlated_reqQ_out.addr, channel_select);
		end
	    end
	end

	logic[AMI_NUM_CHANNELS-1:0] ami_mem_req_grant_in_proxy;
	genvar i;
	generate 
		for (i = 0; i < AMI_NUM_CHANNELS; i = i + 1) begin: output_ami
			assign ami_mem_req_out[i].valid   = (AMI_NUM_CHANNELS == 1  ?  1'b1 : ((channel_select == i[AMI_CHANNEL_BITS-1:0]) ? 1'b1 : 1'b0)) && xlated_reqQ_out.valid && !xlated_reqQ_empty && (!xlated_reqQ_out.isWrite ? !ami_mem_tagQ_full_in : 1'b1);
			assign ami_mem_req_out[i].data    = xlated_reqQ_out.data;
			assign ami_mem_req_out[i].addr    = translated_addr;
			assign ami_mem_req_out[i].srcPort = srcPort;
			assign ami_mem_req_out[i].srcApp  = srcApp;
			assign ami_mem_req_out[i].channel = channel_select;
			assign ami_mem_req_out[i].isWrite = xlated_reqQ_out.isWrite;
			assign ami_mem_req_out[i].size    = xlated_reqQ_out.size;
			assign ami_mem_req_grant_in_proxy[i] = ami_mem_req_grant_in[i];
		end
	endgenerate
	
	// Determine if a request should be dequeued, which means a valid translation was done AND the request was accepted by the next stage
	// AND if it needed a tag, the tag can be allocated
	assign xlated_deq_ok = (|ami_mem_req_grant_in_proxy) && xlated_reqQ_out.valid && !xlated_reqQ_empty && (!xlated_reqQ_out.isWrite ? !ami_mem_tagQ_full_in : 1'b1);
	assign xlated_reqQ_deq = xlated_deq_ok;
	// Contents of the new tag, we know if it will be accepted or not based on ami_mem_tagQ_full_in
	assign isValidRead    = xlated_reqQ_out.valid && !xlated_reqQ_empty && !xlated_reqQ_out.isWrite && xlated_deq_ok;
	assign newTag.valid   = isValidRead;
	assign newTag.srcApp  = srcApp;
	assign newTag.srcPort = srcPort;
	assign newTag.channel = channel_select;
	assign newTag.size    = xlated_reqQ_out.size;
	assign ami_mem_resp_tag_out = newTag;

endmodule
