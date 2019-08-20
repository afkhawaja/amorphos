/*

    NOTE: OS Must ensure transactions are 512-bit (64-byte aligned)
    Handles inbound PCI-E data over AXI-4

*/

import AMITypes::*;

module DMA_PCIS_CONTROLLER#(parameter ENABLE_WRSTRB_FIXUP)
(
    
    // General Signals
    input               clk,
    input               rst,

    // Write Address 
    input[5:0]   sh_cl_dma_pcis_awid,
    input[63:0]  sh_cl_dma_pcis_awaddr,
    input[7:0]   sh_cl_dma_pcis_awlen,  // burst length, number of transfers in a burst (+1 to this value)
    input[2:0]   sh_cl_dma_pcis_awsize, // burst size, size of each transfer in the burst (in bytes)
    input        sh_cl_dma_pcis_awvalid,
    output logic cl_sh_dma_pcis_awready,

    // Write Data
    input[511:0] sh_cl_dma_pcis_wdata,
    input[63:0]  sh_cl_dma_pcis_wstrb,
    input        sh_cl_dma_pcis_wlast,
    input        sh_cl_dma_pcis_wvalid,
    output logic cl_sh_dma_pcis_wready,

    // Write Response
    output logic[5:0] cl_sh_dma_pcis_bid,
    output logic[1:0] cl_sh_dma_pcis_bresp,
    output logic      cl_sh_dma_pcis_bvalid, // write response is valid
    input             sh_cl_dma_pcis_bready,

    // Read Address
    input[5:0]   sh_cl_dma_pcis_arid,
    input[63:0]  sh_cl_dma_pcis_araddr,
    input[7:0]   sh_cl_dma_pcis_arlen,
    input[2:0]   sh_cl_dma_pcis_arsize,
    input        sh_cl_dma_pcis_arvalid,
    output logic cl_sh_dma_pcis_arready,

    // Read Data
    output logic[5:0]   cl_sh_dma_pcis_rid,
    output logic[511:0] cl_sh_dma_pcis_rdata,
    output logic[1:0]   cl_sh_dma_pcis_rresp,
    output logic        cl_sh_dma_pcis_rlast,
    output logic        cl_sh_dma_pcis_rvalid,
    input               sh_cl_dma_pcis_rready,
    
    // Interface to the rest of the AmorphOS system
    output logic[511:0] shell_pcie_packet,
    output logic        shell_pcie_packet_valid,
    input  logic        shell_pice_packet_grant

);
    ///////////////////////
    // Read Interface
    ///////////////////////

    // Disable accepting of read requests and outputting read data
    assign cl_sh_dma_pcis_arready = 1'b0;
    assign cl_sh_dma_pcis_rvalid  = 1'b0;
    
    ///////////////////////
    // Write Interface
    ///////////////////////

    // Transaction starts when 
    logic transaction_starting;
    assign transaction_starting = sh_cl_dma_pcis_awvalid && cl_sh_dma_pcis_awready;
    // Need to register the awid to send back as the bid in the write response
    reg[5:0]  current_bid_reg;
    logic[5:] new_bid_reg_value;
    
    // Accept them and store them in a FIFO (queue/buffer), breaking them down is done later
    // FIFO signals
    logic pcis_in_FIFO_enq;
    logic pcis_in_FIFO_deq;
    wire  pcis_in_FIFO_full;
    wire  pcis_in_FIFO_empty;
    wire[511:0] pcis_in_FIFO_head;

    HullFIFO
    #(
        .TYPE                   (F1_PCIS_IN_FIFO_Type),
        .WIDTH                  (512),
        .LOG_DEPTH              (F1_PCIS_IN_FIFO_Depth)
    )
    pcis_inFIFO
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (pcis_in_FIFO_enq),
        .data                   (sh_cl_dma_pcis_wdata),
        .full                   (pcis_in_FIFO_full),
        .q                      (pcis_in_FIFO_head),
        .empty                  (pcis_in_FIFO_empty),
        .rdreq                  (pcis_in_FIFO_deq)
    );
    
    // Keep track of the write strobes to do any fix up later
    logic wrstrb_in_FIFO_enq;
    logic wrstrb_in_FIFO_deq;
    wire  wrstrb_in_FIFO_full;
    wire  wrstrb_in_FIFO_empty;
    wire[63:0] wrstrb_in_FIFO_head;    

    HullFIFO
    #(
        .TYPE                   (F1_PCIS_WRSTRB_IN_FIFO_Type),
        .WIDTH                  (64),
        .LOG_DEPTH              (F1_PCIS_WRSTRB_IN_FIFO_Depth)
    )
    wrstrb_inFIFO
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (wrstrb_in_FIFO_enq),
        .data                   (sh_cl_dma_pcis_wstrb),
        .full                   (wrstrb_in_FIFO_full),
        .q                      (wrstrb_in_FIFO_head),
        .empty                  (wrstrb_in_FIFO_empty),
        .rdreq                  (wrstrb_in_FIFO_deq)
    );    

    // Response FIFO to track B-resps we need to give
    // After we see wlast asserted, we can return bvalid
    // Valis of bresp
    // 0b00  == OKAY
    // 0b10  == SLVERR
    logic write_resp_out_FIFO_enq;
    logic write_resp_out_FIFO_deq;
    wire  write_resp_out_FIFO_full;
    wire  write_resp_out_FIFO_empty;
    wire[7:0] write_resp_out_FIFO_head;    // 2 for the resp, 6 for the bid
    logic[7:0] write_resp_FIFO_value_in;

    HullFIFO
    #(
        .TYPE                   (F1_PCIS_WR_RESP_OUT_FIFO_Type),
        .WIDTH                  (2+6), // 2 for the resp, 6 for the bid
        .LOG_DEPTH              (F1_PCIS_WR_RESP_OUT_FIFO_Depth)
    )
    write_resp_outFIFO
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (write_resp_out_FIFO_enq),
        .data                   (write_resp_FIFO_value_in),
        .full                   (write_resp_out_FIFO_full),
        .q                      (write_resp_out_FIFO_head),
        .empty                  (write_resp_out_FIFO_empty),
        .rdreq                  (write_resp_out_FIFO_deq)
    );    

    // A response is generated when we see wlast signaled, meaning a burst has completed
    assign write_resp_out_FIFO_enq  = sh_cl_dma_pcis_wvalid && sh_cl_dma_pcis_wlast && !write_resp_out_FIFO_full && pcis_in_FIFO_enq;
    assign write_resp_FIFO_value_in[7:6] = 2'b00; // OKAY
    // Need special logic if a transaction is starting AND write data is being accepted in the same cycle
    // Effectively need to bypass the current_bid_reg
    // TODO: Double check this, might not work if the write address stream is out of sync with the write data one
    // Currently all the id's should be the same....
    assign write_resp_FIFO_value_in[5:0] = (transaction_starting && pcis_in_FIFO_enq) ? sh_cl_dma_pcis_awid : current_bid_reg;
    assign cl_sh_dma_pcis_bresp = write_resp_out_FIFO_head[7:6];
    assign cl_sh_dma_pcis_bid   = write_resp_out_FIFO_head[5:0];
    assign cl_sh_dma_pcis_bvalid   = !write_resp_out_FIFO_empty;
    assign write_resp_out_FIFO_deq = cl_sh_dma_pcis_bvalid && sh_cl_dma_pcis_bready; // deque the response if it was accepted by the shell

    // Accept data into the pcis_inFIFO
    // Accept data if Q isn't full and write data channel is signaling valid data
    assign cl_sh_dma_pcis_wready = !pcis_in_FIFO_full && !wrstrb_in_FIFO_full && !write_resp_out_FIFO_full;
    assign pcis_in_FIFO_enq      = cl_sh_dma_pcis_wready && sh_cl_dma_pcis_wvalid;
    assign wrstrb_in_FIFO_enq    = pcis_in_FIFO_enq;

    // Response id register
    always @(posedge clk) begin
        current_bid_reg <= new_bid_reg_value;
    end
    assign new_bid_reg_value = (transaction_starting ? sh_cl_dma_pcis_awid : current_bid_reg);

    // Write address signals
    // Signal we can accept a new write request if all the queues are NOT full
    assign cl_sh_dma_pcis_awready = !pcis_in_FIFO_full && !wrstrb_in_FIFO_full && !write_resp_out_FIFO_full;
    // Currently ignoring the address, len, size signals

    // Logic to turn partial packets into unified packets due to write strobes
    logic fixup_packet_in_grant;
    wire[511:0] fixup_packet_out;
    wire fixup_packet_out_valid;
    logic fixup_packet_out_grant;
    
    generate
        if (ENABLE_WRSTRB_FIXUP) begin : wrstrb_fixup_enabled
            DMA_PCIS_WRSTRB_FIXUP
            dma_pcis_wrstrb_fixup
            (
                // General Signals
                .clk(clk),
                .rst(rst),
                // Accept possibly fragment packets
                .packet_in(pcis_in_FIFO_head),
                .wrstrb_in(wrstrb_in_FIFO_head),
                .packet_in_valid(!pcis_in_FIFO_empty),
                .packet_in_grant(fixup_packet_in_grant),
                // Output unified packets
                .packet_out(fixup_packet_out),
                .packet_out_valid(fixup_packet_out_valid),
                .packet_out_grant(fixup_packet_out_grant)
            );
            assign pcis_in_FIFO_deq   = fixup_packet_in_grant;
            assign wrstrb_in_FIFO_deq = fixup_packet_in_grant;
            assign shell_pcie_packet  = fixup_packet_out;
            assign shell_pcie_packet_valid = fixup_packet_out_valid;
            assign fixup_packet_out_grant  = shell_pice_packet_grant;
        end else begin : wrstrb_fixup_disabled
            assign pcis_in_FIFO_deq   = !pcis_in_FIFO_empty && shell_pice_packet_grant;
            assign wrstrb_in_FIFO_deq = !pcis_in_FIFO_empty && shell_pice_packet_grant;        
            assign shell_pcie_packet = pcis_in_FIFO_head;
            assign shell_pcie_packet_valid = !pcis_in_FIFO_empty;
        end
    endgenerate
    
endmodule

