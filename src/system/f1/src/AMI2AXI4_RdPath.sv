/*

Handles AMI Read Requests to AXI4

*/

import AMITypes::*;
import AOSF1Types::*;

module AMI2AXI4_RdPath(

    // General Signals
    input               clk,
    input               rst,
	input[3:0]          channel_id,
	input[63:0]         cycle_cntr,
	input               ddr_is_ready,

    // Read Address Channel (ar = address read)
    // AMI is master (initiator)
    output logic[15:0]  cl_sh_ddr_arid,    // read address id for the read address group
    output logic[63:0]  cl_sh_ddr_araddr,  // address of first transfer in a read burst transaction
    output logic[7:0]   cl_sh_ddr_arlen,   // burst length, number of transfers in a burst (+1 to this value)
    output logic[2:0]   cl_sh_ddr_arsize,  // burst size, size of each transfer in the burst
    output logic        cl_sh_ddr_arvalid, // read address valid, signals the read address/control info is valid
    input               sh_cl_ddr_arready, // read address ready, signals the slave is ready to accept an address/control info

    // Read Data Channel (r = read data)
    // AMI is slave
    input[15:0]    sh_cl_ddr_rid,     // read id tag
    input[511:0]   sh_cl_ddr_rdata,   // read data
    input[1:0]     sh_cl_ddr_rresp,   // status of the read transfer
    input          sh_cl_ddr_rlast,   // indicates last transfer in a read burst
    input          sh_cl_ddr_rvalid,  // indicates the read data is valid
    output logic   cl_sh_ddr_rready,  // indicates the master (AMI) can accept read data/response info

    // Interface to AMI2AXI4
    // Incoming read requests
    input  AMIRequest   in_rd_req,
    output logic        out_rd_req_grant,
    // Outgoing requests, always read responses
    output AMIResponse  out_rd_resp,
    input               in_rd_resp_grant

);
		
	// Need a crediting system so rready (able to accept read response data)
	// is only asserted when we're actually waiting on a read response
    // Response credits
    reg[31:0]   read_resp_credit_cnt;
    logic[31:0] new_read_resp_credit_cnt;
    logic       decr_read_resp_credit_cnt;
	logic       incr_read_resp_credit_cnt;
	
    always @(posedge clk) begin 
        if (rst) begin
            read_resp_credit_cnt <= 1'b0;
        end else begin
            read_resp_credit_cnt <= new_read_resp_credit_cnt;
        end
    end
	
	always_comb begin
        new_read_resp_credit_cnt = read_resp_credit_cnt;
        if (incr_read_resp_credit_cnt && !decr_read_resp_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Read Channel %d : Gained response credit", cycle_cntr, channel_id);
            new_read_resp_credit_cnt = read_resp_credit_cnt + 1;
        end else if (!incr_read_resp_credit_cnt && decr_read_resp_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Read Channel %d: Lost response credit", cycle_cntr, channel_id);
            new_read_resp_credit_cnt = read_resp_credit_cnt - 1;
        end else if (incr_read_resp_credit_cnt && decr_read_resp_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Read Channel %d: Submitted a new request and got back a response", cycle_cntr, channel_id);
		end
        // otherwise either gained/lost none (+0) or both (+0)
    end

	logic  enough_resp_credits;
    assign enough_resp_credits = (read_resp_credit_cnt != 32'h0000_0000);
	
	// Read submission path
	
    // Buffer incoming read requests as to not stall the arbiter
    logic rd_req_FIFO_enq;
    logic rd_req_FIFO_deq;
    wire  rd_req_FIFO_full;
    wire  rd_req_FIFO_empty;
    AMIRequest rd_req_FIFO_head;

    HullFIFO
    #(
        .TYPE                   (F1_AMI2AXI4_RdPath_RdReqFIFO_Type),
        .WIDTH                  ($bits(AMIRequest)),
        .LOG_DEPTH              (F1_AMI2AXI4_RdPath_RdReqFIFO_Depth)
    )
    rdReqQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (rd_req_FIFO_enq),
        .data                   (in_rd_req),
        .full                   (rd_req_FIFO_full),
        .q                      (rd_req_FIFO_head),
        .empty                  (rd_req_FIFO_empty),
        .rdreq                  (rd_req_FIFO_deq)
    );
 
    assign rd_req_FIFO_enq  = ddr_is_ready && !rd_req_FIFO_full && in_rd_req.valid && !in_rd_req.isWrite;
    assign out_rd_req_grant = rd_req_FIFO_enq;

    // Submit Requests to AXI4
    assign cl_sh_ddr_arid    = 16'h0000; //currently all transactions are the same id, might be able to optimize and use APP ID later
    assign cl_sh_ddr_araddr  = rd_req_FIFO_head.addr; // addr of the AMIRequest
    assign cl_sh_ddr_arlen   = 8'h00;  // burst length is this value + 1 so arlen = 0 is burst_length of 1
    assign cl_sh_ddr_arsize  = 3'b110; // Each burst is 64 bytes (512 bits)
    assign cl_sh_ddr_arvalid = !rd_req_FIFO_empty && rd_req_FIFO_head.valid; // is the second term really necessary?

    // Was a transaction accepted at the start of this cycle
    reg rd_addr_req_accepted;
    logic rd_addr_req_accepted_new; // will the transaction be accepted
    always@(posedge clk) begin
        if (rst) begin
            rd_addr_req_accepted <= 1'b0;
        end else begin
            rd_addr_req_accepted <= rd_addr_req_accepted_new;
        end
    end

    assign rd_addr_req_accepted_new  = cl_sh_ddr_arvalid && sh_cl_ddr_arready;
    assign rd_req_FIFO_deq           = rd_addr_req_accepted_new;
	assign incr_read_resp_credit_cnt = rd_req_FIFO_deq;
	
	// Read response path
    logic rd_resp_FIFO_enq;
    logic rd_resp_FIFO_deq;
    wire  rd_resp_FIFO_full;
    wire  rd_resp_FIFO_empty;
    AMIResponse rd_resp_in;
    AMIResponse rd_resp_out;
    
    assign rd_resp_in = '{valid: 1'b1, data: sh_cl_ddr_rdata, size : 6'b100_0000}; // fixed 64 bytes
    
    HullFIFO
    #(
        .TYPE                   (F1_AMI2AXI4_RdPath_RdRespFIFO_Type),
        .WIDTH                  ($bits(AMIResponse)),
        .LOG_DEPTH              (F1_AMI2AXI4_RdPath_RdRespFIFO_Depth)
    )
    rdRespQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (rd_resp_FIFO_enq),
        .data                   (rd_resp_in),
        .full                   (rd_resp_FIFO_full),
        .q                      (rd_resp_out),
        .empty                  (rd_resp_FIFO_empty),
        .rdreq                  (rd_resp_FIFO_deq)
    );
    
    assign out_rd_resp = '{valid: rd_resp_out.valid && !rd_resp_FIFO_empty, data: rd_resp_out.data, size: rd_resp_out.size };
    assign rd_resp_FIFO_deq = in_rd_resp_grant;
    
    // Accept read response data from AXI4    
    assign cl_sh_ddr_rready = !rd_resp_FIFO_full && enough_resp_credits; // FIFO has to have room AND we have to be waiting for a response
    assign rd_resp_FIFO_enq = sh_cl_ddr_rvalid && cl_sh_ddr_rready;
    assign decr_read_resp_credit_cnt = rd_resp_FIFO_enq; // enqueing data means we accepted a response and thus lose an internal credit
	
endmodule
