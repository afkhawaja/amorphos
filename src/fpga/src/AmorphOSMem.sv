/*
	
	Top level module connecting apps to the memory system
	Fully parametrized, although the sub components might not
	support all configuration values

	Author: Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;

module AmorphOSMem
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
	output								mem_req_grant_out[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	// Reading responses
	output AMIResponse                  mem_resp_out[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	input                               mem_resp_grant_in[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0],
	// Interface to mem interface modules per channel
	output AMIRequest                   ch2mem_inter_req_out[AMI_NUM_CHANNELS-1:0],
	input                               ch2mem_inter_req_grant_in[AMI_NUM_CHANNELS-1:0],
	input AMIResponse                   ch2mem_inter_resp_in[AMI_NUM_CHANNELS-1:0],
	output                              ch2mem_inter_resp_grant_out[AMI_NUM_CHANNELS-1:0]
);

	// Enable signals
	wire   app_port_enable[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];

	// Wires for from/to translation unit
	AMIReq xlate2chmerge_req[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0][AMI_NUM_CHANNELS-1:0];
	wire   xlate2chmerge_grant[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0][AMI_NUM_CHANNELS-1:0];
	AMITag xlate2respmerge_tag[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	wire   xlate2respmerge_tag_grant[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	wire   xlate2respmerge_taqQ_full[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	AMIRequest xlate2appxlate_to_xlate[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	wire   xlate2appxlate_reqAccepted[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	AMIRequest xlate2appxlate_xlated[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	wire   xlate2appxlate_xlated_grant[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];

	// Translation unit per app per port (num_apps x num_ports)
	genvar app_num;
	genvar port_num;
	genvar channel_num;
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : per_app_xlate_unit
			for (port_num = 0; port_num < AMI_NUM_PORTS; port_num = port_num + 1) begin : per_port_xlate_unit
				assign app_port_enable[app_num][port_num] = app_enable[app_num] && port_enable[app_num][port_num]; 
				AddressTranslate
				addrXlate(
					.enabled	(app_port_enable[app_num][port_num]),
					.clk		(clk),
					.rst		(rst),
					.srcApp     (app_num[AMI_APP_BITS-1:0]),
					.srcPort	(port_num[AMI_PORT_BITS-1:0]),
					.mem_req_in                    (mem_req_in[app_num][port_num]), // app facing
					.mem_req_grant_out             (mem_req_grant_out[app_num][port_num]), // app facing
					.ami_mem_req_to_xlate          (xlate2appxlate_to_xlate[app_num][port_num]),
					.ami_mem_req_to_xlate_accepted (xlate2appxlate_reqAccepted[app_num][port_num]),
					.ami_mem_req_xlated	           (xlate2appxlate_xlated[app_num][port_num]),
					.ami_mem_req_xlated_grant      (xlate2appxlate_xlated_grant[app_num][port_num]),
					.ami_mem_req_out               (xlate2chmerge_req[app_num][port_num]),
					.ami_mem_req_grant_in          (xlate2chmerge_grant[app_num][port_num]),
					.ami_mem_resp_tag_out          (xlate2respmerge_tag[app_num][port_num]),
					.ami_mem_resp_tag_grant_in     (xlate2respmerge_tag_grant[app_num][port_num]),
					.ami_mem_tagQ_full_in          (xlate2respmerge_taqQ_full[app_num][port_num])
				);
			end
		end
	endgenerate
	
	// App level combined translation unit per App connected to each per app/per port AddressTranslate unit	
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : applevel_xlate_unit
			AppLevelTranslate
			appLevelXlate
			(
				.enabled	  (app_enable[app_num]),
				.app_num	  (app_num[AMI_APP_BITS-1:0]),
				.clk 		  (clk),
				.rst 		  (rst),
				.inReq 		  (xlate2appxlate_to_xlate[app_num]),
				.reqAccepted  (xlate2appxlate_reqAccepted[app_num]),
				.outReq 	  (xlate2appxlate_xlated[app_num]),
				.outReq_grant (xlate2appxlate_xlated_grant[app_num])
			);
		end
	endgenerate

	// Wires to/from channel merge
	AMIReq chmerge2charb_ami_req[AMI_NUM_APPS-1:0][AMI_NUM_CHANNELS-1:0];
	wire   chmerge2charb_ami_grant[AMI_NUM_APPS-1:0][AMI_NUM_CHANNELS-1:0];
	AMIReq xlate2chmerge_req_tmp[AMI_NUM_APPS-1:0][AMI_NUM_CHANNELS-1:0][AMI_NUM_PORTS-1:0];
	wire   xlate2chmerge_grant_tmp[AMI_NUM_APPS-1:0][AMI_NUM_CHANNELS-1:0][AMI_NUM_PORTS-1:0];
	
	// Channel merge per channel per app (num_channels x num_apps)
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : channel_merge_per_app
			for (channel_num = 0; channel_num < AMI_NUM_CHANNELS; channel_num = channel_num + 1) begin : channel_merge_per_channel
				ChannelMerge
				channelMerge(
					.clk (clk),
					.rst (rst),
					.ami_mem_req_in        (xlate2chmerge_req_tmp[app_num][channel_num]),
					.ami_mem_req_grant_out (xlate2chmerge_grant_tmp[app_num][channel_num]),
					.ami_mem_req_out       (chmerge2charb_ami_req[app_num][channel_num]),
					.ami_mem_req_grant_in  (chmerge2charb_ami_grant[app_num][channel_num])
				);
				for (port_num = 0; port_num < AMI_NUM_PORTS; port_num = port_num + 1) begin : channel_merge_per_port
					assign xlate2chmerge_req_tmp[app_num][channel_num][port_num]   = xlate2chmerge_req[app_num][port_num][channel_num];
					//assign xlate2chmerge_grant_tmp[app_num][channel_num][port_num] = xlate2chmerge_grant[app_num][port_num][channel_num];
					assign xlate2chmerge_grant[app_num][port_num][channel_num] = xlate2chmerge_grant_tmp[app_num][channel_num][port_num];
				end
			end
		end
	endgenerate
	
	// Wires to/from channel arbiter
	AMIReq  chmerge2charb_ami_req_tmp[AMI_NUM_CHANNELS-1:0][AMI_NUM_APPS-1:0];
	wire    chmerge2charb_ami_grant_tmp[AMI_NUM_CHANNELS-1:0][AMI_NUM_APPS-1:0];
	wire    charb2respmerge_select_valid[AMI_NUM_CHANNELS-1:0][AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	AMIResp charb2respmerge_resp[AMI_NUM_CHANNELS-1:0];
	wire    charb2respmerge_grant[AMI_NUM_CHANNELS-1:0][AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	

	// Channel arbiter per memory channel
	generate
		for (channel_num = 0; channel_num < AMI_NUM_CHANNELS; channel_num = channel_num + 1) begin : arbiter_per_channel
			ChannelArbiter
			channelArbiter(
				.clk  (clk),
				.rst  (rst),
				// Interface from channel merge
				.ami_mem_req_in       (chmerge2charb_ami_req_tmp[channel_num]),
				.ami_mem_req_grant_out(chmerge2charb_ami_grant_tmp[channel_num]),
				// Interface to AMI2SimpleDRAM
				.mem_req_out          (ch2mem_inter_req_out[channel_num]),
				.mem_req_grant_in     (ch2mem_inter_req_grant_in[channel_num]),
				.mem_resp_sd          (ch2mem_inter_resp_in[channel_num]),
				.mem_resp_grant_sd    (ch2mem_inter_resp_grant_out[channel_num]),
				// Interface to RespBuffer
				.mem_resp_select_valid (charb2respmerge_select_valid[channel_num]),
				.mem_resp_sys          (charb2respmerge_resp[channel_num]),
				.mem_resp_grant_sys    (charb2respmerge_grant[channel_num])
			);
			for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : arbiter_per_app
				assign chmerge2charb_ami_req_tmp[channel_num][app_num] = chmerge2charb_ami_req[app_num][channel_num];
				assign chmerge2charb_ami_grant[app_num][channel_num]   = chmerge2charb_ami_grant_tmp[channel_num][app_num];				
			end
		end
	endgenerate
	
	// Wires to/from respmerge
	wire    charb2respmerge_select_valid_tmp[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0][AMI_NUM_CHANNELS-1:0];
	AMIResp charb2respmerge_resp_tmp[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0][AMI_NUM_CHANNELS-1:0];
	wire    charb2respmerge_grant_tmp[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0][AMI_NUM_CHANNELS-1:0];
	
	// Response merge unit per port per app (num_apps x num_ports)
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : per_app_respmerge
			for (port_num = 0; port_num < AMI_NUM_PORTS; port_num = port_num + 1) begin : per_port_respmerge
				RespMerge
				respMerge(
					.clk     (clk),
					.rst     (rst),
					.enabled (app_port_enable[app_num][port_num]),
					// Interface to app
					.mem_resp_out               (mem_resp_out[app_num][port_num]),
					.mem_resp_grant_in          (mem_resp_grant_in[app_num][port_num]),
					// Interface from address translation unit
					.ami_mem_resp_tag_in        (xlate2respmerge_tag[app_num][port_num]),
					.ami_mem_resp_tag_grant_out (xlate2respmerge_tag_grant[app_num][port_num]),
					.ami_mem_tagQ_full_out      (xlate2respmerge_taqQ_full[app_num][port_num]),
					// Interface from the channel arbiters
					.ami_mem_select_valid       (charb2respmerge_select_valid_tmp[app_num][port_num]),
					.ami_mem_resp_in            (charb2respmerge_resp_tmp[app_num][port_num]),
					.ami_mem_resp_grant_out     (charb2respmerge_grant_tmp[app_num][port_num])
				);
				for (channel_num = 0; channel_num < AMI_NUM_CHANNELS; channel_num = channel_num + 1) begin : per_channel_respmerge
					assign charb2respmerge_resp_tmp[app_num][port_num][channel_num]          = charb2respmerge_resp[channel_num];
					assign charb2respmerge_select_valid_tmp[app_num][port_num][channel_num]  = charb2respmerge_select_valid[channel_num][app_num][port_num];
					//assign charb2respmerge_grant_tmp[app_num][port_num][channel_num]         = charb2respmerge_grant[channel_num][app_num][port_num];
					assign charb2respmerge_grant[channel_num][app_num][port_num] = charb2respmerge_grant_tmp[app_num][port_num][channel_num];
				end
			end
		end
	endgenerate
	
endmodule
