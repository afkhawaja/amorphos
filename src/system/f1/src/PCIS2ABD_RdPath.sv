/*

Written by Ahmed Khawaja

*/

import AMITypes::*;
import AOSF1Types::*;

module PCIS2ABD_RdPath(
    
    // General Signals
    input clk,
    input rst,

    // Read Address Channel
    input[5:0]   sh_cl_dma_pcis_arid,    // read address id for the read address group
    input[63:0]  sh_cl_dma_pcis_araddr,  // address of first transfer in a read burst transaction
    input[7:0]   sh_cl_dma_pcis_arlen,   // burst length, number of transfers in a burst (+1 to this value)
    input[2:0]   sh_cl_dma_pcis_arsize,  // burst size, size of each transfer in the burst
    input        sh_cl_dma_pcis_arvalid, // read address valid, signals the read address/control info is valid
    output logic cl_sh_dma_pcis_arready, // read address ready, signals the slave is ready to accept an address/control info

    // Read Data Channel
    output logic[5:0]   cl_sh_dma_pcis_rid,     // read id tag
    output logic[511:0] cl_sh_dma_pcis_rdata,   // read data
    output logic[1:0]   cl_sh_dma_pcis_rresp,   // status of the read transfer
    output logic        cl_sh_dma_pcis_rlast,   // indicates last transfer in a read burst
    output logic        cl_sh_dma_pcis_rvalid,  // indicates the read data is valid
    input               sh_cl_dma_pcis_rready,  // indicates the master (the host) can accept read data/response info

    // Connection to the rest of AmorphOS
    // Read Response packets
    output  accept_read_resp_packet,
    input   read_resp_packet_valid,
    input   ABDInternalPacket read_resp_packet,
    // Read Request packets
    output ABDReadReq read_req_packet,
    output read_req_packet_valid,
    input  read_req_accept

);

    // Read state
    logic[63:0] current_read_address;
    logic[63:0] new_read_address;
    logic       read_address_we;

    logic[8:0] current_read_reqs_left;
    logic[8:0] new_read_reqs_left;
    logic      read_reqs_left_we;

    logic      current_rd_packetization_in_progress;
    logic      new_rd_packetization_in_progress;
    logic      rd_packetization_in_progress_we;
    
    // Read request buffer
    logic rd_req_FIFO_enq;
    logic rd_req_FIFO_deq;
    logic rd_req_FIFO_full;
    logic rd_req_FIFO_empty;
    ABDReadReq rd_req_FIFO_head;
    ABDReadReq rd_req_FIFO_input;

    // Read response ID buffer
    logic rd_id_FIFO_enq;
    logic rd_id_FIFO_deq;
    logic rd_id_FIFO_full;
    logic rd_id_FIFO_empty;
    ABDReadRespID rd_id_FIFO_head;
    ABDReadRespID rd_id_FIFO_input;
    
    assign rd_id_FIFO_input.valid = rd_id_FIFO_enq
    assign rd_id_FIFO_input.arid  = sh_cl_dma_pcis_arid;
    assign rd_id_FIFO_input.arlen = sh_cl_dma_pcis_arlen + 1;
    
    // Registers
    always@(posedge clk) begin
        if (rst) begin
            current_read_address <= {64{1'b0}};
        end else if (read_address_we) begin
            current_read_address <= new_read_address;
        end
    end
    
    always@(posedge clk) begin
        if (rst) begin
            current_read_reqs_left <= {8{1'b0}};
        end else if (read_reqs_left_we) begin
            current_read_reqs_left <= new_read_reqs_left;
        end
    end

    always@(posedge clk) begin
        if (rst) begin
            rd_packetization_in_progress <= 1'b0;
        end else if (rd_packetization_in_progress_we) begin
            rd_packetization_in_progress <= new_rd_packetization_in_progress;
        end
    end


    always_comb begin
        new_read_address   = current_read_address;
        new_read_reqs_left = current_read_reqs_left;
        new_rd_packetization_in_progress = current_rd_packetization_in_progress;
        read_address_we = 1'b0;
        read_reqs_left_we = 1'b0;
        rd_packetization_in_progress_we = 1'b0;
        rd_id_FIFO_enq  = 1'b0;
        rd_req_FIFO_enq = 1'b0;
         
        // See if we can accept a new read request
        // NOTE: Assuming we don't have to send the read data back before signalling we can accept another read
        if (cl_sh_dma_pcis_arready && sh_cl_dma_pcis_arvalid) begin 
            rd_packetization_in_progress_we  = 1'b1;
            new_rd_packetization_in_progress = 1'b1;
            read_address_we    = 1'b1;
            new_read_address   = sh_cl_dma_pcis_araddr;
            new_read_reqs_left = sh_cl_dma_pcis_arlen + 1;
            read_reqs_left_we  = 1'b1;
            rd_id_FIFO_enq     = 1'b1;
        // Continue to break the AXI request into smaller internal requests
        end else if (current_rd_packetization_in_progress) begin
            // We are going to enque a new internal request
            if (!rd_req_FIFO_full) begin
                rd_req_FIFO_enq = 1'b1;
                // Check if this is the last internal request we need to generate
                if (current_read_reqs_left == 8'b0000_0001) begin
                    new_rd_packetization_in_progress = 1'b0;
                    rd_packetization_in_progress_we  = 1'b1;
                    read_address_we = 1'b1;
                    new_read_address = 0; // for debug
                    new_reads_reqs_left = 0;
                    read_reqs_left_we = 1'b1;
                end else begin
                    new_read_address = current_read_address + 64;
                    read_address_we  = 1'b1;
                    new_reads_reqs_left = current_read_reqs_left - 1;
                    read_reqs_left_we = 1'b1;

                end
            end
            // Else we do nothing
        end
    
    end

    // Need room in the arid buffer
    assign cl_sh_dma_pcis_arready = !current_rd_packetization_in_progress && !rd_id_FIFO_full;

    /////////////////////////////////////
    // Read response interface over AXI4
    /////////////////////////////////////

    HullFIFO
    #(
        .TYPE                   (F1_PCIS2ABD_RdPath_RdRespIDFIFO_Type),
        .WIDTH                  ($bits(ABDReadRespID)),
        .LOG_DEPTH              (F1_PCIS2ABD_RdPath_RdRespIDFIFO_Depth)
    )
    rdRespIDBuffer
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (rd_id_FIFO_enq),
        .data                   (rd_id_FIFO_input),
        .full                   (rd_id_FIFO_full),
        .q                      (rd_id_FIFO_head),
        .empty                  (rd_id_FIFO_empty),
        .rdreq                  (rd_id_FIFO_deq)
    );

    //////////////////////////////////////
    // Read Request interface to AmorphOS
    //////////////////////////////////////

    HullFIFO
    #(
        .TYPE                   (F1_PCIS2ABD_RdPath_RdReqFIFO_Type),
        .WIDTH                  ($bits(ABDReadReq)),
        .LOG_DEPTH              (F1_PCIS2ABD_RdPath_RdReqFIFO_Depth)
    )
    rdReadReqBuffer
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (rd_req_FIFO_enq),
        .data                   (rd_req_FIFO_input),
        .full                   (rd_req_FIFO_full),
        .q                      (rd_req_FIFO_head),
        .empty                  (rd_req_FIFO_empty),
        .rdreq                  (rd_req_FIFO_deq)
    );

    assign rd_req_FIFO_input.valid  = rd_req_FIFO_enq;
    //assign rd_req_FIFO_input.app_id = 0; // Currently don't care
    assign rd_req_FIFO_input.addr   = current_read_address;
    
    assign read_req_packet_valid = !rd_req_FIFO_empty && rd_req_FIFO_head.valid;
    assign read_req_packet       = rd_req_FIFO_head;
    assign rd_req_FIFO_deq       = read_req_accept;


endmodule;
