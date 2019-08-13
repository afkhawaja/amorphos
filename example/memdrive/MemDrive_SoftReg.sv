import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module MemDrive_SoftReg
(
    // User clock and reset
    input                               clk,
    input                               rst, 

    input [AMI_APP_BITS-1:0]            srcApp,
    
    // Simplified Memory interface
    output AMIRequest                   mem_reqs        [1:0],
    input                               mem_req_grants  [1:0],
    input AMIResponse                   mem_resps       [1:0],
    output logic                        mem_resp_grants [1:0],

    // PCIe Slot DMA interface
    input PCIEPacket                    pcie_packet_in,
    output                              pcie_full_out,

    output PCIEPacket                   pcie_packet_out,
    input                               pcie_grant_in,

    // Soft register interface
    input  SoftRegReq                   softreg_req,
    output SoftRegResp                  softreg_resp
);
    
    // clk and debug counter
    wire[63:0] clk_counter;

    // Don't need the PCI-e interface
    assign pcie_full_out = 1'b0;
    assign pcie_packet_out = '{valid: 1'b0, data: 0, slot: 0, pad: 0, last: 1'b0};

    // Response credits
    reg[31:0]   read_resp_credit_cnt;
    logic[31:0] new_read_resp_credit_cnt;
    logic       decr_read_resp_credit_cnt;

    always @(posedge clk) begin 
        if (rst) begin
            read_resp_credit_cnt <= 1'b0;
        end else begin
            read_resp_credit_cnt <= new_read_resp_credit_cnt;
        end
    end    

    // Input queue for PCI-e
    wire             sr_inQ_empty;
    wire             sr_inQ_full;
    logic            sr_inQ_enq;
    logic            sr_inQ_deq;
    SoftRegReq       sr_inQ_in;
    SoftRegReq       sr_inQ_out;

    HullFIFO
    #(
        .TYPE                   (MEMDRIVE_SOFTREG_FIFO_Type),
        .WIDTH                  ($bits(SoftRegReq)),
        .LOG_DEPTH              (MEMDRIVE_SOFTREG_FIFO_Depth)
    )
    softReg_InQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (sr_inQ_enq),
        .data                   (sr_inQ_in),
        .full                   (sr_inQ_full),
        .q                      (sr_inQ_out),
        .empty                  (sr_inQ_empty),
        .rdreq                  (sr_inQ_deq)
    );    

    // Connections to softreg input interface
    assign sr_inQ_in   = softreg_req;
    assign sr_inQ_enq  = softreg_req.valid && (softreg_req.isWrite == 1'b1) && !sr_inQ_full;
    
    logic  incoming_req_is_read;
    assign incoming_req_is_read = softreg_req.valid && (softreg_req.isWrite == 1'b0);
    
    always_comb begin
        new_read_resp_credit_cnt = read_resp_credit_cnt;
        if (incoming_req_is_read && !decr_read_resp_credit_cnt) begin
			$display("Cycle %d MemDrive: Gained response credit", clk_counter);
            new_read_resp_credit_cnt = read_resp_credit_cnt + 1;
        end else if (!incoming_req_is_read && decr_read_resp_credit_cnt) begin
			$display("Cycle %d MemDrive: Lost response credit", clk_counter);
            new_read_resp_credit_cnt = read_resp_credit_cnt - 1;
        end
        // otherwise either gained/lost none (+0) or both (+0)
    end
    
    // Logic used to program the FSM over PCI-e
    parameter PACKET_COUNT = 8; // 8 64 bit packet contents
    //  Information to read/write
    reg[63:0] program_struct[PACKET_COUNT-1:0];
    logic[63:0] start_addr;
    logic[63:0] total_subs;
    logic[63:0] mask;
    logic[63:0] mode;    
    logic[63:0] start_addr2;
    logic[63:0] addr_delta;
    logic[63:0] canary0;
    logic[63:0] canary1;
    
    reg[3:0] wr_count;
    logic[3:0] new_wr_count;
    logic[($clog2(PACKET_COUNT))-1:0] struct_wr_index;
    logic   struct_wr_en;
    
    assign start_addr  = program_struct[0][63:0];
    assign total_subs  = program_struct[1][63:0];
    assign mask        = program_struct[2][63:0];
    assign mode        = program_struct[3][63:0];
    assign start_addr2 = program_struct[4][63:0];
    assign addr_delta  = program_struct[5][63:0];
    assign canary0     = program_struct[6][63:0];
    assign canary1     = program_struct[7][63:0];
    
    // Counter
    reg[63:0]  start_cycle;
    logic      start_cycle_we;
	reg[63:0]  end_cycle;
	logic      end_cycle_we;
    
    Counter64 
    clk_counter64
    (
        .clk             (clk),
        .rst             (rst),
        .increment       (1'b1), // clock is always incrementing
        .count           (clk_counter)
    );
    
    always@(posedge clk) begin : start_cycle_update
        if (rst) begin
            start_cycle  <= 64'h0;
			end_cycle    <= 64'h0;
        end else begin
            if (start_cycle_we) begin
                start_cycle <= clk_counter;
            end
			if (end_cycle_we) begin
				end_cycle <= clk_counter;
			end
        end
    end

    // Submission counter
    reg[63:0]   sub_counter;
    logic[63:0] new_sub_counter;
    logic       sub_counter_we;
    
    always@(posedge clk) begin : sub_counter_update
        if (rst) begin
            sub_counter <= 64'h0;
        end else begin
            if (sub_counter_we) begin
                sub_counter <= new_sub_counter;
            end
        end
    end
    
    // Resp counter
    reg[63:0] resp_counter;
    logic[63:0] new_resp_counter;
    logic resp_counter_we;
    logic reset_resp_counter;

    always@(posedge clk) begin : resp_counter_update
        if (rst) begin
            resp_counter <= 64'h0;
        end else begin
            if (reset_resp_counter) begin
                resp_counter <= 64'h0;
            end else if (resp_counter_we) begin
                resp_counter <= new_resp_counter;
            end
        end
    end
    
    // Submissions Queues
    parameter SUB_Q_LOG_DEPTH = 9;
    
    genvar port_num;

    wire             sub_inQ_empty[AMI_NUM_PORTS-1:0];
    wire[AMI_NUM_PORTS-1:0]             sub_inQ_full;
    logic            sub_inQ_enq[AMI_NUM_PORTS-1:0];
    logic            sub_inQ_deq[AMI_NUM_PORTS-1:0];
    AMIRequest       sub_inQ_in[AMI_NUM_PORTS-1:0];
    AMIRequest       sub_inQ_out[AMI_NUM_PORTS-1:0];

    generate
        for (port_num = 0; port_num < AMI_NUM_PORTS; port_num = port_num + 1) begin : sub_in_queues
            HullFIFO
            #(
                .TYPE                     (MEMDRIVE_SUB_Q_Type),
                .WIDTH                    ($bits(AMIRequest)),
                .LOG_DEPTH                (MEMDRIVE_SUB_Q_Depth)
            )
            sub_InQ
            (
                .clock                    (clk),
                .reset_n                (~rst),
                .wrreq                    (sub_inQ_enq[port_num]),
                .data                   (sub_inQ_in[port_num]),
                .full                   (sub_inQ_full[port_num]),
                .q                      (sub_inQ_out[port_num]),
                .empty                  (sub_inQ_empty[port_num]),
                .rdreq                  (sub_inQ_deq[port_num])
            );
            assign mem_reqs[port_num].valid   = sub_inQ_out[port_num].valid && !sub_inQ_empty[port_num];
            assign mem_reqs[port_num].isWrite = sub_inQ_out[port_num].isWrite;
            assign mem_reqs[port_num].addr    = sub_inQ_out[port_num].addr;
            assign mem_reqs[port_num].data    = sub_inQ_out[port_num].data;
            assign mem_reqs[port_num].size    = sub_inQ_out[port_num].size;
            
            assign sub_inQ_deq[port_num] = mem_req_grants[port_num] && sub_inQ_out[port_num].valid && !sub_inQ_empty[port_num];

        end
    endgenerate

    always_comb begin
	if (sub_inQ_enq[0]) begin
	   $display("MemDrive: Sub 0 Enqueing addr: %h ", sub_inQ_in[0].addr);
	end
	if (sub_inQ_enq[1]) begin
	   $display("MemDrive: Sub 1 Enqueing addr: %h ", sub_inQ_in[1].addr);
	end

	if (sub_inQ_deq[0] == 1'b1) begin
	    $display("MemDrive: Submit addr: %h on port 0, start addr: %h , addr delta: %d total_subs: %d, subcounter: %d", sub_inQ_out[0].addr, start_addr, addr_delta, total_subs, sub_counter);
        end
	if (sub_inQ_deq[1] == 1'b1) begin
	    $display("MemDrive: Submit addr: %h on port 1, start addr: %h , addr delta: %d total_subs: %d, subcounter: %d", sub_inQ_out[1].addr, start_addr2, addr_delta, total_subs, sub_counter);
        end

    end

    // monitor the submission queues
    // per port counter
    reg[63:0]   sub_queue_full[AMI_NUM_PORTS-1:0];
    logic[63:0] new_sub_queue_full[AMI_NUM_PORTS-1:0];
    logic         sub_queue_full_we[AMI_NUM_PORTS-1:0];
    // unified counter
    reg[63:0]   all_sub_queue_full;
    logic[63:0] new_all_sub_queue_full;
    logic       all_sub_queue_full_we;
    
    generate
        for (port_num = 0; port_num < AMI_NUM_PORTS; port_num = port_num + 1) begin : monitor_sub_queues

            always@(posedge clk) begin : monitor_sub_counter_update
                if (rst) begin
                    sub_queue_full[port_num] <= 64'h0;
                end else begin
                    if (sub_queue_full_we[port_num]) begin
                        sub_queue_full[port_num] <= new_sub_queue_full[port_num];
                    end
                end
            end        
        
        end
    endgenerate    
    
    always@(posedge clk) begin : monitor_all_counter_update
        if (rst) begin
            all_sub_queue_full <= 64'h0;
        end else begin
            if (all_sub_queue_full_we) begin
                all_sub_queue_full <= new_all_sub_queue_full;
            end
        end
    end
    
    // error counters
    reg[63:0] port0_errors;
    reg[63:0] port1_errors;
    logic[63:0] new_port0_errors;
    logic[63:0] new_port1_errors;    
    logic port0_errors_we;
    logic port1_errors_we;
    logic reset_errors;

    always@(posedge clk) begin : error_counter_update
        if (rst || reset_errors) begin
            port0_errors <= 64'h0;
            port1_errors <= 64'h0;
        end else begin
            if (port0_errors_we) begin
                port0_errors <= new_port0_errors;
            end
            if (port1_errors_we) begin
                port1_errors <= new_port1_errors;
            end
        end
    end
    
    // FSM states
    parameter IDLE        = 4'b0000;
    parameter PROGRAMMING = 4'b0001;
    parameter REQUESTING  = 4'b0010;
    parameter AWAIT_RESP  = 4'b0011;
    parameter CLEAN_UP1   = 4'b0100;
    parameter CLEAN_UP2   = 4'b0101;
    parameter CLEAN_UP3   = 4'b0110;
    parameter CLEAN_UP4   = 4'b0111;
    parameter CLEAN_UP5   = 4'b1000;
    
    // FSM registers
    reg[3:0]   current_state;
    logic[3:0] next_state;

    // FSM reset/update
    always@(posedge clk) begin : fsm_update
        if (rst) begin
            wr_count <=  0;
            current_state  <= IDLE;
        end else begin
            wr_count <= new_wr_count;
            current_state <= next_state;
        end
    end
    // Used when programming the internal struct
    always @(posedge clk) begin : struct_update
        if (struct_wr_en) begin
            program_struct[struct_wr_index] <= sr_inQ_out.data;
        end else begin
            program_struct[struct_wr_index] <= program_struct[struct_wr_index];
        end
    end
    // address temp vars
    logic[63:0] sub_addr[AMI_NUM_PORTS-1:0];
    assign sub_addr[0] = (start_addr  + (sub_counter << addr_delta)) & mask;
    assign sub_addr[1] = (start_addr2 + (sub_counter << addr_delta)) & mask;
    // Values to submit
    logic[511:0] data0;
    logic[511:0] data1;
    
    assign data0 = {srcApp,{(512-64-64-AMI_APP_BITS){1'b0}},sub_counter,canary0};
    assign data1 = {srcApp,{(512-64-64-AMI_APP_BITS){1'b1}},sub_counter,canary1};
    
    logic  enough_sr_resp_credits;
    assign enough_sr_resp_credits = (read_resp_credit_cnt != 32'h0000_0000);
    
    // FSM update logic
    always_comb begin
        next_state = current_state;
        struct_wr_en    = 1'b0;
        struct_wr_index = 0;
        sr_inQ_deq    = 1'b0;
        new_wr_count = wr_count;
        softreg_resp = '{valid: 1'b0, data: 0};
        start_cycle_we = 1'b0;
        sub_counter_we = 1'b0;
        new_sub_counter = 0;
        sub_inQ_in[0] = '{valid: 0, isWrite: 1'b0, addr: 64'b0, data: 512'b0, size: 64};
        sub_inQ_in[1] = '{valid: 0, isWrite: 1'b0, addr: 64'b0, data: 512'b0, size: 64};    
        sub_inQ_enq[0] = 1'b0;
        sub_inQ_enq[1] = 1'b0;
        reset_resp_counter = 1'b0;
        
        sub_queue_full_we[0]   = 1'b0;
        sub_queue_full_we[1]   = 1'b0;
        all_sub_queue_full_we  = 1'b0;
        new_sub_queue_full[0]  = sub_queue_full[0] + 64'h1;
        new_sub_queue_full[1]  = sub_queue_full[1] + 64'h1;
        new_all_sub_queue_full = all_sub_queue_full + 64'h1;
        
        reset_errors = 1'b0;
        decr_read_resp_credit_cnt = 1'b0;
		end_cycle_we = 1'b0;
        
        case (current_state)
            IDLE : begin
                if (!sr_inQ_empty) begin
                    $display("Cycle %d MemDrive %d: Starting programming", clk_counter, srcApp);
                    next_state = PROGRAMMING;
                    //next_state   = CLEAN_UP1;
                end else begin
                    next_state = IDLE;
                end
            end
            PROGRAMMING : begin
                if (!sr_inQ_empty) begin
                    sr_inQ_deq = 1'b1;
                    struct_wr_en = 1'b1;
                    struct_wr_index = wr_count;
                    new_wr_count = wr_count + 1;
                    if (new_wr_count == 4'b1000) begin
                        // Consumed last packet, move on to requesting
                        next_state = REQUESTING;
                        // reset the wr count
                        new_wr_count = 0;
                        // Save the current cycle as the start time stamp
                        start_cycle_we = 1'b1;
                        // Reset the submission counter
                        new_sub_counter = 64'h0;
                        sub_counter_we  = 1'b1;
                        // Reset the sub queue counters
                        sub_queue_full_we[0]   = 1'b1;
                        sub_queue_full_we[1]   = 1'b1;
                        all_sub_queue_full_we  = 1'b1;
                        new_sub_queue_full[0]  = 64'h0;
                        new_sub_queue_full[1]  = 64'h0;
                        new_all_sub_queue_full = 64'h0;
                        // Reset the error counters
                        reset_errors = 1'b1;
                        $display("Cycle %d MemDrive %d: DONE programming", clk_counter, srcApp);
                    end else begin
                        next_state = PROGRAMMING; // need more packets
                    end
                end else begin
                    // Still need more packet(s) to finish programming
                    next_state = PROGRAMMING;
                end
            end
            REQUESTING : begin
                // See if anything left to submit
                if (sub_counter == total_subs) begin
                    next_state = AWAIT_RESP;
                    // reset the sub_counter
                    new_sub_counter = 64'h0;
                    sub_counter_we  = 1'b1;
                end else begin
                    // If either submission queue is full, we don't submit this cycle
                    if (|sub_inQ_full) begin
                        next_state = REQUESTING;
                        // Both full
                        if  (sub_inQ_full[0] && sub_inQ_full[1]) begin
                            all_sub_queue_full_we  = 1'b1;
                        end else if (sub_inQ_full[0]) begin
                            sub_queue_full_we[0]   = 1'b1;
                        end else if (sub_inQ_full[1]) begin
                            sub_queue_full_we[1]   = 1'b1;
                        end

                    end else begin
                        $display("Cycle %d MemDrive %d: Making requests", clk_counter, srcApp);
                        next_state = REQUESTING;
                        // Submit 1 request per port this cycle
                        sub_inQ_in[0] = '{valid: 1'b1, isWrite: mode[0], addr: sub_addr[0], data: data0, size: 64};
                        sub_inQ_in[1] = '{valid: 1'b1, isWrite: mode[0], addr: sub_addr[1], data: data1, size: 64};    
                        sub_inQ_enq[0] = 1'b1;
                        sub_inQ_enq[1] = 1'b1;
                        // update the sub counter
                        new_sub_counter = sub_counter + 64'h1;
                        sub_counter_we  = 1'b1;
                    end
                end
            end
            AWAIT_RESP : begin
                if (clk_counter % 100 == 0) begin
					$display("Cycle %d MemDrive %d: Awaiting responses", clk_counter, srcApp);
				end
                // if its a sequence of writes, no need to wait on response
                if (mode[0] == 1'b1) begin
					$display("Cycle %d MemDrive: Mode == 1, Transitioning to Clean up 1", clk_counter, srcApp);
                    next_state = CLEAN_UP1;
					// save the end cycle
					end_cycle_we = 1'b1;
                end else if (resp_counter == total_subs) begin
                    $display("Cycle %d MemDrive %d: Mode == 0, Transitioning to Clean up 1", clk_counter, srcApp);
					// we're done
                    next_state = CLEAN_UP1;
					// save the end cycle
					end_cycle_we = 1'b1;
                    // reset the resp counter to 0
                    reset_resp_counter = 1'b1;
                end else begin
					if (clk_counter % 100 == 0) begin
						$display("Cycle %d MemDrive %d: Staying in awaiting response", clk_counter, srcApp);
					end
                    // Requests are being dequeued in a different piece of logic
                    next_state = AWAIT_RESP;
                end
            end
            CLEAN_UP1: begin
                if (enough_sr_resp_credits) begin
                    $display("Cycle %d MemDrive %d: Clean up 1", clk_counter, srcApp);
                    softreg_resp = '{valid: 1'b1, data: start_cycle};
                    decr_read_resp_credit_cnt = 1'b1;
                    next_state = CLEAN_UP2;
                end else begin
					if (clk_counter % 100 == 0) begin
						$display("Cycle %d MemDrive %d: Staying in Clean up 1, no resp credits (%d)", clk_counter, srcApp,read_resp_credit_cnt);
					end
                    next_state = CLEAN_UP1;
                end
            end
            CLEAN_UP2: begin
                if (enough_sr_resp_credits) begin
                    $display("Cycle %d MemDrive %d: Clean up 2", clk_counter, srcApp);
                    softreg_resp = '{valid: 1'b1, data: end_cycle};
                    decr_read_resp_credit_cnt = 1'b1;
                    next_state = IDLE;
                    $display("Cycle %d MemDrive %d: DONE", clk_counter, srcApp);
                end else begin
					if (clk_counter % 100 == 0) begin
						$display("Cycle %d MemDrive: Staying in Clean up 2, no resp credits (%d)", clk_counter, read_resp_credit_cnt);
					end
                    next_state = CLEAN_UP2;
                end
            end
            default : begin
                next_state = current_state;
            end
        endcase
    end

    // Response logic
    always_comb begin : respo_comb_logic
        mem_resp_grants[0] = 1'b0;
        mem_resp_grants[1] = 1'b0;
        new_resp_counter = resp_counter;
        resp_counter_we = 1'b0;
        new_port0_errors = port0_errors + 64'h1;
        new_port1_errors = port1_errors + 64'h1;
        port0_errors_we = 1'b0;
        port1_errors_we = 1'b0;
        // handle responses from the memory systems for reads
        // only accept responses if both ports have one
        if (mem_resps[0].valid && mem_resps[1].valid) begin
            mem_resp_grants[0] = 1'b1;
            mem_resp_grants[1] = 1'b1;
            // update the resp counter
            new_resp_counter = resp_counter + 64'h1;
            resp_counter_we  = 1'b1;
            // Check for errors
            // port 0
            if (mem_resps[0].data != {srcApp,{(512-64-64-AMI_APP_BITS){1'b0}},resp_counter,canary0}) begin
                port0_errors_we = 1'b1;
            end
            // port 1
            if (mem_resps[1].data != {srcApp,{(512-64-64-AMI_APP_BITS){1'b1}},resp_counter,canary1}) begin
                port1_errors_we = 1'b1;
            end
        end        
    end
    
endmodule
