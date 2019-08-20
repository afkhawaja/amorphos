// testbench for the AmorphOSMem
`timescale 1 ns / 1 ns

import ShellTypes::*;
import AMITypes::*;

parameter NUM_READS     = 64'd8;

module Req_module(
input[31:0] app_num,
input[31:0] port_num,
input[63:0] num_reads,
input[63:0] start_addr,
input[63:0] addr_offset,
input[511:0] base_data,
input port_enable,
input mem_req_grant_out,
output MemReq mem_req_in
);
initial begin
	int cycles;
	cycles  = 0;
	mem_req_in = '{valid: 1'b0, isWrite: 1'b0, addr: 0, data: 0};
	#5;
	if (port_enable == 1'b0) begin
		$display("IMPORTANT - App %d Port %d  requests are DISABLED.",app_num,port_num);
	end else begin
		#20;
		for (int i = 0; i < 8; i = i + 1) begin
			mem_req_in = '{valid: 1'b1, isWrite: 1'b1, addr: i*64, data: ('hDEAD0000 + i)};
			#2 cycles = cycles + 1;
			while(mem_req_grant_out != 1'b1) begin
				#2 cycles = cycles + 1;
				$display("App %d Port %d: Write %d not accepted by memory system",app_num,port_num,i);
			end
			$display("App %d Port %d: Write %d (addr: %h, data: %h)accepted!", app_num, port_num, i , i*64, ('hDEAD0000 + i));
		end
		mem_req_in = '{valid: 1'b0, isWrite: 1'b1, addr: 0, data: 0};
		#2 cycles = cycles + 1;
		for (int j = 0; j < 8; j = j + 1) begin
			mem_req_in = '{valid: 1'b1, isWrite: 1'b0, addr: j*64, data: 0};
			#2 cycles = cycles + 1;
			while(mem_req_grant_out != 1'b1) begin
				#2 cycles = cycles + 1;
				$display("App %d Port %d: Read %d not accepted by memory system",app_num,port_num,j);
			end
			$display("App %d Port %d: Read %d (addr: %h)accepted!",app_num,port_num, j , j*64);
		end
		mem_req_in= '{valid: 1'b0, isWrite: 1'b0, addr: 0, data: 0};
		$display("IMPORTANT - App %d Port %d: All %d requests submitted. Cycles: %d",app_num,port_num,8,cycles);
		#2;
	end
end
endmodule

module Resp_module(
input[31:0] app_num,
input[31:0] port_num,
input[63:0] num_reads,
input port_enable,
output logic mem_resp_grant_in,
input MemResp mem_resp_out
);
initial begin
	int cycles;
	cycles  = 0;
	mem_resp_grant_in = 1'b0;
	#5;
	if (port_enable == 1'b0) begin
		$display("IMPORTANT - App %d Port %d  responses are DISABLED.",app_num,port_num);
	end else begin
		#20;
		for (int k = 0; k < 8; k = k + 1) begin 
			#2 cycles = cycles + 1;
			while(!mem_resp_out.valid) begin
			#2 cycles = cycles + 1;
				$display("App %d Port %d: Read Resp %d not done", app_num, port_num, k);
			end
			$display("App %d Port %d: Read Resp %d data(%h)",app_num, port_num, k, mem_resp_out.data[31:0]);
			mem_resp_grant_in = 1'b1;
		end
			#2 cycles = cycles + 1;
		mem_resp_grant_in = 1'b0;
		$display("IMPORTANT - App %d Port %d: All responses received. Cycles: %d cycles", app_num,port_num,cycles);
		#2;
	end
end
endmodule

module testAMI_NARd();

	// General signals
	reg clk;
	reg rst;

	// Simple Dram instances
	MemReq  sd_mem_req_in[AMI_NUM_CHANNELS-1:0];
	MemResp sd_mem_resp_out[AMI_NUM_CHANNELS-1:0];
	wire    sd_mem_resp_grant_in[AMI_NUM_CHANNELS-1:0];
	wire    sd_mem_req_grant_out[AMI_NUM_CHANNELS-1:0];

	genvar channel_num;
	generate
		for (channel_num = 0; channel_num < AMI_NUM_CHANNELS; channel_num = channel_num + 1) begin: sd_inst
			SimSimpleDram
			#(
				.DATA_WIDTH(512), // 64 bytes (512 bits)
				.LOG_SIZE(20),
				.LOG_Q_SIZE(4)
			)
			simpleDramChannel
			(
				.clk(clk),
				.rst(rst),
				.mem_req_in(sd_mem_req_in[channel_num]),
				.mem_req_grant_out(sd_mem_req_grant_out[channel_num]),
				.mem_resp_out(sd_mem_resp_out[channel_num]),
				.mem_resp_grant_in(sd_mem_resp_grant_in[channel_num])
			);
		end
	endgenerate
	
	// From apps to AMI
	reg     app_enable[AMI_NUM_APPS-1:0];
	reg     port_enable[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	MemReq	mem_req_in[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	logic   mem_resp_grant_in[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	
	// From AMI to apps
	wire    mem_req_grant_out[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];	
	MemResp mem_resp_out[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	
	AmorphOSMem ami_mem_system
	(
    // User clock and reset
		.clk(clk),
		.rst(rst),
		// Enable signals
		.app_enable (app_enable),
		.port_enable (port_enable),
		// SimpleDRAM interface to the apps
		// Submitting requests
		.mem_req_in(mem_req_in),
		.mem_req_grant_out(mem_req_grant_out),
		// Reading responses
		.mem_resp_out(mem_resp_out),
		.mem_resp_grant_in(mem_resp_grant_in),
		// Interface to SimpleDRAM modules per channel
		.ch2sdram_req_out(sd_mem_req_in),
		.ch2sdram_req_grant_in(sd_mem_req_grant_out),
		.ch2sdram_resp_in(sd_mem_resp_out),
		.ch2sdram_resp_grant_out(sd_mem_resp_grant_in)
	);
	

	
	genvar app_num;
	genvar port_num;
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : per_app_test
			for (port_num = 0; port_num < AMI_NUM_PORTS; port_num = port_num + 1) begin : per_port_test
				// Create test drivers
				Req_module req_module
				(
					.app_num(app_num),
					.port_num(port_num),
					.num_reads(NUM_READS),
					.start_addr(0),
					.addr_offset(0),
					.base_data('hDEADBEEF),
					.port_enable(port_enable[app_num][port_num]),
					.mem_req_grant_out(mem_req_grant_out[app_num][port_num]),
					.mem_req_in(mem_req_in[app_num][port_num])
				);
				Resp_module resp_module(
					.app_num(app_num),
					.port_num(port_num),
					.num_reads(NUM_READS),
					.port_enable(port_enable[app_num][port_num]),
					.mem_resp_grant_in(mem_resp_grant_in[app_num][port_num]),
					.mem_resp_out(mem_resp_out[app_num][port_num])
				);
			end
		end
	endgenerate
	
initial begin

	$display("Starting AMI Test\n");
	
	app_enable[0] = 1'b1;
	app_enable[1] = 1'b0;
	
	port_enable[0][0] = 1'b1;
	port_enable[0][1] = 1'b1;
	port_enable[1][0] = 1'b0;
	port_enable[1][1] = 1'b0;

	clk = 1'b0;
	rst = 1'b1;
	#2
	rst = 1'b0;

end	
	
// Clock
always #1 clk = !clk;

endmodule