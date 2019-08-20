/*

Handles AMI Write Requests to AXI4

*/

import AMITypes::*;
import AOSF1Types::*;

module AMI2AXI4_WrPath(

    // General Signals
    input               clk,
    input               rst,
	input[3:0]          channel_id,
	input[63:0]         cycle_cntr,
	input               ddr_is_ready,
	
    // Write Address Channel (aw = address write)
    // AMI is the master (initiator)
    output logic[15:0]  cl_sh_ddr_awid,    // tag for the write address group
    output logic[63:0]  cl_sh_ddr_awaddr,  // address of first transfer in write burst
    output logic[7:0]   cl_sh_ddr_awlen,   // number of transfers in a burst (+1 to this value)
    output logic[2:0]   cl_sh_ddr_awsize,  // size of each transfer in the burst
    output logic        cl_sh_ddr_awvalid, // write address valid, signals the write address and control info is correct
    input               sh_cl_ddr_awready, // slave is ready to ass

    // Write Data Channel (w = write data)
    // AMI is the master (initiator)
    output logic[15:0]  cl_sh_ddr_wid,     // write id tag
    output logic[511:0] cl_sh_ddr_wdata,   // write data
    output logic[63:0]  cl_sh_ddr_wstrb,   // write strobes, indicates which byte lanes hold valid data, 1 strobe bit per 8 bits to write
    output logic        cl_sh_ddr_wlast,   // indicates the last transfer
    output logic        cl_sh_ddr_wvalid,  // indicates the write data and strobes are valid
    input               sh_cl_ddr_wready,  // indicates the slave can accept write data

    // Write Response Channel (b = write response)
    // AMI is slave
    input[15:0]    sh_cl_ddr_bid,     // response id tag
    input[1:0]     sh_cl_ddr_bresp,   // write response indicating the status of the transaction
    input          sh_cl_ddr_bvalid,  // indicates the write response is valid
    output logic   cl_sh_ddr_bready,  // indicates the master can accept a write response

    // Interface to AMI2AXI4
    // Incoming write requests
    input  AMIRequest   in_wr_req,
    output logic        out_wr_req_grant    

);

	// Need two different credits
	// One for tracking if read addr has been accepted, so we can assert write data ready
	// One for tracking when read data has been accepted, so we can assert ready to accept write response
    // Write Data Credit
	reg[31:0]   write_data_credit_cnt;
    logic[31:0] new_write_data_credit_cnt;
    logic       decr_write_data_credit_cnt;
	logic       incr_write_data_credit_cnt;
	
    always @(posedge clk) begin 
        if (rst) begin
            write_data_credit_cnt <= 1'b0;
        end else begin
            write_data_credit_cnt <= new_write_data_credit_cnt;
        end
    end

	always_comb begin
        new_write_data_credit_cnt = write_data_credit_cnt;
        if (incr_write_data_credit_cnt && !decr_write_data_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Write Channel %d : Gained data credit", cycle_cntr, channel_id);
            new_write_data_credit_cnt = write_data_credit_cnt + 1;
        end else if (!incr_write_data_credit_cnt && decr_write_data_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Write Channel %d: Lost data credit", cycle_cntr, channel_id);
            new_write_data_credit_cnt = write_data_credit_cnt - 1;
        end else if (incr_write_data_credit_cnt && decr_write_data_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Write Channel %d: Both gained/lost data credit", cycle_cntr, channel_id);
		end
        // otherwise either gained/lost none (+0) or both (+0)
    end

	logic  enough_data_credits;
    assign enough_data_credits = (write_data_credit_cnt != 32'h0000_0000);

	// Write Response Credit
    reg[31:0]   write_resp_credit_cnt;
    logic[31:0] new_write_resp_credit_cnt;
    logic       decr_write_resp_credit_cnt;
	logic       incr_write_resp_credit_cnt;
	
    always @(posedge clk) begin 
        if (rst) begin
            write_resp_credit_cnt <= 1'b0;
        end else begin
            write_resp_credit_cnt <= new_write_resp_credit_cnt;
        end
    end

	always_comb begin
        new_write_resp_credit_cnt = write_resp_credit_cnt;
        if (incr_write_resp_credit_cnt && !decr_write_resp_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Write Channel %d : Gained response credit", cycle_cntr, channel_id);
            new_write_resp_credit_cnt = write_resp_credit_cnt + 1;
        end else if (!incr_write_resp_credit_cnt && decr_write_resp_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Write Channel %d: Lost response credit", cycle_cntr, channel_id);
            new_write_resp_credit_cnt = write_resp_credit_cnt - 1;
        end else if (incr_write_resp_credit_cnt && decr_write_resp_credit_cnt) begin
			$display("Cycle %d AMI2AXI4 Write Channel %d: Both gained/lost response credit", cycle_cntr, channel_id);
		end
        // otherwise either gained/lost none (+0) or both (+0)
    end

	logic  enough_resp_credits;
    assign enough_resp_credits = (write_resp_credit_cnt != 32'h0000_0000);
	
	// Write submission path
	
    // Accept AMIRequests and split them into address and data
    // Data buffer
    logic wr_req_data_FIFO_enq;
    logic wr_req_data_FIFO_deq;
    wire  wr_req_data_FIFO_full;
    wire  wr_req_data_FIFO_empty;
    wire[511:0] wr_req_data_FIFO_head;

    HullFIFO
    #(
        .TYPE                   (F1_AMI2AXI4_WrPath_WrReq_Data_FIFO_Type),
        .WIDTH                  (512),
        .LOG_DEPTH              (F1_AMI2AXI4_WrPath_WrReq_Data_FIFO_Depth)
    )
    wrReq_DataQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (wr_req_data_FIFO_enq),
        .data                   (in_wr_req.data[511:0]),
        .full                   (wr_req_data_FIFO_full),
        .q                      (wr_req_data_FIFO_head),
        .empty                  (wr_req_data_FIFO_empty),
        .rdreq                  (wr_req_data_FIFO_deq)
    );

    // Address buffer
    logic wr_req_addr_FIFO_enq;
    logic wr_req_addr_FIFO_deq;
    wire  wr_req_addr_FIFO_full;
    wire  wr_req_addr_FIFO_empty;
    wire[63:0] wr_req_addr_FIFO_head;

    HullFIFO
    #(
        .TYPE                   (F1_AMI2AXI4_WrPath_WrReq_Addr_FIFO_Type),
        .WIDTH                  (64),
        .LOG_DEPTH              (F1_AMI2AXI4_WrPath_WrReq_Addr_FIFO_Depth)
    )
    wrReq_AddrQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (wr_req_addr_FIFO_enq),
        .data                   (in_wr_req.addr), // make sure the valid bit isn't needed
        .full                   (wr_req_addr_FIFO_full),
        .q                      (wr_req_addr_FIFO_head),
        .empty                  (wr_req_addr_FIFO_empty),
        .rdreq                  (wr_req_addr_FIFO_deq)
    );
    
    logic addr_data_not_full;
    assign addr_data_not_full = !wr_req_data_FIFO_full && !wr_req_addr_FIFO_full;
    
	// only accept requests if we can interact with DDR
    assign wr_req_data_FIFO_enq = ddr_is_ready && addr_data_not_full && in_wr_req.valid && in_wr_req.isWrite;
    assign wr_req_addr_FIFO_enq = ddr_is_ready && addr_data_not_full && in_wr_req.valid && in_wr_req.isWrite;
    assign out_wr_req_grant     = ddr_is_ready && addr_data_not_full && in_wr_req.valid && in_wr_req.isWrite;
	
    // Write Address Channel Signals
    assign cl_sh_ddr_awid   = 16'h0000; //currently all transactions are the same id, might be able to optimize and use APP ID later
    assign cl_sh_ddr_awaddr = wr_req_addr_FIFO_head;
    assign cl_sh_ddr_awlen   = 8'h00;  // burst length is this value + 1 so wrlen = 0 is burst_length of 1
    assign cl_sh_ddr_awsize  = 3'b110; // Each burst is 64 bytes (512 bits)
    assign cl_sh_ddr_awvalid = !wr_req_addr_FIFO_empty;
    
    // Was a transaction accepted at the start of this cycle
    reg wr_addr_req_accepted;
    logic wr_addr_req_accepted_new; // will the transaction be accepted
    always@(posedge clk) begin
        if (rst) begin
            wr_addr_req_accepted <= 1'b0;
        end else begin
            wr_addr_req_accepted <= wr_addr_req_accepted_new;
        end
    end

    assign wr_addr_req_accepted_new = cl_sh_ddr_awvalid && sh_cl_ddr_awready;
    assign wr_req_addr_FIFO_deq = wr_addr_req_accepted_new;
	assign incr_write_data_credit_cnt = wr_req_addr_FIFO_deq;
    
    // Write Data Channel Signals
    assign cl_sh_ddr_wid    = 16'h0000; //currently all transactions are the same id, might be able to optimize and use APP ID later
    assign cl_sh_ddr_wdata  = wr_req_data_FIFO_head;
    assign cl_sh_ddr_wstrb  = 64'hFFFF_FFFF_FFFF_FFFF; // all 64 8-bit lanes are valid (64 x 8 = 512 bits)
    assign cl_sh_ddr_wlast  = 1'b1; // always the last since it's a single transaction
    assign cl_sh_ddr_wvalid = !wr_req_data_FIFO_empty && enough_data_credits; // TODO: Do we need to check if the request portion was already submitted

    // Was a transaction accepted at the start of this cycle
    reg wr_data_req_accepted;
    logic wr_data_req_accepted_new; // will the transaction be accepted
    always@(posedge clk) begin
        if (rst) begin
            wr_data_req_accepted = 1'b0;
        end else begin
            wr_data_req_accepted = wr_data_req_accepted_new;
        end
    end

    assign wr_data_req_accepted_new = cl_sh_ddr_wvalid && sh_cl_ddr_wready;
    assign wr_req_data_FIFO_deq = wr_data_req_accepted_new;
	assign decr_write_data_credit_cnt = wr_req_data_FIFO_deq;
	assign incr_write_resp_credit_cnt = wr_req_data_FIFO_deq;
	
    // Write Response Signals
    assign cl_sh_ddr_bready = enough_resp_credits; // currently we don't care about the write responses, just need to accept them
    assign decr_write_resp_credit_cnt = cl_sh_ddr_bready && sh_cl_ddr_bvalid;
	
endmodule
