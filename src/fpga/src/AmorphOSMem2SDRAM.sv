

import ShellTypes::*;
import AMITypes::*;

module AmorphOSMem2SDRAM
(
    // User clock and reset
    input                               clk,
    input                               rst,
	// Enable signals
	input								app_enable[AMI_NUM_APPS-1:0],
	input								port_enable[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	// AMI interface to the apps
	// Submitting requests
	input AMIRequest					mem_req_in[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	output 	wire						mem_req_grant_out[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	// Reading responses
	output AMIResponse                  mem_resp_out[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	input                               mem_resp_grant_in[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	// Interface to SimpleDRAM per channel
	output MemReq                   	ch2sdram_req_out[AMI_NUM_CHANNELS-1:0],
	input                               ch2sdram_req_grant_in[AMI_NUM_CHANNELS-1:0],
	input MemResp                   	ch2sdram_resp_in[AMI_NUM_CHANNELS-1:0],
	output  wire                        ch2sdram_resp_grant_out[AMI_NUM_CHANNELS-1:0]
);

	AMIRequest  ch2mem_inter_req_out[AMI_NUM_CHANNELS-1:0];
	wire        ch2mem_inter_req_grant_in[AMI_NUM_CHANNELS-1:0];
	AMIResponse ch2mem_inter_resp_in[AMI_NUM_CHANNELS-1:0];
	wire        ch2mem_inter_resp_grant_out[AMI_NUM_CHANNELS-1:0];
	/*
	wire mem_req_grant_out_tmp[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	assign mem_req_grant_out = mem_req_grant_out_tmp;
	
	AMIResponse mem_resp_out_tmp[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	assign mem_resp_out = mem_resp_out_tmp;
	*/
	AmorphOSMem
	mem_system
	(
		// User clock and reset
		.clk (clk),
		.rst (rst),
		// Enable signals
		.app_enable(app_enable),
		.port_enable(port_enable),
		// AMI interface to the apps
		// Submitting requests
		.mem_req_in(mem_req_in),
		.mem_req_grant_out(mem_req_grant_out),
		// Reading responses
		.mem_resp_out(mem_resp_out),
		.mem_resp_grant_in(mem_resp_grant_in),
		// Interface to mem interface modules per channel
		.ch2mem_inter_req_out(ch2mem_inter_req_out),
		.ch2mem_inter_req_grant_in(ch2mem_inter_req_grant_in),
		.ch2mem_inter_resp_in(ch2mem_inter_resp_in),
		.ch2mem_inter_resp_grant_out(ch2mem_inter_resp_grant_out)
	);

	/*wire ch2sdram_req_out_tmp[AMI_NUM_CHANNELS-1:0];
	wire ch2sdram_resp_grant_out_tmp[AMI_NUM_CHANNELS-1:0];
	assign ch2sdram_req_out = ch2sdram_req_out_tmp;
	assign ch2sdram_resp_grant_out = ch2sdram_resp_grant_out_tmp;
	*/
	genvar channel_num;
	generate
		for (channel_num = 0; channel_num < AMI_NUM_CHANNELS; channel_num = channel_num + 1) begin : per_channel_AMI2SimpleDRAM

			AMI2SimpleDRAM
			ami2simple_dram
			(
				// General signals
				.clk(clk),
				.rst(rst),
				// Interface to the AMI side
				.reqIn (ch2mem_inter_req_out[channel_num]),
				.reqIn_grant(ch2mem_inter_req_grant_in[channel_num]),
				.respOut(ch2mem_inter_resp_in[channel_num]),
				.respOut_grant(ch2mem_inter_resp_grant_out[channel_num]),
				// Interface to the SimpleDRAM side
				.reqOut(ch2sdram_req_out[channel_num]),
				.reqOut_grant(ch2sdram_req_grant_in[channel_num]),
				.respIn(ch2sdram_resp_in[channel_num]),
				.respIn_grant(ch2sdram_resp_grant_out[channel_num])
			);

		end
	endgenerate

endmodule