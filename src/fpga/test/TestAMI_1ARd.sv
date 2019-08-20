// testbench for the AmorphOSMem
`timescale 1 ns / 1 ns

import ShellTypes::*;
import AMITypes::*;

module testAMI_1ARd();

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
	reg     mem_resp_grant_in[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	
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

// Watchdog

initial begin
#250
$stop;
end
	
// App 0 Port 0 Requests

initial begin
	$display("Starting AMI Test\n");
	app_enable[0] = 1'b1;
	
	port_enable[0][0] = 1'b1;
	mem_req_in[0][0] = '{valid: 1'b0, isWrite: 1'b0, addr: 0, data: 0};
	mem_resp_grant_in[0][0] = 1'b0;

	
	clk = 1'b0;
	rst = 1'b1;
	#2
	rst = 1'b0;
	for (int i = 0; i < 8; i = i + 1) begin
		mem_req_in[0][0] = '{valid: 1'b1, isWrite: 1'b1, addr: i*64, data: ('hDEAD0000 + i)};
		#2
		while(mem_req_grant_out[0][0] != 1'b1) begin
			#2
			$display("App 0 Port 0: Write not accepted by memory system");
		end
		$display("App 0 Port 0: Write %d (addr: %h, data: %h)accepted!", i , i*64, ('hDEAD0000 + i));
	end
	mem_req_in[0][0] = '{valid: 1'b0, isWrite: 1'b1, addr: 0, data: 0};
	#2
	for (int j = 0; j < 8; j = j + 1) begin
		mem_req_in[0][0] = '{valid: 1'b1, isWrite: 1'b0, addr: j*64, data: 0};
		#2
		while(mem_req_grant_out[0][0] != 1'b1) begin
			#2
			$display("App 0 Port 0: Read not accepted by memory system");
		end
		$display("App 0 Port 0: Read %d (addr: %h)accepted!", j , j*64);
	end
	mem_req_in[0][0] = '{valid: 1'b0, isWrite: 1'b0, addr: 0, data: 0};
	#2;
end

// App 0 Port 0 Responses

initial begin
	#20
	for (int k = 0; k < 8; k = k + 1) begin 
		#2
		while(!mem_resp_out[0][0].valid) begin
			#2
			$display("App 0 Port 0: Read %d not done", k);
		end
		$display("App 0 Port 0: Read %d data(%h)", k, mem_resp_out[0][0].data[31:0]);
		mem_resp_grant_in[0][0] = 1'b1;
	end
	#2
	mem_resp_grant_in[0][0] = 1'b0;
end

// App 0 Port 1

initial begin
	port_enable[0][1] = 1'b1;
	mem_req_in[0][1] = '{valid: 1'b0, isWrite: 1'b0, addr: 0, data: 0};
	mem_resp_grant_in[0][1] = 1'b0;
	#2
	for (int i = 0; i < 8; i = i + 1) begin
		mem_req_in[0][1] = '{valid: 1'b1, isWrite: 1'b1, addr: 4096+(2*i*64), data: ('hBEEF0000 + i)};
		#2
		while(mem_req_grant_out[0][1] != 1'b1) begin
			#2
			$display("App 0 Port 1: Write not accepted by memory system");
		end
		$display("App 0 Port 1: Write %d (addr: %h, data: %h)accepted!", i , 4096+(2*i*64), ('hBEEF0000 + i));
	end
	mem_req_in[0][1] = '{valid: 1'b0, isWrite: 1'b1, addr: 0, data: 0};
	#2
	for (int j = 0; j < 8; j = j + 1) begin
		mem_req_in[0][1] = '{valid: 1'b1, isWrite: 1'b0, addr: 4096+(2*j*64), data: 0};
		#2
		while(mem_req_grant_out[0][1] != 1'b1) begin
			#2
			$display("App 0 Port 1: Read not accepted by memory system");
		end
		$display("App 0 Port 1: Read %d (addr: %h)accepted!", j , 4096+(2*j*64));
	end
	mem_req_in[0][1] = '{valid: 1'b0, isWrite: 1'b0, addr: 0, data: 0};
	#2;
	
end

// App 0 Port 1 Responses

initial begin
	#20
	for (int k = 0; k < 8; k = k + 1) begin 
		#2
		while(!mem_resp_out[0][1].valid) begin
			#2
			$display("App 0 Port 1: Read %d not done", k);
		end
		$display("App 0 Port 1: Read %d data(%h)", k, mem_resp_out[0][1].data[31:0]);
		mem_resp_grant_in[0][1] = 1'b1;
	end
	#2
	mem_resp_grant_in[0][1] = 1'b0;
end


// App 1 Port 0
	
initial begin
	app_enable[1] = 1'b0;
	port_enable[1][0] = 1'b0;
	mem_req_in[1][0] = '{valid: 1'b0, isWrite: 1'b0, addr: 0, data: 0};
	mem_resp_grant_in[1][0] = 1'b0;
	/*
	#2
	for (int i = 0; i < 8; i = i + 1) begin
		mem_req_in[1][0] = '{valid: 1'b1, isWrite: 1'b1, addr: (2048 + (2*i*64)), data: ('hBEEF0000 + i)};
		#2
		while(mem_req_grant_out[1][0] != 1'b1) begin
			#2
			$display("App 1 Port 0: Write not accepted by memory system");
		end
		$display("App 1 Port 0: Write %d (addr: %h)accepted!", i , (2048 + (2*i*64)));
	end
	mem_req_in[1][0] = '{valid: 1'b0, isWrite: 1'b1, addr: 0, data: 0};
	*/
end

// App 1 Port 1
	
initial begin
	port_enable[1][1] = 1'b0;
	mem_req_in[1][1] = '{valid: 1'b0, isWrite: 1'b0, addr: 0, data: 0};
	mem_resp_grant_in[1][1] = 1'b0;
end
	
// Clock
always #1 clk = !clk;

endmodule