import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

// Written by Ahmed Khawaja
// Handles the vector add of A + B and writes out a vector C
// Currently does a 32 bit add of each number

module VecAddInt
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

    // Input queue for SoftReq requests
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

    // Connections to softreg input interface
    assign sr_inQ_in   = softreg_req;
    assign sr_inQ_enq  = softreg_req.valid && (softreg_req.isWrite == 1'b1) && !sr_inQ_full;
    
    logic  incoming_req_is_read;
    assign incoming_req_is_read = softreg_req.valid && (softreg_req.isWrite == 1'b0);
    
    always_comb begin
        new_read_resp_credit_cnt = read_resp_credit_cnt;
        if (incoming_req_is_read && !decr_read_resp_credit_cnt) begin
			$display("Cycle %d VecAddInt: Gained response credit", clk_counter);
            new_read_resp_credit_cnt = read_resp_credit_cnt + 1;
        end else if (!incoming_req_is_read && decr_read_resp_credit_cnt) begin
			$display("Cycle %d VecAddInt: Lost response credit", clk_counter);
            new_read_resp_credit_cnt = read_resp_credit_cnt - 1;
        end
        // otherwise either gained/lost none (+0) or both (+0)
    end
 
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

    // Result writes logic
    logic[63:0] current_write_addr; // this muxes between the next value and a new value
    logic       current_write_addr_we;
    logic[63:0] current_write_addr_init_val;
    logic       current_write_addr_init_val_we;

    // Read request logic
    logic[63:0] current_read_addr[1:0];
    logic       current_read_addr_we[1:0];
    logic[63:0] 
    

    
    
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
                    $display("Cycle %d VecAddInt %d: Starting programming", clk_counter, srcApp);
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
                        $display("Cycle %d VecAddInt %d: DONE programming", clk_counter, srcApp);
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
                        $display("Cycle %d VecAddInt %d: Making requests", clk_counter, srcApp);
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
					$display("Cycle %d VecAddInt %d: Awaiting responses", clk_counter, srcApp);
				end
                // if its a sequence of writes, no need to wait on response
                if (mode[0] == 1'b1) begin
					$display("Cycle %d VecAddInt: Mode == 1, Transitioning to Clean up 1", clk_counter, srcApp);
                    next_state = CLEAN_UP1;
					// save the end cycle
					end_cycle_we = 1'b1;
                end else if (resp_counter == total_subs) begin
                    $display("Cycle %d VecAddInt %d: Mode == 0, Transitioning to Clean up 1", clk_counter, srcApp);
					// we're done
                    next_state = CLEAN_UP1;
					// save the end cycle
					end_cycle_we = 1'b1;
                    // reset the resp counter to 0
                    reset_resp_counter = 1'b1;
                end else begin
					if (clk_counter % 100 == 0) begin
						$display("Cycle %d VecAddInt %d: Staying in awaiting response", clk_counter, srcApp);
					end
                    // Requests are being dequeued in a different piece of logic
                    next_state = AWAIT_RESP;
                end
            end
            CLEAN_UP1: begin
                if (enough_sr_resp_credits) begin
                    $display("Cycle %d VecAddInt %d: Clean up 1", clk_counter, srcApp);
                    softreg_resp = '{valid: 1'b1, data: start_cycle};
                    decr_read_resp_credit_cnt = 1'b1;
                    next_state = CLEAN_UP2;
                end else begin
					if (clk_counter % 100 == 0) begin
						$display("Cycle %d VecAddInt %d: Staying in Clean up 1, no resp credits (%d)", clk_counter, srcApp,read_resp_credit_cnt);
					end
                    next_state = CLEAN_UP1;
                end
            end
            CLEAN_UP2: begin
                if (enough_sr_resp_credits) begin
                    $display("Cycle %d VecAddInt %d: Clean up 2", clk_counter, srcApp);
                    softreg_resp = '{valid: 1'b1, data: end_cycle};
                    decr_read_resp_credit_cnt = 1'b1;
                    next_state = IDLE;
                    $display("Cycle %d VecAddInt %d: DONE", clk_counter, srcApp);
                end else begin
					if (clk_counter % 100 == 0) begin
						$display("Cycle %d VecAddInt: Staying in Clean up 2, no resp credits (%d)", clk_counter, read_resp_credit_cnt);
					end
                    next_state = CLEAN_UP2;
                end
            end
            default : begin
                next_state = current_state;
            end
        endcase
    end

    //////////////////////////////////
    ///////// Vector Add Logic
    //////////////////////////////////
    // Issue reads, Accept values from memory, add them, and output write them back

    // Request queues for vectors
    wire             mem_readQ_empty[1:0];
    wire             mem_readQ_full[1:0];
    logic            mem_readQ_enq[1:0];
    logic            mem_readQ_deq[1:0];
    AMIRequest       mem_readQ_in[1:0];
    AMIRequest       mem_readQ_out[1:0];

    SoftFIFO
    #(
        .WIDTH					($bits(AMIRequest)),
        .LOG_DEPTH				(8),
    )
    vector_A_req_Q
    (
        .clock					(clk),
        .reset_n				(~rst),
        .wrreq					(mem_readQ_enq[0]),
        .data                   (mem_readQ_in[0]),
        .full                   (mem_readQ_full[0]),
        .q                      (mem_readQ_out[0]),
        .empty                  (mem_readQ_empty[0]),
        .rdreq                  (mem_readQ_deq[0])
    );

    SoftFIFO
    #(
        .WIDTH					($bits(AMIRequest)),
        .LOG_DEPTH				(8),
    )
    vector_B_req_Q
    (
        .clock					(clk),
        .reset_n				(~rst),
        .wrreq					(mem_readQ_enq[1]),
        .data                   (mem_readQ_in[1]),
        .full                   (mem_readQ_full[1]),
        .q                      (mem_readQ_out[1]),
        .empty                  (mem_readQ_empty[1]),
        .rdreq                  (mem_readQ_deq[1])
    );
    
    // Input queues for vectors
    wire             mem_data_inQ_empty[1:0];
    wire             mem_data_inQ_full[1:0];
    logic            mem_data_inQ_enq[1:0];
    logic            mem_data_inQ_deq[1:0];
    logic[511:0]     mem_data_inQ_in[1:0];
    logic[511:0]     mem_data_inQ_out[1:0];

    SoftFIFO
    #(
        .WIDTH					(512),
        .LOG_DEPTH				(8)
    )
    vector_A_Q
    (
        .clock					(clk),
        .reset_n				(~rst),
        .wrreq					(mem_data_inQ_enq[0]),
        .data                   (mem_data_inQ_in[0]),
        .full                   (mem_data_inQ_full[0]),
        .q                      (mem_data_inQ_out[0]),
        .empty                  (mem_data_inQ_empty[0]),
        .rdreq                  (mem_data_inQ_deq[0])
    );

    SoftFIFO
    #(
        .WIDTH					(512),
        .LOG_DEPTH				(8)
    )
    vector_B_Q
    (
        .clock					(clk),
        .reset_n				(~rst),
        .wrreq					(mem_data_inQ_enq[1]),
        .data                   (mem_data_inQ_in[1]),
        .full                   (mem_data_inQ_full[1]),
        .q                      (mem_data_inQ_out[1]),
        .empty                  (mem_data_inQ_empty[1]),
        .rdreq                  (mem_data_inQ_deq[1])
    );

    // Output queue for vector results
    wire             mem_data_outQ_empty;
    wire             mem_data_outQ_full;
    logic            mem_data_outQ_enq;
    logic            mem_data_outQ_deq;
    logic[511:0]     mem_data_outQ_in;
    logic[511:0]     mem_data_outQ_out;

    SoftFIFO
    #(
        .WIDTH					(512),
        .LOG_DEPTH				(8)
    )
    vector_C_Q
    (
        .clock					(clk),
        .reset_n				(~rst),
        .wrreq					(mem_data_outQ_enq),
        .data                   (mem_data_outQ_in),
        .full                   (mem_data_outQ_full),
        .q                      (mem_data_outQ_out),
        .empty                  (mem_data_outQ_empty),
        .rdreq                  (mem_data_outQ_deq)
    );

    // Generate Read Requests

    // Accept read response data
    assign mem_data_inQ_in[0] = mem_resps[0].data;
    assign mem_data_inQ_in[1] = mem_resps[1].data;

    always_comb begin
        mem_data_inQ_enq[0] = 1'b0;
        mem_data_inQ_enq[1] = 1'b0;
        mem_resp_grants[0]  = 1'b0;
        mem_resp_grants[1]  = 1'b0;
    
        if (mem_resps[0].valid && !(mem_data_inQ_full[0])) begin 
            mem_resp_grants[0] = 1'b1;
            mem_data_inQ_enq[0] = 1'b1;
        end

        if (mem_resps[1].valid && !(mem_data_inQ_full[1])) begin 
            mem_resp_grants[1] = 1'b1;
            mem_data_inQ_enq[1] = 1'b1;
        end
        
    end

    // Add and append to vector C
    // Register this if it is a timing issue
    genvar lane_id;
    generate 
        for (lane_id = 0; lane_id < 16; lane_id = lane_id + 1) begin : gen_vec_lane
            assign mem_data_outQ_in[((32*lane_id))+31:(32*lane_id)] = mem_data_inQ_out[0][((32*lane_id))+31:(32*lane_id)] + mem_data_inQ_out[1][((32*lane_id))+31:(32*lane_id)];
        end
    endgenerate

    // Save result of vector add if it was valid and there is room
    always_comb begin
        mem_data_inQ_deq[0] = 1'b0;
        mem_data_inQ_deq[1] = 1'b0;
        mem_data_outQ_enq   = 1'b0;
        if ((!mem_data_outQ_full)  && (!mem_data_inQ_empty[0]) && (!mem_data_inQ_empty[1])) begin
            mem_data_inQ_deq[0] = 1'b1;
            mem_data_inQ_deq[1] = 1'b1;
            mem_data_outQ_enq   = 1'b1;
        end
    end

    // Generate Write Requests
    logic memory_write_issued;

    assign current_write_addr_we = memory_write_issued;

    always_comb begin
        current_write_addr = current_write_addr;
        if (current_write_addr_init_val_we) begin
            current_write_addr = current_write_addr_init_val;
        end else if (current_write_addr_we) begin
            current_write_addr = current_write_addr + 64;
        end
    end

    logic last_port_used;   
    AMIRequest write_mem_req;
 
    always_comb begin
        mem_readQ_deq[0]  = 1'b0;
        mem_readQ_deq[1]  = 1'b0;
        mem_data_outQ_deq = 1'b0;
        mem_reqs[0] = 0;
        mem_reqs[1] = 0;
        memory_write_issued = 1'b0;
        write_mem_req.valid = 1'b0;
        write_mem_req.isWrite = 1'b1;
        write_mem_req.data = mem_data_outQ_out;
        wirte_mem_req.addr = current_write_addr;
        write_mem_req.size = 64;
        if (rst) begin
            last_port_used = 1'b0;
        else begin
            // mem_req_grants
            // Writes have priority, as it takes 2 reads to generate 1 write
            // prioritizes reads would cause us to deadlock
            if (!mem_data_outQ_empty) begin
                // Handle muxing of writes
                write_mem_req.valid = 1'b1;
                if (mem_readQ_empty[0]) begin
                    // Port 0 is available
                    mem_reqs[0] = write_mem_req;
                    if (mem_req_grants[0]) begin
                        mem_data_outQ_deq = 1'b1;
                        memory_write_issued = 1'b1;
                        
                    end
                    // See if port 1 got used
                    if (!mem_readQ_empty[1]) begin
                        mem_reqs[1] = mem_readQ_out[0];    
                        if (mem_req_grants[1]) begin
                            mem_readQ_deq[1];
                        end
                    end
                end else if (mem_readQ_empty[1]) begin
                    // Port 1 is available
                    mem_reqs[1] = write_mem_req;
                    if (mem_req_grants[1]) begin
                        mem_data_outQ_deq = 1'b1;
                        memory_write_issued = 1'b1;
                        
                    end
                    // See if port 0 got used
                    if (!mem_readQ_empty[0]) begin
                        mem_reqs[0] = mem_readQ_out[0];    
                        if (mem_req_grants[0]) begin
                            mem_readQ_deq[0];
                        end
                    end
                end else begin
                    // both ports needed
                end
            end else begin
                // Only handle reads, no pending writes
                if (!mem_readQ_empty[0]) begin
                    mem_reqs[0] = mem_readQ_out[0];    
                    if (mem_req_grants[0]) begin
                        mem_readQ_deq[0];
                    end
                end
                if (!mem_readQ_empty[1]) begin
                    mem_reqs[1] = mem_readQ_out[1];    
                    if (mem_req_grants[1]) begin
                        mem_readQ_deq[1];
                    end
                end
            end
        end
    end

endmodule

