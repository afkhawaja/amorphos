/*

	Buffers responses from the channel arbiter to the app ports and ensures they are 
	put in the proper order

	Author: Ahmed Khawaja


*/

import ShellTypes::*;
import AMITypes::*;

module RespMerge
(
    // User clock and reset
    input                               clk,
    input                               rst,
	input								enabled,
	// Interface to app
	output AMIResponse                  mem_resp_out,
	input                               mem_resp_grant_in,
	// Interface from address translation unit
	input AMITag						ami_mem_resp_tag_in,
	output logic						ami_mem_resp_tag_grant_out,
	output logic						ami_mem_tagQ_full_out,
	// Interface from the channel arbiters
	input								ami_mem_select_valid[AMI_NUM_CHANNELS-1:0],
	input AMIResp						ami_mem_resp_in[AMI_NUM_CHANNELS-1:0],
	output								ami_mem_resp_grant_out[AMI_NUM_CHANNELS-1:0]
);

	// Response queues from the arbiters
	wire             respQ_empty[AMI_NUM_CHANNELS-1:0];
	wire             respQ_full[AMI_NUM_CHANNELS-1:0];
	logic            respQ_enq[AMI_NUM_CHANNELS-1:0];
	logic            respQ_deq[AMI_NUM_CHANNELS-1:0];
	AMIResp          respQ_in[AMI_NUM_CHANNELS-1:0];
	AMIResp          respQ_out[AMI_NUM_CHANNELS-1:0];
 
	genvar i;
	generate 
		for (i = 0; i < AMI_NUM_CHANNELS; i = i + 1) begin: buffer_queues
			// Create the queue
			if (USE_SOFT_FIFO) begin : SoftFIFO_respmergeChannelQueue
				SoftFIFO
				#(
					.WIDTH					($bits(AMIResp)),
					.LOG_DEPTH				(RESP_MERGE_CHAN_Q_DEPTH)
				)
				respmergeChannelQueue
				(
					.clock					(clk),
					.reset_n				(~rst),
					.wrreq					(respQ_enq[i]),
					.data                   (respQ_in[i]),
					.full                   (respQ_full[i]),
					.q                      (respQ_out[i]),
					.empty                  (respQ_empty[i]),
					.rdreq                  (respQ_deq[i])
				);	
				
			end else begin : FIFO_respmergeChannelQueue
				FIFO
				#(
					.WIDTH					($bits(AMIResp)),
					.LOG_DEPTH				(RESP_MERGE_CHAN_Q_DEPTH)
				)
				respmergeChannelQueue
				(
					.clock					(clk),
					.reset_n				(~rst),
					.wrreq					(respQ_enq[i]),
					.data                   (respQ_in[i]),
					.full                   (respQ_full[i]),
					.q                      (respQ_out[i]),
					.empty                  (respQ_empty[i]),
					.rdreq                  (respQ_deq[i])
				);				
			end
			// Accept completed responses from the memory system
			assign respQ_in[i] = ami_mem_resp_in[i];
			assign ami_mem_resp_grant_out[i] = !respQ_full[i] && ami_mem_resp_in[i].valid && ami_mem_select_valid[i];
			assign respQ_enq[i] = ami_mem_resp_grant_out[i];
		end
	endgenerate

	// Unified output queue
	wire             outQ_empty;
	wire             outQ_full;
	logic            outQ_enq;
	logic             outQ_deq;
	AMIResponse      outQ_in;
	AMIResponse      outQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_respmergeOutQueue
			SoftFIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(RESP_MERGE_OUT_Q_DEPTH)
			)
			respmergeOutQueue
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(outQ_enq),
				.data                   (outQ_in),
				.full                   (outQ_full),
				.q                      (outQ_out),
				.empty                  (outQ_empty),
				.rdreq                  (outQ_deq)
			);	
			
		end else begin : FIFO_respmergeOutQueue
			FIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(RESP_MERGE_OUT_Q_DEPTH)
			)
			respmergeOutQueue
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(outQ_enq),
				.data                   (outQ_in),
				.full                   (outQ_full),
				.q                      (outQ_out),
				.empty                  (outQ_empty),
				.rdreq                  (outQ_deq)
			);	
		end
	endgenerate
	
	// See if port is accepting a response
        AMIResponse disabled_mem_resp;
        assign disabled_mem_resp = '{valid: 1'b0, data: 0, size: 0};
	assign mem_resp_out = (enabled && !outQ_empty && outQ_out.valid) ? outQ_out : disabled_mem_resp;
	assign outQ_deq     = enabled && mem_resp_grant_in && !outQ_empty && outQ_out.valid;
	
	// Tag queue
	wire             tagQ_empty;
	wire             tagQ_full;
	logic            tagQ_enq;
	logic             tagQ_deq;
	AMITag           tagQ_in;
	AMITag           tagQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_memtagQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMITag)),
				.LOG_DEPTH				(RESP_MERGE_TAG_Q_DEPTH)
			)
			memtagQ
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
		end else begin : FIFO_memtagQ
			FIFO
			#(
				.WIDTH					($bits(AMITag)),
				.LOG_DEPTH				(RESP_MERGE_TAG_Q_DEPTH)
			)
			memtagQ
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
		end
	endgenerate
	
	// Accept new tag
	always_comb begin : new_tag_logic
		ami_mem_tagQ_full_out = tagQ_full;
		tagQ_in = ami_mem_resp_tag_in;
		if (ami_mem_resp_tag_in.valid && !tagQ_full) begin // allocate a new tag
			ami_mem_resp_tag_grant_out = 1'b1;
			tagQ_enq = 1'b1;
		end else begin
			ami_mem_resp_tag_grant_out = 1'b0;
			tagQ_enq = 1'b0;
		end
	end
	
	logic merge_success;
	logic[AMI_NUM_CHANNELS-1:0]  grant;
	AMIResponse outQ_in_tmp[AMI_NUM_CHANNELS-1:0];
	
	genvar channel_num;
	generate
		for (channel_num = 0; channel_num < AMI_NUM_CHANNELS; channel_num = channel_num + 1) begin : outQ_in_tmp_logic
			assign outQ_in_tmp[channel_num].valid = respQ_out[channel_num].valid;
			assign outQ_in_tmp[channel_num].data  = respQ_out[channel_num].data;
			assign outQ_in_tmp[channel_num].size  = respQ_out[channel_num].size;
			assign grant[channel_num]             = !outQ_full && !respQ_empty[channel_num] && respQ_out[channel_num].valid && !tagQ_empty && tagQ_out.valid && (respQ_out[channel_num].channel == tagQ_out.channel);
			assign respQ_deq[channel_num]         = grant[channel_num]; 
		end
	endgenerate

	// Mux in the correct request
	/*OneHotMux
	#(
		.WIDTH($bits(AMIResponse)),
		.N(AMI_NUM_CHANNELS)
	)
	channel_merge_mux
	(
		.data(outQ_in_tmp),
		.select(grant),
		.out(outQ_in)
	);*/
	localparam MUX_BITS = AMI_NUM_CHANNELS > 1 ? $clog2(AMI_NUM_CHANNELS) : 1;
	logic[MUX_BITS-1:0] mux_select;
	OneHotEncoder
	#(
		.ONE_HOTS(AMI_NUM_CHANNELS),
		.MUX_SELECTS(MUX_BITS)
	)
	one_hot_encoder
	(
		.one_hots(grant),
		.mux_select(mux_select)
	);	
	
	always_comb begin
		outQ_in = outQ_in_tmp[0];
		if (AMI_NUM_CHANNELS == 1) begin
			outQ_in = outQ_in_tmp[0];
		end else if (AMI_NUM_CHANNELS == 2) begin
			if (mux_select == 1'b1) begin
				outQ_in = outQ_in_tmp[1];
			end else begin 
				outQ_in = outQ_in_tmp[0];
			end
		end else if (AMI_NUM_CHANNELS == 4) begin
			if (mux_select == 2'b11) begin
				outQ_in = outQ_in_tmp[3];
			end else if (mux_select == 2'b10) begin 
				outQ_in = outQ_in_tmp[2];
			end else if (mux_select == 2'b01) begin
				outQ_in = outQ_in_tmp[1];
			end else begin
				outQ_in = outQ_in_tmp[0];
			end
		end else if (AMI_NUM_CHANNELS == 8) begin
			if (mux_select == 3'b111) begin
				outQ_in = outQ_in_tmp[7];
			end else if (mux_select == 3'b110) begin
				outQ_in = outQ_in_tmp[6];
			end else if (mux_select == 3'b101) begin
				outQ_in = outQ_in_tmp[5];
			end else if (mux_select == 3'b100) begin
				outQ_in = outQ_in_tmp[4];
			end else if (mux_select == 3'b011) begin
				outQ_in = outQ_in_tmp[3];
			end else if (mux_select == 3'b010) begin
				outQ_in = outQ_in_tmp[2];
			end else if (mux_select == 3'b001) begin
				outQ_in = outQ_in_tmp[1];
			end else begin // 3'b000
				outQ_in = outQ_in_tmp[0];
			end
		end
	end	
	
	assign merge_success = !tagQ_empty && tagQ_out.valid && (|grant);
	
	// Deque a tag
	assign tagQ_deq = merge_success;
	// Write into output queue
	assign outQ_enq = merge_success;

endmodule
