/*

Handles write requests from the host

Written by Ahmed Khawaja

*/

import AMITypes::*;
import AOSF1Types::*;

module PCIS2ABD_WrPath(

    // General Signals
    input clk,
    input rst,

    // Write Address Channel
    input[5:0]   sh_cl_dma_pcis_awid,    // tag for the write address group
    input[63:0]  sh_cl_dma_pcis_awaddr,  // address of first transfer in write burst
    input[7:0]   sh_cl_dma_pcis_awlen,   // number of transfers in a burst (+1 to this value)
    input[2:0]   sh_cl_dma_pcis_awsize,  // size of each transfer in the burst
    input        sh_cl_dma_pcis_awvalid, // write address valid, signals the write address and control info is correct
    output logic cl_sh_dma_pcis_awready,

    // Write Data Channel
    input[511:0] sh_cl_dma_pcis_wdata,   // write data
    input[63:0]  sh_cl_dma_pcis_wstrb,   // write strobes, indicates which byte lanes hold valid data, 1 strobe bit per 8 bits to write
    input        sh_cl_dma_pcis_wlast,   // indicates the last transfer
    input        sh_cl_dma_pcis_wvalid,  // indicates the write data and strobes are valid
    output logic cl_sh_dma_pcis_wready,  // indicates the slave can accept write data

    // Write Response Channel
    output logic[5:0] cl_sh_dma_pcis_bid,    // response id tag
    output logic[1:0] cl_sh_dma_pcis_bresp,  // write response indicating the status of the transaction
    output logic      cl_sh_dma_pcis_bvalid, // indicates the write response is valid
    input             sh_cl_dma_pcis_bready, // indicates the master can accept a write response
    
    // connection to the rest of AmorphOS
    input  accept_packet,
    output packet_valid,
    output ABDInternalPacket write_packet

);

    // Metadata for writes
    // Signals
    logic[63:0] current_write_address;
    logic[63:0] new_write_address;
    logic       write_address_we;

    logic write_in_progress;
    logic new_write_in_progress;
    logic write_in_progress_we;

    logic starting_wr_transaction;
    logic accepted_last_wr_data;

    // Write data buffer
    logic wr_data_FIFO_enq;
    logic wr_data_FIFO_deq;
    wire  wr_data_FIFO_full;
    wire  wr_data_FIFO_empty;
    ABDInternalPacket wr_data_FIFO_head;
    ABDInternalPacket wr_data_input_packet;
    
    // Write id buffer
    logic wr_id_FIFO_enq;
    logic wr_id_FIFO_deq;
    wire  wr_id_FIFO_full;
    wire  wr_id_FIFO_empty;
    logic[5:0] wr_id_FIFO_head;
    logic[5:0] wr_id_input_id;
    
    // Registers
    always@(posedge clk) begin
        if (rst) begin
            current_write_address <= {64{1'b0}};
        end else if (write_address_we) begin
            current_write_address <= new_write_address;
        end
    end

    always@(posedge clk) begin
        if (rst) begin
            write_in_progress <= 1'b0;
        end else if (write_in_progress_we) begin
            write_in_progress <= new_write_in_progress;
        end
    end

    // Write request control signals
    always_comb begin
        // Write enables for registered values
        write_address_we       = 1'b0;
        write_in_progress_we   = 1'b0;
        new_write_address     = current_write_address;
        new_write_in_progress = write_in_progress; 
        cl_sh_dma_pcis_awready = 1'b0;

        if (write_in_progress) begin
            // Write in progress and data was accepted
            if (wr_data_FIFO_enq) begin
                // was it the last write data portion?
                if (accepted_last_wr_data) begin 
                    // Mark write in progress as done
                    write_in_progress_we  = 1'b1;
                    new_write_in_progress = 1'b0;
                    // Reset the address to aid debugging
                    write_address_we  = 1'b1;
                    new_write_address = {64{1'b1}};
                // otherwise increment the address by 64 bytes since we just accepted a chunk
                end else begin
                    write_address_we  = 1'b1;
                    new_write_address = current_write_address + 64;
                end
            end
            // If no write data was enqued, nothing else to be done
        end else begin // no write transaction in progress
            cl_sh_dma_pcis_awready = 1'b1;
            // See if we are starting a new transaction
            if (cl_sh_dma_pcis_awready && sh_cl_dma_pcis_awvalid) begin
                write_in_progress_we  = 1'b1;
                new_write_in_progress = 1'b1;
                write_address_we  = 1'b1;
                new_write_address = sh_cl_dma_pcis_awaddr;
            end
        end

    end

    // Accepted a data packet and it was marked as last
    assign accepted_last_wr_data = sh_cl_dma_pcis_wvalid && cl_sh_dma_pcis_wready && sh_cl_dma_pcis_wlast;
    // If we accept an address on the interface and no transaction was in progress 
    assign starting_wr_transaction = (!write_in_progress) && sh_cl_dma_pcis_awvalid && cl_sh_dma_pcis_awready;
    
    HullFIFO
    #(
        .TYPE                   (F1_PCIS2ABD_WrPath_WrDataFIFO_Type),
        .WIDTH                  ($bits(ABDInternalPacket)),
        .LOG_DEPTH              (F1_PCIS2ABD_WrPath_WrDataFIFO_Depth)
    )
    wrDataBuffer
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (wr_data_FIFO_enq),
        .data                   (wr_data_input_packet),
        .full                   (wr_data_FIFO_full),
        .q                      (wr_data_FIFO_head),
        .empty                  (wr_data_FIFO_empty),
        .rdreq                  (wr_data_FIFO_deq)
    );

    // Leave the write buffer
    logic write_data_FIFO_head_valid; 
    assign write_data_FIFO_head_valid = !wr_data_FIFO_empty && wr_data_FIFO_head.valid;

    assign write_packet.valid = write_data_FIFO_head_valid;
    assign write_packet.addr  = wr_data_FIFO_head.addr;
    assign write_packet.data  = wr_data_FIFO_head.data;

    assign packet_valid = write_data_FIFO_head_valid;
    assign wr_data_FIFO_deq = packet_valid && accept_packet;

    // Assemble the input packet for the write buffer
    assign wr_data_input_packet.valid  = wr_data_FIFO_enq;
    assign wr_data_input_packet.addr   = current_write_address;
    assign wr_data_input_packet.data   = sh_cl_dma_pcis_wdata;
    //assign wr_data_input_packet.app_id = 0; Currently don't care

    assign cl_sh_dma_pcis_wready = write_in_progress && !wr_data_FIFO_full;
    // WREADY and WVALID being asserted in the same clock cycle means we have to accept the write data
    // We only assert WREADY if the write buffer (FIFO) can accept the data, so there is no chance of data loss
    assign wr_data_FIFO_enq      = cl_sh_dma_pcis_wready && sh_cl_dma_pcis_wvalid;

    ////////////////////////////////////
    // Write response logic
    ////////////////////////////////////

    // Per the AXI4 spec: For a write transaction, a single response is signaled for the entire burst, and not for each data transfer within the burst.

    HullFIFO
    #(
        .TYPE                   (F1_PCIS2ABD_WrPath_WrIdFIFO_Type),
        .WIDTH                  (6), // AXI4 ID is 6 bits wide
        .LOG_DEPTH              (F1_PCIS2ABD_WrPath_WrIdFIFO_Depth)
    )
    wrIdBuffer
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (wr_id_FIFO_enq),
        .data                   (wr_id_input_id),
        .full                   (wr_id_FIFO_full),
        .q                      (wr_id_FIFO_head),
        .empty                  (wr_id_FIFO_empty),
        .rdreq                  (wr_id_FIFO_deq)
    );
    
    // Enque the id when the address for the transaction is accepted
    // But only increment the credit count when the last write data is received
    assign wr_id_input_id = sh_cl_dma_pcis_awid;
    assign wr_id_FIFO_enq = starting_wr_transaction;
    assign wr_id_FIFO_deq = cl_sh_dma_pcis_bvalid && sh_cl_dma_pcis_bready;

    // Write Response Credit
    logic[31:0] write_resp_credit_cnt;
    logic[31:0] new_write_resp_credit_cnt;
    logic       decr_write_resp_credit_cnt;
	logic       incr_write_resp_credit_cnt;
    
    logic  enough_resp_credits;
    assign enough_resp_credits = (write_resp_credit_cnt != 32'h0000_0000);
    
    always @(posedge clk) begin 
        if (rst) begin
            write_resp_credit_cnt <= 32'h0000_0000;
        end else begin
            write_resp_credit_cnt <= new_write_resp_credit_cnt;
        end
    end

	always_comb begin
        new_write_resp_credit_cnt = write_resp_credit_cnt;
        if (incr_write_resp_credit_cnt && !decr_write_resp_credit_cnt) begin
			//$display("Cycle %d PCIS2ABD_WrPath Gained response credit", cycle_cntr);
            new_write_resp_credit_cnt = write_resp_credit_cnt + 1;
        end else if (!incr_write_resp_credit_cnt && decr_write_resp_credit_cnt) begin
			//$display("Cycle %d PCIS2ABD_WrPath Lost response credit", cycle_cntr);
            new_write_resp_credit_cnt = write_resp_credit_cnt - 1;
        end else if (incr_write_resp_credit_cnt && decr_write_resp_credit_cnt) begin
			//$display("Cycle %d PCIS2ABD_WrPath Both gained/lost response credit", cycle_cntr);
		end
        // otherwise either gained/lost none (+0) or both (+0)
    end

    // Increase response credits if we enqueued into the write buffer
    assign incr_write_resp_credit_cnt = accepted_last_wr_data;
    // Decrement if a write response was accepted
    assign decr_write_resp_credit_cnt = cl_sh_dma_pcis_bvalid && sh_cl_dma_pcis_bready;
    
    // Wr response interface signals
    assign cl_sh_dma_pcis_bid    = wr_id_FIFO_head;
    assign cl_sh_dma_pcis_bresp  = 2'b00; // OKAY
    assign cl_sh_dma_pcis_bvalid = enough_resp_credits && !wr_id_FIFO_empty; // having an empty queue with available credits would indicate a bug
    
endmodule
