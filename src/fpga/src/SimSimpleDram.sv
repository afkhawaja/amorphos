
import ShellTypes::*;
import AMITypes::*;

module SimSimpleDram
(
    // User clock and reset
    input                               clk,
    input                               rst,
	// Simplified Memory Interface
	input MemReq                        mem_req_in,
	output                              mem_req_grant_out,
	output MemResp                      mem_resp_out,
	input                               mem_resp_grant_in
);

parameter DATA_WIDTH = 64;
parameter LOG_SIZE   = 10;
parameter LOG_Q_SIZE = 5;

logic[DATA_WIDTH-1:0] memory[(1 << LOG_SIZE)-1:0];

	// Request queue

	logic            reqQ_empty;
	logic            reqQ_full;
	logic            reqQ_enq;
	logic            reqQ_deq;
	MemReq           reqQ_in;
	MemReq           reqQ_out;

    FIFO
	#(
		.WIDTH					($bits(MemReq)),
		.LOG_DEPTH				(LOG_Q_SIZE)
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

// Request path
logic mem_req_grant_out_tmp;
assign mem_req_grant_out = mem_req_grant_out_tmp;

always_comb begin
	reqQ_in = mem_req_in;
	if (mem_req_in.valid && !reqQ_full) begin
		$display("SimDRAM: Accepting memory request!");
		reqQ_enq = 1'b1;
		mem_req_grant_out_tmp = 1'b1;
	end else begin
		//$display("SimDRAM: NO REQUEST TO ACCEPT");
		reqQ_enq = 1'b0;
		mem_req_grant_out_tmp = 1'b0;
	end
end

logic[DATA_WIDTH-1:0] new_write_data, old_write_data;
logic[LOG_SIZE-1:0]   new_write_addr;
logic valid_wr;
// Response path
always_comb begin
	valid_wr = 1'b0;
	new_write_data = 0;
	new_write_addr = reqQ_out.addr[LOG_SIZE-1:0] & 16'hFFFF;
	old_write_data = memory[(reqQ_out.addr[LOG_SIZE-1:0]) & 16'hFFFF];
	mem_resp_out.valid = !reqQ_empty && reqQ_out.valid && !reqQ_out.isWrite;
	mem_resp_out.data  = memory[(reqQ_out.addr[LOG_SIZE-1:0] & 16'hFFFF)];
	if (!reqQ_empty && reqQ_out.valid) begin
		if (reqQ_out.isWrite) begin
			$display("SimDRAM: Write to address: ", reqQ_out.addr);
			valid_wr = 1'b1;
			reqQ_deq = 1'b1;
			new_write_data = reqQ_out.data;
		end else if (mem_resp_grant_in) begin // its a read
			$display("SimDRAM: Read to address: ", reqQ_out.addr);
			reqQ_deq = 1'b1;
		end else begin
			//$display("SimDRAM: No Traffic 1");
			reqQ_deq = 1'b0;
		end
	end else begin
		//$display("SimDRAM: No Traffic 2");
		reqQ_deq = 1'b0;
	end
end

always @(posedge clk) begin
	if (valid_wr) begin
		//$display("SimDRAM: Writing DATA");
		memory[new_write_addr] <= new_write_data;
	end else begin
		//$display("SimDRAM: No data to write");
		memory[new_write_addr] <= old_write_data;
	end
end

endmodule