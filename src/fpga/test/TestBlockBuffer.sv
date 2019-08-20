// testbench for the block buffer
`timescale 1 ns / 1 ns

import ShellTypes::*;
import AMITypes::*;

module testBlockBuffer();

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
				.LOG_SIZE(10),
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
	reg         app_enable[AMI_NUM_APPS-1:0];
	reg         port_enable[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	AMIRequest	mem_req_in[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	wire        mem_resp_grant_in[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	
	// From AMI to apps
	wire        mem_req_grant_out[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];	
	AMIResponse mem_resp_out[AMI_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
	
	AmorphOSMem2SDRAM ami_mem_system
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

	// App2BB
	AMIRequest reqIn;
	wire reqIn_grant;
	AMIResponse respOut;
	reg respOut_grant;

	// Block buffer
	BlockBuffer
	block_buffer
	(
		// General signals
		.clk (clk),
		.rst (rst),
		.flush_buffer (1'b0),
		// Interface to App
		.reqIn (reqIn),
		.reqIn_grant (reqIn_grant),
		.respOut (respOut),
		.respOut_grant (respOut_grant),
		// Interface to Memory system, 2 ports enables simulatentous eviction and request of a new block
		.reqOut(mem_req_in[0]), // port 0 is the rd port, port 1 is the wr port
		.reqOut_grant(mem_req_grant_out[0]),
		.respIn(mem_resp_out[0]),
		.respIn_grant(mem_resp_grant_in[0])
	);

	initial begin
		$display("Starting BlockBuffer Test\n");
		app_enable[0] = 1'b1;
		port_enable[0][0] = 1'b1;
		port_enable[0][1] = 1'b1;
		respOut_grant = 1'b0;
		
		clk = 1'b0;
		rst = 1'b1;
		#2
		rst = 1'b0;
		// Write a block
		for (int i = 0; i < 8; i = i + 1) begin
			reqIn = '{valid: 1'b1, isWrite: 1'b1, addr: 0 + (i*8), data: ('hABBABAABDEAD0000 + i), size: 8};
			#2
			while(reqIn_grant != 1'b1) begin
				#2
				$display("Write not accepted by memory system");
			end
			$display("Write %d (addr: %h)accepted!", i , i*8);
		end
		reqIn = '{valid: 1'b0, isWrite: 1'b0, addr: 0 , data: 0, size: 0};
		// Read back the same block
		#2
		for (int i = 0; i < 8; i = i + 1) begin
			reqIn = '{valid: 1'b1, isWrite: 1'b0, addr: 0 + (i*8), data: 0, size: 8};
			#2
			while(reqIn_grant != 1'b1) begin
				#2
				$display("Read not accepted by memory system");
			end
			$display("Read %d (addr: %h)accepted!", i , i*8);
		end
		reqIn = '{valid: 1'b0, isWrite: 1'b0, addr: 0 , data: 0, size: 0};
		// Await the Read responses
		#2
		for (int i = 0; i < 8; i = i + 1) begin
			#2
			respOut_grant = 1'b0;
			while (!respOut.valid) begin
				#2
				$display("Waiting on read response!");
			end
			respOut_grant = 1'b1;
			$display("Read %d data: %h",i,respOut.data);
		end
		#2
		respOut_grant = 1'b0;
		// Write a block
		#2
		for (int i = 0; i < 8; i = i + 1) begin
			reqIn = '{valid: 1'b1, isWrite: 1'b1, addr: 64 + (i*8), data: ('hCBBABAABDEAD0000 + i), size: 8};
			#2
			while(reqIn_grant != 1'b1) begin
				#2
				$display("Write not accepted by memory system");
			end
			$display("Write %d (addr: %h)accepted!", i , 64 + (i*8));
		end
		reqIn = '{valid: 1'b0, isWrite: 1'b0, addr: 0 , data: 0, size: 0};		
		// Read back the same block
		#2
		for (int i = 0; i < 8; i = i + 1) begin
			reqIn = '{valid: 1'b1, isWrite: 1'b0, addr: 64 + (i*8), data: 0, size: 8};
			#2
			while(reqIn_grant != 1'b1) begin
				#2
				$display("Read not accepted by memory system");
			end
			$display("Read %d (addr: %h)accepted!", i , 64 + (i*8));
		end
		reqIn = '{valid: 1'b0, isWrite: 1'b0, addr: 0 , data: 0, size: 0};
		// Await the Read responses
		#2
		for (int i = 0; i < 8; i = i + 1) begin
			#2
			respOut_grant = 1'b0;
			while (!respOut.valid) begin
				#2
				$display("Waiting on read response!");
			end
			respOut_grant = 1'b1;
			$display("Read %d data: %h",i,respOut.data);
		end
		#2
		respOut_grant = 1'b0;
		// Re read the first block
		// Read back the same block
		#2
		for (int i = 0; i < 8; i = i + 1) begin
			reqIn = '{valid: 1'b1, isWrite: 1'b0, addr: 0 + (i*8), data: 0, size: 8};
			#2
			while(reqIn_grant != 1'b1) begin
				#2
				$display("Read not accepted by memory system");
			end
			$display("Read %d (addr: %h)accepted!", i , i*8);
		end
		reqIn = '{valid: 1'b0, isWrite: 1'b0, addr: 0 , data: 0, size: 0};
		// Await the Read responses
		#2
		for (int i = 0; i < 8; i = i + 1) begin
			#2
			respOut_grant = 1'b0;
			while (!respOut.valid) begin
				#2
				$display("Waiting on read response!");
			end
			respOut_grant = 1'b1;
			$display("Read %d data: %h",i,respOut.data);
		end
		#2
		respOut_grant = 1'b0;	

		$stop;
	end
	
	
// Clock
always #1 clk = !clk;

// Watchdog

initial begin
#250
$stop;
end

endmodule