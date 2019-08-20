// testbench for the block buffer
`timescale 1 ns / 1 ns

import ShellTypes::*;
import AMITypes::*;

module simulate_outbuf_slice
#(
parameter DATA_WIDTH = 64
)
(
	input clk,
	input rst,
	input[31:0] pu_id,
	input outbuf_pop,
	output logic outbuf_empty,
	output logic[DATA_WIDTH-1:0] data_from_outbuf
);

	reg[DATA_WIDTH-1:0]  current_out_data;
	
	always@(posedge clk) begin
		if (rst) begin
			current_out_data <= {pu_id,16'haaaa,16'h0000};
		end else begin
			if (outbuf_pop) begin
				$display("Popping value %h from PU %h",data_from_outbuf,pu_id);
				current_out_data <= current_out_data + 1;
			end
		end	
	end

	assign outbuf_empty     = 1'b0;
	assign data_from_outbuf = current_out_data;

endmodule

module simulate_inbuf
#(
parameter DATA_WIDTH = 64
)
(
	input clk,
	input rst,
	input[DATA_WIDTH-1:0] data_to_inbuf,
	input inbuf_push,
	output inbuf_full
);

	assign inbuf_full = 1'b0;
	
	always@(posedge clk) begin
		if (inbuf_push) begin
			$display("Pushing value %h into inbuf",data_to_inbuf);
		end
	end

endmodule

module testDNN2AMI();

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
	wire respOut_grant;

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

	
	localparam integer num_pu = 2;
	
	// Reads
	// DNN2AMI Inputs that need to be driven
	wire inbuf_full;
	reg rd_req;
	reg[9:0] rd_req_size;
	reg[31:0] rd_addr;
	
	// DNN2AMI Outputs
	wire[63:0] data_to_inbuf;
	wire       inbuf_push;
	wire       rd_ready;

	
	// Writes
	// Inputs
	wire[num_pu-1:0] outbuf_empty;
	wire[((num_pu)*64) - 1:0] data_from_outbuf;
	reg[num_pu-1:0] write_valid;
	reg             wr_req;
	reg[1:0]  wr_pu_id;
	reg[9:0]  wr_req_size;
	reg[31:0] wr_addr;
	
	// Outputs
	wire[num_pu-1:0] outbuf_pop;
	wire wr_ready;
	wire wr_done;
	
	DNN2AMI
	#
	(
		.AXI_ADDR_WIDTH(32),
		.AXI_DATA_WIDTH(64),
		.NUM_PU(num_pu)
	)
	dnn2_ami
	(
		// General signals
		.clk (clk),
		.rst (rst),

		// AMI signals
		.mem_req (reqIn),
		.mem_req_grant(reqIn_grant) ,
		.mem_resp (respOut),
		.mem_resp_grant (respOut_grant),

		// Reads
		// READ from DDR to BRAM
		.inbuf_full(inbuf_full), // can the buffer accept new data
		.data_to_inbuf(data_to_inbuf), // data to be written
		.inbuf_push(inbuf_push), // write the data

		// Memory Controller Interface - Read
		.rd_req(rd_req), // read request
		.rd_req_size(rd_req_size), // size of the read request in bytes
		.rd_addr(rd_addr),     // address of the read request
		.rd_ready(rd_ready), // able to accept a new read

		// Writes
		// WRITE from BRAM to DDR
		.outbuf_empty(outbuf_empty), // no data in the output buffer
		.data_from_outbuf(data_from_outbuf),  // data to write from, portion per PU
		.write_valid(write_valid),       // value is ready to be written back
		.outbuf_pop(outbuf_pop),   // dequeue a data item
		
		// Memory Controller Interface - Write
		.wr_req(wr_req),   // assert when submitting a wr request
		.wr_pu_id(wr_pu_id), // determine where to write, I assume ach PU has a different region to write
		.wr_req_size(wr_req_size), // size of request in bytes (I assume)
		.wr_addr(wr_addr), // address to write to, look like 32 bit addresses
		.wr_ready(wr_ready), // ready for more writes
		.wr_done(wr_done)  // no writes left to submit

	);
	
	

	initial begin
		$display("Starting DNN2AMI Test\n");
		app_enable[0] = 1'b1;
		port_enable[0][0] = 1'b1;
		port_enable[0][1] = 1'b1;

		write_valid[0] = 1'b1;
		write_valid[1] = 1'b1;		

		rd_req      = 1'b0;
		rd_req_size = 0;
		rd_addr     = 0;

		wr_req = 1'b0;
		wr_pu_id = 0;
		wr_req_size = 0;
		wr_addr = 0;
		
		clk = 1'b0;
		rst = 1'b1;
		#2
		rst = 1'b0;
		#2
		wr_req   = 1'b1;
		wr_pu_id = 1;
		wr_req_size = 4;
		wr_addr     = 0;
		#2
		wr_req   = 1'b0;
		$display("Writes should be all accepted");
		#2
		rd_req      = 1'b1;
		rd_req_size = 4;
		rd_addr     = 0;
		#2
		rd_req      = 1'b0;	
		#100
		$stop;
	end
	
	// simulate the outbuf
	genvar pu_num;
	generate
		for (pu_num = 0; pu_num < num_pu; pu_num = pu_num + 1) begin
			simulate_outbuf_slice
			#(
				.DATA_WIDTH(64)
			)
			outbuf_sim_slice
			(
				.clk(clk),
				.rst(rst),
				.pu_id(pu_num),
				.outbuf_pop(outbuf_pop[pu_num]),
				.outbuf_empty(outbuf_empty[pu_num]),
				.data_from_outbuf(data_from_outbuf[((pu_num+1)*64)-1:(pu_num*64)])
			);
		
		end
	endgenerate
	
	// Simulate the inbuf
	simulate_inbuf
	#(
		.DATA_WIDTH(64)
	)
	inbuf_sim
	(
		.clk(clk),
		.rst(rst),
		.data_to_inbuf(data_to_inbuf),
		.inbuf_push(inbuf_push),
		.inbuf_full(inbuf_full)
	);
	
// Clock
always #1 clk = !clk;

// Watchdog
initial begin
#400
$stop;
end

endmodule