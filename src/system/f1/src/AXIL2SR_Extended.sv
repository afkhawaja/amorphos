/*

    Interfaces to the AXI-Lite interface and converts to/from SoftReg requests/responses

*/

import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module AXIL2SR_Extended(

    // General Signals
    input clk,
    input rst,

    // Write Address
    input              sh_bar1_awvalid,
    input[31:0]        sh_bar1_awaddr,
    output logic       bar1_sh_awready,

    //Write data
    input              sh_bar1_wvalid,
    input[31:0]        sh_bar1_wdata,
    input[3:0]         sh_bar1_wstrb,
    output logic       bar1_sh_wready,

    //Write response
    output logic       bar1_sh_bvalid,
    output logic[1:0]  bar1_sh_bresp,
    input              sh_bar1_bready,

    //Read address
    input              sh_bar1_arvalid,
    input[31:0]        sh_bar1_araddr,
    output logic       bar1_sh_arready,

    //Read data/response
    output logic       bar1_sh_rvalid,
    output logic[31:0] bar1_sh_rdata,
    output logic[1:0]  bar1_sh_rresp,
    input              sh_bar1_rready,

    // Interface to SoftReg
    // Requests
    output SoftRegReq  softreg_req,
    input              softreg_req_grant,
    // Responses
    input SoftRegResp  softreg_resp,
    output             softreg_resp_grant

);

	// Debug counter
	wire[63:0] debug_cntr;
	// Debug counter
	Counter64 cntr(
		.clk(clk),
		.rst(rst), 
		.increment(1'b1),
		.count(debug_cntr)
	);

	// work around for genvar expecting constant expressions
	logic selects[1:0];
	assign selects[0] = 1'b0;
	assign selects[1] = 1'b1;
	

    //////////////////////////////////
    // Write requests
    //////////////////////////////////

	// Need to skip storing every other 
	reg   skip_wr_addr_enq;
    logic new_skip_wr_addr_enq;
    
    always @(posedge clk) begin 
        if (rst) begin
            skip_wr_addr_enq <= 1'b0;
        end else begin
            skip_wr_addr_enq <= new_skip_wr_addr_enq;
        end
    end

    // Keep track of the address to pass along
    logic       wr_addr_FIFO_enq;
    logic       wr_addr_FIFO_deq;
    wire        wr_addr_FIFO_full;
    wire        wr_addr_FIFO_empty;
    wire[31:0]  wr_addr_FIFO_head;

    HullFIFO
    #(
        .TYPE                   (F1_AXIL_wr_addr_FIFO_Type),
        .WIDTH                  (32), // matches the address width
        .LOG_DEPTH              (F1_AXIL_wr_addr_FIFO_Depth)
    )
    wr_addrQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (wr_addr_FIFO_enq),
        .data                   (sh_bar1_awaddr), // do we need to account for the BAR here?
        .full                   (wr_addr_FIFO_full),
        .q                      (wr_addr_FIFO_head),
        .empty                  (wr_addr_FIFO_empty),
        .rdreq                  (wr_addr_FIFO_deq)
    );

    assign bar1_sh_awready  = !wr_addr_FIFO_full;
    assign wr_addr_FIFO_enq = bar1_sh_awready && sh_bar1_awvalid && !skip_wr_addr_enq;
    
	always_comb begin
		new_skip_wr_addr_enq = skip_wr_addr_enq;
		// skip the new one
		if (wr_addr_FIFO_enq) begin
		    new_skip_wr_addr_enq = 1'b1;
		// just skipped one, so save the next one
		end else if (bar1_sh_awready && sh_bar1_awvalid && skip_wr_addr_enq) begin
			new_skip_wr_addr_enq = 1'b0;
		end
	end
	
    // Track which input FIFO to accept writes to
    reg   write_fifo_select;
    logic new_write_fifo_select;
    
    always @(posedge clk) begin 
        if (rst) begin
            write_fifo_select <= 1'b0;
        end else begin
            write_fifo_select <= new_write_fifo_select;
        end
    end

    // Two 32-bit FIFOs for each half of the 64 bit SoftReg data portion
    logic[1:0]  wr_data_FIFO_enq;
    logic[1:0]  wr_data_FIFO_deq;
    wire[1:0]   wr_data_FIFO_full;
    wire[1:0]   wr_data_FIFO_empty;
    wire[31:0]  wr_data_FIFO_head[1:0];
	
    genvar i;
    generate 
        for (i = 0; i < 2; i = i + 1) begin: input_write_FIFOs
            HullFIFO
            #(
                .TYPE                   (F1_AXIL_wr_data_FIFO_Type),
                .WIDTH                  (32), // half of a 64-bit chunk
                .LOG_DEPTH              (F1_AXIL_wr_data_FIFO_Depth)
            )
            wr_dataQ
            (
                .clock                  (clk),
                .reset_n                (~rst),
                .wrreq                  (wr_data_FIFO_enq[i]),
                .data                   (sh_bar1_wdata), // same input to both, only one captures the value
                .full                   (wr_data_FIFO_full[i]),
                .q                      (wr_data_FIFO_head[i]),
                .empty                  (wr_data_FIFO_empty[i]),
                .rdreq                  (wr_data_FIFO_deq[i])
            );
	    // enq signal
           assign wr_data_FIFO_enq[i] = sh_bar1_wvalid && bar1_sh_wready && !wr_data_FIFO_full[i] && (write_fifo_select == selects[i]);	
        end // for	
    endgenerate

    // ignoring wrstrb for now since we will ensure in SW everything is 64 bit aligned
    assign bar1_sh_wready = !(|wr_data_FIFO_full); // both have to have room, use OR reduction
    // Logic to switch which FIFO we're writing into
    always_comb begin
        new_write_fifo_select = write_fifo_select;
        if ((|wr_data_FIFO_enq)) begin
            new_write_fifo_select = ~write_fifo_select;
        end
    end

    // Write response
    reg[31:0]   resp_counter;
    logic[31:0] new_resp_counter;

    always @(posedge clk) begin 
        if (rst) begin
            resp_counter <= {32{1'b0}};
        end else begin
            resp_counter <= new_resp_counter;
        end
    end    

    logic resp_sent;
    assign resp_sent = sh_bar1_bready && bar1_sh_bvalid;
    logic wr_data_received;
    assign wr_data_received = (|wr_data_FIFO_enq);

    always_comb begin
        new_resp_counter = resp_counter;
        // if any write data was received
        if (wr_data_received && (!resp_sent)) begin
            new_resp_counter = resp_counter + 1;
        // no new request and response sent out
        end else if ((!wr_data_received) && resp_sent) begin
            new_resp_counter = resp_counter - 1;
        end
        // else either nothing happened or both a write request accepted and response sent out (-1 + 1 = 0), no change
    end

    // 0b00  == OKAY
    // 0b10  == SLVERR
    assign bar1_sh_bresp  = 2'b00;
    assign bar1_sh_bvalid = (resp_counter != {32{1'b0}});

    // Combine the write request into a SoftRegReq
    SoftRegReq write_sr_req;
    assign write_sr_req.valid   = !wr_addr_FIFO_empty && !wr_data_FIFO_empty[1] && !wr_data_FIFO_empty[0];
    assign write_sr_req.isWrite = 1'b1;
    assign write_sr_req.addr    = wr_addr_FIFO_head; // do we need to account for the BAR?
    assign write_sr_req.data    = {wr_data_FIFO_head[1],wr_data_FIFO_head[0]}; 

    //////////////////////////////////
    // Read requests
    //////////////////////////////////

    reg   read_req_fifo_select;
    logic new_read_req_fifo_select;
    reg   read_submit_select;
	logic new_read_submit_select;
	reg[31:0]   read_resp_credit_cnt;
	logic[31:0] new_read_resp_credit_cnt;
	
    always @(posedge clk) begin 
        if (rst) begin
            read_req_fifo_select <= 1'b0;
			read_submit_select   <= 1'b0;
			read_resp_credit_cnt <= 1'b0;
        end else begin
            read_req_fifo_select <= new_read_req_fifo_select;
			read_submit_select   <= new_read_submit_select;
			read_resp_credit_cnt <= new_read_resp_credit_cnt;
        end
    end
    
    // Two FIFOs for each half of the 64 bit read request
    logic[1:0]  read_req_FIFO_enq;
    logic[1:0]  read_req_FIFO_deq;
    wire[1:0]   read_req_FIFO_full;
    wire[1:0]   read_req_FIFO_empty;
    wire[31:0]  read_req_FIFO_head[1:0];

    generate 
        for (i = 0; i < 2; i = i + 1) begin: read_req_FIFOs
            HullFIFO
            #(
                .TYPE                   (F1_AXIL_rd_req_FIFO_Type),
                .WIDTH                  (32), // half of a 64-bit chunk
                .LOG_DEPTH              (F1_AXIL_rd_req_FIFO_Depth)
            )
            read_reqQ
            (
                .clock                  (clk),
                .reset_n                (~rst),
                .wrreq                  (read_req_FIFO_enq[i]),
                .data                   (sh_bar1_araddr), // same input to both, only one captures the value
                .full                   (read_req_FIFO_full[i]),
                .q                      (read_req_FIFO_head[i]),
                .empty                  (read_req_FIFO_empty[i]),
                .rdreq                  (read_req_FIFO_deq[i])
            );
	    assign read_req_FIFO_enq[i] = sh_bar1_arvalid && bar1_sh_arready && !read_req_FIFO_full[i] && (read_req_fifo_select == selects[i]);
        end // for
    endgenerate
    
    assign bar1_sh_arready = !(|read_req_FIFO_full); // both have to have room, use OR reduction
    // Logic to switch which FIFO we're wr iting into
    always_comb begin
        new_read_req_fifo_select = read_req_fifo_select;
        if ((|read_req_FIFO_enq)) begin
            new_read_req_fifo_select = ~read_req_fifo_select;
        end
    end    

    // Read request
    SoftRegReq read_sr_req;
    /*assign read_sr_req.valid   = !read_req_FIFO_empty[0] || !read_req_FIFO_empty[1];
    assign read_sr_req.isWrite = 1'b0;
    assign read_sr_req.addr    = read_req_FIFO_head[0]; // address of the first 32-bit chunk
    assign read_sr_req.data    = 64'b0;*/
    
	always_comb begin
		new_read_submit_select = read_submit_select;
		read_sr_req.valid    = 1'b0;
		read_sr_req.isWrite  = 1'b0;
		read_sr_req.addr     = read_req_FIFO_head[0];
		read_sr_req.data     = 64'b0;
		// dummy request
		read_req_FIFO_deq[1] = 1'b0;
		if (!read_req_FIFO_empty[0] && (read_submit_select == 1'b0)) begin
			read_sr_req.valid = 1'b1;
			read_sr_req.addr  = read_req_FIFO_head[0];
			if (softreg_req_grant && (write_sr_req.valid == 1'b0)) begin
				new_read_submit_select = 1'b1;
			end
		end else if (!read_req_FIFO_empty[1] && (read_submit_select == 1'b1)) begin
			// throw away this request as the first was already converted to a 64-bit softreg read request
			read_sr_req.valid = 1'b0;
			read_sr_req.addr  = read_req_FIFO_head[1];
			new_read_submit_select = 1'b0;
			read_req_FIFO_deq[1]   = 1'b1;
		end	
	end
	
    //////////////////////////////////
    // Arbitration
    //////////////////////////////////
    
    // Intermediate FIFO late for timing
    logic       buffer_sr_req_FIFO_enq;
    logic       buffer_sr_req_FIFO_deq;
    wire        buffer_sr_req_FIFO_full;
    wire        buffer_sr_req_FIFO_empty;
    SoftRegReq  buffer_sr_req_FIFO_head;
	SoftRegReq  buffer_sr_req_FIFO_data_in;
	
    HullFIFO
    #(
        .TYPE                   (F1_AXIL_buffer_sr_req_FIFO_Type),
        .WIDTH                  ($bits(SoftRegReq)), // matches the data width
        .LOG_DEPTH              (F1_AXIL_buffer_sr_req_FIFO_Depth)
    )
    buffer_sr_req_queue
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (buffer_sr_req_FIFO_enq),
        .data                   (buffer_sr_req_FIFO_data_in),
        .full                   (buffer_sr_req_FIFO_full),
        .q                      (buffer_sr_req_FIFO_head),
        .empty                  (buffer_sr_req_FIFO_empty),
        .rdreq                  (buffer_sr_req_FIFO_deq)
    );

	always_comb begin
		buffer_sr_req_FIFO_deq = 1'b0;
        softreg_req.valid   = 1'b0;
        softreg_req.isWrite = buffer_sr_req_FIFO_head.isWrite;
        softreg_req.addr    = buffer_sr_req_FIFO_head.addr;
        softreg_req.data    = buffer_sr_req_FIFO_head.data;		
		if (!buffer_sr_req_FIFO_empty && buffer_sr_req_FIFO_head.valid) begin
			$display("Cycle: %d AXIL2SR: Trying to submit a request to SR addr: %x data: %x isWrite: %x", debug_cntr, buffer_sr_req_FIFO_head.addr, buffer_sr_req_FIFO_head.data, buffer_sr_req_FIFO_head.isWrite);
            softreg_req.valid = 1'b1;
            if (softreg_req_grant) begin
				$display("Cycle: %d AXIL2SR: Request accepted by SR", debug_cntr);
				buffer_sr_req_FIFO_deq = 1'b1;
            end
		end
	end
	
    always_comb begin
        buffer_sr_req_FIFO_data_in.valid   = 1'b0;
        buffer_sr_req_FIFO_data_in.isWrite = write_sr_req.isWrite;
        buffer_sr_req_FIFO_data_in.addr    = write_sr_req.addr;
        buffer_sr_req_FIFO_data_in.data    = write_sr_req.data;
    
        wr_addr_FIFO_deq    = 1'b0;
        wr_data_FIFO_deq[0] = 1'b0;
        wr_data_FIFO_deq[1] = 1'b0;

        read_req_FIFO_deq[0] = 1'b0;
		
		buffer_sr_req_FIFO_enq = 1'b0;
    
        if (write_sr_req.valid == 1'b1) begin 
			$display("Cycle: %d AXIL2SR: Trying to submit a Write request to buffer addr: %x data: %x", debug_cntr, buffer_sr_req_FIFO_data_in.addr, buffer_sr_req_FIFO_data_in.data);
            buffer_sr_req_FIFO_data_in.valid = 1'b1;
            if (!buffer_sr_req_FIFO_full) begin
				$display("Cycle: %d AXIL2SR: Write request accepted by buffer",debug_cntr);
                wr_addr_FIFO_deq    = 1'b1;
                wr_data_FIFO_deq[0] = 1'b1;
                wr_data_FIFO_deq[1] = 1'b1;
				buffer_sr_req_FIFO_enq = 1'b1;
            end
        end else if (read_sr_req.valid == 1'b1) begin
			$display("Cycle: %d AXIL2SR: Trying to submit a Read request to buffer addr: %x ", debug_cntr, read_sr_req.addr);
            buffer_sr_req_FIFO_data_in.valid   = 1'b1;
            buffer_sr_req_FIFO_data_in.isWrite = 1'b0;
            buffer_sr_req_FIFO_data_in.addr    = read_sr_req.addr;
            buffer_sr_req_FIFO_data_in.data    = read_sr_req.data;
            if (!buffer_sr_req_FIFO_full) begin
				$display("Cycle: %d AXIL2SR: Read request accepted by buffer", debug_cntr);
                read_req_FIFO_deq[0] = 1'b1;
				buffer_sr_req_FIFO_enq = 1'b1;
            end
        end
    end

    // Read response path (address-less)
    // Accept responses into a buffer
    logic       rd_resp_FIFO_enq;
    logic       rd_resp_FIFO_deq;
    wire        rd_resp_FIFO_full;
    wire        rd_resp_FIFO_empty;
    wire[63:0]  rd_resp_FIFO_head;

    HullFIFO
    #(
        .TYPE                   (F1_AXIL_rd_resp_FIFO_Type),
        .WIDTH                  (64), // matches the data width
        .LOG_DEPTH              (F1_AXIL_rd_resp_FIFO_Depth)
    )
    rd_respQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (rd_resp_FIFO_enq),
        .data                   (softreg_resp.data),
        .full                   (rd_resp_FIFO_full),
        .q                      (rd_resp_FIFO_head),
        .empty                  (rd_resp_FIFO_empty),
        .rdreq                  (rd_resp_FIFO_deq)
    );

    assign rd_resp_FIFO_enq   = softreg_resp.valid && !rd_resp_FIFO_full;
    assign softreg_resp_grant = rd_resp_FIFO_enq;

	always_comb begin
		if (rd_resp_FIFO_enq) begin
			$display("Cycle: %d AXIL2SR: Read data returned from SR (%x)", debug_cntr, softreg_resp.data);
		end
	end
	
	// only signal data ready when a credit is available, this avoids issues with 64-bit data being ready
	// before the second 32-bit read request comes in from F1_AXIL_rd_req_FIFO_Depth
	always_comb begin
		new_read_resp_credit_cnt = read_resp_credit_cnt;
		// 32-bit read request accepted
		if ((|read_req_FIFO_enq)) begin
			// we gained a credit and lost one by submiting a response, so net 0
			if (bar1_sh_rvalid && sh_bar1_rready) begin
				// no change
			end else begin
				// gained a credit
				new_read_resp_credit_cnt = read_resp_credit_cnt + 1;
			end
		// see if we lost a credit
		end else if (bar1_sh_rvalid && sh_bar1_rready) begin
			new_read_resp_credit_cnt = read_resp_credit_cnt - 1;
		end
		// else no change
	end
	
    // Submit each half of the 64-bit response to the F1 Shell
    reg rd_resp_half_select;
    logic new_rd_resp_half_select;
    always @(posedge clk) begin 
        if (rst) begin
            rd_resp_half_select <= 1'b0;
        end else begin
            rd_resp_half_select <= new_rd_resp_half_select;
        end
    end
    
    assign bar1_sh_rvalid = !rd_resp_FIFO_empty && (read_resp_credit_cnt != 32'h0000_0000);
    assign bar1_sh_rdata  = (rd_resp_half_select == 1'b0) ? rd_resp_FIFO_head[31:0] : rd_resp_FIFO_head[63:32];
    // 0b00  == OKAY
    // 0b10  == SLVERR
    assign bar1_sh_rresp    = 2'b00;
    assign rd_resp_FIFO_deq = (rd_resp_half_select == 1'b1) && sh_bar1_rready && bar1_sh_rvalid; // deque if the second half of the chunk was accepted
    
    always_comb begin
        new_rd_resp_half_select = rd_resp_half_select;
        if (rd_resp_FIFO_deq) begin // second chunk was just accepted
            new_rd_resp_half_select = 1'b0;
        end else if ((rd_resp_half_select == 1'b0) && sh_bar1_rready && bar1_sh_rvalid) begin // first chunk was just accepted
            new_rd_resp_half_select = 1'b1;
        end
    end
    
endmodule
