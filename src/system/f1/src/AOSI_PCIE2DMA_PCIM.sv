
/*

    Converts F1 PCI-E packets to AmorphOS sized packets

    // Incoming PCI-E packet format
    // NOTE: Currently only support Packet 0 being valid
  
    Bits Range NumBits Name
    0   - 127  128     AmorphOS Packet 0 data
    127 - 255  128     AmorphOS Packet 1 data
    256 - 383  128     AmorphOS Packet 2 data
    384 - 399  16      AmorphOS Packet Slot ID (shared for all 3 incoming packets)
    400 - 407  8       Num valid packets in this transaction
    408 - 415  8       Valid bit vector for the 3 packets
    416 - 423  8       Last bit vector for the  3 packets
    424 - 511  88      Unused
    0   - 511  512     Total
    
*/


import AMITypes::*;

module AOSI_PCIE2DMA_PCIM(
    // general signals
    input clk,
    input rst,
    // Convert from AmorphOS sized "pci-e" packets
    input PCIEPacket       packet_from_aosi,
    output logic           packet_from_aosi_grant,
    // Send out real pci-e packets
    output logic[511:0]    packet_to_pcim,
    output logic           packet_to_pcim_valid,
    input                  packet_to_pcim_grant,
);

    // PCIEPacket queue
    logic small_packet_FIFO_enq;
    logic small_packet_FIFO_deq;
    wire  small_packet_FIFO_full;
    wire  small_packet_FIFO_empty;
    PCIEPacket small_packet_FIFO_head;
    
    HullFIFO
    #(
        .TYPE                   (F1_small_packet_out_FIFO_Type),
        .WIDTH                  ($bits(PCIEPacket)),
        .LOG_DEPTH              (F1_small_packet_out_FIFO_Depth)
    )
    small_packet_out_FIFO
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (small_packet_FIFO_enq),
        .data                   (packet_from_aosi),
        .full                   (small_packet_FIFO_full),
        .q                      (small_packet_FIFO_head),
        .empty                  (small_packet_FIFO_empty),
        .rdreq                  (small_packet_FIFO_deq)
    );    

    assign small_packet_FIFO_enq  = packet_from_aosi.valid && !small_packet_FIFO_full;
    // Interface to AmorphOS
    assign packet_from_aosi_grant = small_packet_FIFO_enq;

    // NOTE: Currently only 1 packet is bundled together for simplicity, can optimize later
    // Accept the 512-bit packet into queue
    logic big_packet_FIFO_enq;
    logic big_packet_FIFO_deq;
    wire  big_packet_FIFO_full;
    wire  big_packet_FIFO_empty;
    wire[511:0]  big_packet_FIFO_head;
    logic[511:0] big_packet_FIFO_in;

    HullFIFO
    #(
        .TYPE                   (F1_big_packet_out_FIFO_Type),
        .WIDTH                  (512),
        .LOG_DEPTH              (F1_big_packet_out_FIFO_Depth)
    )
    big_packet_out_FIFO
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (big_packet_FIFO_enq),
        .data                   (big_packet_FIFO_in),
        .full                   (big_packet_FIFO_full),
        .q                      (big_packet_FIFO_head),
        .empty                  (big_packet_FIFO_empty),
        .rdreq                  (big_packet_FIFO_deq)
    );
    
    // Combine the packet
    assign big_packet_FIFO_in[127:0]   = small_packet_FIFO_head.data;
    assign big_packet_FIFO_in[399:384] = small_packet_FIFO_head.slot;
    assign big_packet_FIFO_in[407:400] = 8'h01; // num valid sub packets
    //408 - 415         Valid bit vector for the 3 packets
    assign big_packet_FIFO_in[408]     = 1'b1; // one packet valid
    assign big_packet_FIFO_in[415:409] = 7'b000_000;
    // 416 - 423        Last bit vector for the  3 packets
    assign big_packet_FIFO_in[416]     = small_packet_FIFO_head.last;
    assign big_packet_FIFO_in[423:417] = 7'b000_0000;
    
    assign big_packet_FIFO_enq = !small_packet_FIFO_empty && !big_packet_FIFO_full && small_packet_FIFO_head.valid; // the valid check might not be needed, remove to optimize
    
    // Interface to PCIM
    assign packet_to_pcim = big_packet_FIFO_head; 
    assign packet_to_pcim_valid = !big_packet_FIFO_empty;
    assign big_packet_FIFO_deq  = packet_to_pcim_valid && packet_to_pcim_grant;
    
    // Cross between them
    assign small_packet_FIFO_deq = big_packet_FIFO_enq;
    
endmodule
