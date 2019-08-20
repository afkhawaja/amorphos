/*

Converts AMI{Requests,Responses} to AXI4

*/

import AMITypes::*;

module AMI2AXI4(
    
    // General Signals
    input               clk,
    input               rst,
	input[3:0]          channel_id,

    // AmorphOS Memory Interface
    // Incoming requests, can be Read or Write
    input  AMIRequest   in_ami_req,
    output logic        out_ami_req_grant,
    // Outgoing requests, always read responses
    output AMIResponse  out_ami_resp,
    input               in_ami_resp_grant,

    // AXI-4 signals to DDR

    // Write Address Channel (aw = address write)
    // AMI is the master (initiator)
    output [15:0]  cl_sh_ddr_awid,    // tag for the write address group
    output [63:0]  cl_sh_ddr_awaddr,  // address of first transfer in write burst
    output [7:0]   cl_sh_ddr_awlen,   // number of transfers in a burst (+1 to this value)
    output [2:0]   cl_sh_ddr_awsize,  // size of each transfer in the burst
    output         cl_sh_ddr_awvalid, // write address valid, signals the write address and control info is correct
    input          sh_cl_ddr_awready, // slave is ready to ass

    // Write Data Channel (w = write data)
    // AMI is the master (initiator)
    output [15:0]  cl_sh_ddr_wid,     // write id tag
    output [511:0] cl_sh_ddr_wdata,   // write data
    output [63:0]  cl_sh_ddr_wstrb,   // write strobes, indicates which byte lanes hold valid data, 1 strobe bit per 8 bits to write
    output         cl_sh_ddr_wlast,   // indicates the last transfer
    output         cl_sh_ddr_wvalid,  // indicates the write data and strobes are valid
    input          sh_cl_ddr_wready,  // indicates the slave can accept write data

    // Write Response Channel (b = write response)
    // AMI is slave
    input[15:0]    sh_cl_ddr_bid,     // response id tag
    input[1:0]     sh_cl_ddr_bresp,   // write response indicating the status of the transaction
    input          sh_cl_ddr_bvalid,  // indicates the write response is valid
    output         cl_sh_ddr_bready,  // indicates the master can accept a write response

    // Read Address Channel (ar = address read)
    // AMI is master (initiator)
    output [15:0]  cl_sh_ddr_arid,    // read address id for the read address group
    output [63:0]  cl_sh_ddr_araddr,  // address of first transfer in a read burst transaction
    output [7:0]   cl_sh_ddr_arlen,   // burst length, number of transfers in a burst (+1 to this value)
    output [2:0]   cl_sh_ddr_arsize,  // burst size, size of each transfer in the burst
    output         cl_sh_ddr_arvalid, // read address valid, signals the read address/control info is valid
    input          sh_cl_ddr_arready, // read address ready, signals the slave is ready to accept an address/control info

    // Read Data Channel (r = read data)
    // AMI is slave
    input[15:0]    sh_cl_ddr_rid,     // read id tag
    input[511:0]   sh_cl_ddr_rdata,   // read data
    input[1:0]     sh_cl_ddr_rresp,   // status of the read transfer
    input          sh_cl_ddr_rlast,   // indicates last transfer in a read burst
    input          sh_cl_ddr_rvalid,  // indicates the read data is valid
    output         cl_sh_ddr_rready,  // indicates the master (AMI) can accept read data/response info
    
    // Misc
    input          sh_cl_ddr_is_ready // figure out what this is    

);

	// Check if the memory controllers are ready to issue memory requests
	logic ddr_is_ready_local;

	always@(posedge clk) begin
		if (rst) begin
			ddr_is_ready_local <= 1'b0;
		end else begin 
			if (sh_cl_ddr_is_ready == 1'b1) begin
				ddr_is_ready_local <= 1'b1;
			end
		end
	end
	
	// Debug counter
    // Counter
    wire[63:0] cycle_cntr;
    
    Counter64 
    clk_counter64
    (
        .clk             (clk),
        .rst             (rst),
        .increment       (1'b1), // clock is always incrementing
        .count           (cycle_cntr)
    );
    
    // Rd Path Signals
    wire  rd_req_grant;

    // Rd Path
    AMI2AXI4_RdPath
    ami2axi4_rdpath_inst
    (
        // General Signals
        .clk (clk),
        .rst (rst),
		.channel_id(channel_id),
		.cycle_cntr (cycle_cntr),
		.ddr_is_ready(ddr_is_ready_local),
        // Pass through the 2 channels to AXI4
        // Read Address Channel 
        .cl_sh_ddr_arid   (cl_sh_ddr_arid),    
        .cl_sh_ddr_araddr (cl_sh_ddr_araddr), 
        .cl_sh_ddr_arlen  (cl_sh_ddr_arlen),   
        .cl_sh_ddr_arsize (cl_sh_ddr_arsize),  
        .cl_sh_ddr_arvalid(cl_sh_ddr_arvalid), 
        .sh_cl_ddr_arready(sh_cl_ddr_arready), 
        // Read Data Channel 
        .sh_cl_ddr_rid    (sh_cl_ddr_rid),
        .sh_cl_ddr_rdata  (sh_cl_ddr_rdata),
        .sh_cl_ddr_rresp  (sh_cl_ddr_rresp),
        .sh_cl_ddr_rlast  (sh_cl_ddr_rlast),
        .sh_cl_ddr_rvalid (sh_cl_ddr_rvalid),
        .cl_sh_ddr_rready (cl_sh_ddr_rready),
        // Interface to AMI2AXI4
        // Incoming read requests
        .in_rd_req        (in_ami_req),
        .out_rd_req_grant (rd_req_grant),
        // Outgoing requests, always read responses
        .out_rd_resp      (out_ami_resp),
        .in_rd_resp_grant (in_ami_resp_grant)
    );

    // Wr Path Signals
    wire  wr_req_grant;

    // Wr Path
    AMI2AXI4_WrPath
    ami2axi4_wrpath_inst
    (
        // General Signals
        .clk (clk),
        .rst (rst),
		.channel_id(channel_id),
		.cycle_cntr(cycle_cntr),
		.ddr_is_ready(ddr_is_ready_local),
        // Write Address Channel
        // AMI is the master (initiator)
        .cl_sh_ddr_awid   (cl_sh_ddr_awid),
        .cl_sh_ddr_awaddr (cl_sh_ddr_awaddr),
        .cl_sh_ddr_awlen  (cl_sh_ddr_awlen),
        .cl_sh_ddr_awsize (cl_sh_ddr_awsize),
        .cl_sh_ddr_awvalid(cl_sh_ddr_awvalid),
        .sh_cl_ddr_awready(sh_cl_ddr_awready),
        // Write Data Channel
        // AMI is the master (initiator)
        .cl_sh_ddr_wid    (cl_sh_ddr_wid),
        .cl_sh_ddr_wdata  (cl_sh_ddr_wdata),
        .cl_sh_ddr_wstrb  (cl_sh_ddr_wstrb),
        .cl_sh_ddr_wlast  (cl_sh_ddr_wlast),
        .cl_sh_ddr_wvalid (cl_sh_ddr_wvalid),
        .sh_cl_ddr_wready (sh_cl_ddr_wready),
        // Write Response Channel
        // AMI is slave
        .sh_cl_ddr_bid    (sh_cl_ddr_bid),
        .sh_cl_ddr_bresp  (sh_cl_ddr_bresp),
        .sh_cl_ddr_bvalid (sh_cl_ddr_bvalid),
        .cl_sh_ddr_bready (cl_sh_ddr_bready),
        // Interface to AMI2AXI4
        // Incoming write requests
        .in_wr_req        (in_ami_req),
        .out_wr_req_grant (wr_req_grant)
    );
        
    // Only deque a request if its path has accepted it
    assign out_ami_req_grant = wr_req_grant || rd_req_grant;


endmodule

