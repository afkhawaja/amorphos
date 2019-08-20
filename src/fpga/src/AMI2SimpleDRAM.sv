


import ShellTypes::*;
import AMITypes::*;

module AMI2SimpleDRAM
(
	// General signals
	input			   clk,
	input 			   rst,
	// Interface to the AMI side
	input AMIRequest   reqIn,
	output logic       reqIn_grant,
	output AMIResponse respOut,
	input 			   respOut_grant,
	// Interface to the SimpleDRAM side
	output MemReq      reqOut,
	input 			   reqOut_grant,
	input MemResp      respIn,
	output logic       respIn_grant
	
);

	// Placeholder logic

	assign reqOut.valid   = reqIn.valid;
	assign reqOut.isWrite = reqIn.isWrite;
	assign reqOut.data    = reqIn.data;
	assign reqOut.addr    = reqIn.addr;

	assign reqIn_grant    = reqOut_grant;
	
	assign respOut.valid  = respIn.valid;
	assign respOut.data   = respIn.data;
	assign respOut.size   = 64;
	
	assign respIn_grant   = respOut_grant;
	/*
	
	// Queue for incoming AMIRequests
	wire             reqInQ_empty;
	wire             reqInQ_full;
	wire             reqInQ_enq;
	wire             reqInQ_deq;
	AMIRequest       reqInQ_in;
	AMIRequest       reqInQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_reqIn_memReqQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(AMI2SDRAM_REQ_IN_Q_DEPTH)
			)
			reqIn_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(reqInQ_enq),
				.data                   (reqInQ_in),
				.full                   (reqInQ_full),
				.q                      (reqInQ_out),
				.empty                  (reqInQ_empty),
				.rdreq                  (reqInQ_deq)
			);
		end else begin : FIFO_reqIn_memReqQ
			FIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(AMI2SDRAM_REQ_IN_Q_DEPTH)
			)
			reqIn_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(reqInQ_enq),
				.data                   (reqInQ_in),
				.full                   (reqInQ_full),
				.q                      (reqInQ_out),
				.empty                  (reqInQ_empty),
				.rdreq                  (reqInQ_deq)
			);
		end
	endgenerate	
	
	assign reqInQ_in   = reqIn;
	assign reqInQ_enq  = reqIn.valid && !reqInQ_full;
	assign reqIn_grant = reqInQ_enq;

	// ResponseQ from SimpleDRAM
	// TODO: FIX THIS NAME
	wire             respInQ_empty;
	wire             respInQ_full;
	wire             respInQ_enq;
	wire             respInQ_deq;
	AMIResponse      respInQ_in;
	AMIResponse      respInQ_out;	
	
	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_respIn_memReqQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(AMI2SDRAM_RESP_IN_Q_DEPTH)
			)
			respIn_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(respInQ_enq),
				.data                   (respInQ_in),
				.full                   (respInQ_full),
				.q                      (respInQ_out),
				.empty                  (respInQ_empty),
				.rdreq                  (respInQ_deq)
			);
		end else begin : FIFO_respIn_memReqQ
			FIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(AMI2SDRAM_RESP_IN_Q_DEPTH)
			)
			respIn_memReqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(respInQ_enq),
				.data                   (respInQ_in),
				.full                   (respInQ_full),
				.q                      (respInQ_out),
				.empty                  (respInQ_empty),
				.rdreq                  (respInQ_deq)
			);
		end
	endgenerate	
	
	assign respInQ_in   = respIn;
	assign respInQ_enq  = respIn.valid && !respInQ_full;
	assign respIn_grant = respInQ_enq;
*/
endmodule 
