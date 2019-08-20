// testbench for the FIFO
`timescale 1 ns / 1 ns

import ShellTypes::*;
import AMITypes::*;

module simpledram_test();

	reg clk;
	reg rst;

	MemReq mem_req_in;
	MemResp mem_resp_out;
	logic mem_resp_grant_in;
	wire mem_req_grant_out;

	SimSimpleDram
	#(
		.DATA_WIDTH(64),
		.LOG_SIZE(10),
		.LOG_Q_SIZE(4)
	)
	testSimpleDram
	(
		.clk(clk),
		.rst(rst),
		.mem_req_in(mem_req_in),
		.mem_req_grant_out(mem_req_grant_out),
		.mem_resp_out(mem_resp_out),
		.mem_resp_grant_in(mem_resp_grant_in)
	);
	
	// Clock
always #1 clk = !clk;

	// Writes
initial begin
	$display("Starting up here!\n");
	mem_req_in.valid   = 1'b0; 
	mem_req_in.isWrite = 1'b1;
	mem_req_in.addr    = 0;
	mem_req_in.data    = 0;
	clk = 1'b0;
	rst = 1'b1;
	#2
	rst = 1'b0;
	for (int i = 0; i < 4; i = i + 1) begin
		#2
		mem_req_in.valid   = 1'b1; 
		mem_req_in.isWrite = 1'b1;
		mem_req_in.addr    = i;
		mem_req_in.data    = 1+i+i;
		while (!mem_req_grant_out) begin
			#2
			$display("Memory write NOT accepted");
		end
		$display("Memory write %d, Value: %d accepted by SimpleDram", i, mem_req_in.data);
	end
	#2
	mem_req_in.valid = 1'b0;
	for (int j = 0; j < 4; j = j + 1) begin
		mem_req_in.valid = 1'b1;
		mem_req_in.isWrite = 1'b0;
		mem_req_in.addr    = j;
		mem_req_in.data    = j+j;
		#2
		while (!mem_req_grant_out) begin
			#2
			$display("Memory read NOT accepted");
		end
		$display("Memory read %d accepted by SimpleDram", j);
	end
end	
	
	// Reads
initial begin
	mem_resp_grant_in = 1'b0;
	#100
	for (int i = 0; i < 4; i = i + 1) begin
		#2
		while (!mem_resp_out.valid) begin
			#2
			$display("Read Not Ready!");
		end
		mem_resp_grant_in = 1'b1;
		$display("Read %d, Value: %d",i, mem_resp_out.data);
	end
	$stop;
end	


endmodule 