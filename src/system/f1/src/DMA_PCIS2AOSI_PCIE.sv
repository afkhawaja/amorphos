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

module DMA_PCIS2AOSI_PCIE(
    // general signals
    input clk,
    input rst,
    // Accept F1 PCI-E packets
    input[511:0] packet_in,
    input        packet_in_valid,
    output logic packet_in_grant,
    // Convert to AmorphOS sized "pci-e" packets
    output PCIEPacket packet_to_aosi,
    input             aosi_full // If asserted, system can't accept a valid packet (don't deque) 
    
);

    // Accept the 512-bit packet into queue
    logic big_packet_FIFO_enq;
    logic big_packet_FIFO_deq;
    wire  big_packet_FIFO_full;
    wire  big_packet_FIFO_empty;
    wire[511:0] big_packet_FIFO_head;

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
        .data                   (packet_in),
        .full                   (big_packet_FIFO_full),
        .q                      (big_packet_FIFO_head),
        .empty                  (big_packet_FIFO_empty),
        .rdreq                  (big_packet_FIFO_deq)
    );    

    assign big_packet_FIFO_enq = packet_in_valid && !big_packet_FIFO_full;
    assign packet_in_grant = big_packet_FIFO_enq;
    
    // PCIEPacket queue
    logic small_packet_FIFO_enq;
    logic small_packet_FIFO_deq;
    wire  small_packet_FIFO_full;
    wire  small_packet_FIFO_empty;
    PCIEPacket small_packet_FIFO_head;
    PCIEPacket small_packet_in;
    
    HullFIFO
    #(
        .TYPE                   (F1_small_packet_in_FIFO_Type),
        .WIDTH                  ($bits(PCIEPacket)),
        .LOG_DEPTH              (F1_small_packet_in_FIFO_Depth)
    )
    small_packet_in_FIFO
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (small_packet_FIFO_enq),
        .data                   (small_packet_in),
        .full                   (small_packet_FIFO_full),
        .q                      (small_packet_FIFO_head),
        .empty                  (small_packet_FIFO_empty),
        .rdreq                  (small_packet_FIFO_deq)
    );        

    // Dequeue from the big packet queue to the small packet queue
    assign big_packet_FIFO_deq   = !big_packet_FIFO_empty && !small_packet_FIFO_full;    
    
    // Input end of the small_packetFIFO
    assign small_packet_FIFO_enq = big_packet_FIFO_deq;
    assign small_packet_in.valid = 1'b1;
    assign small_packet_in.data  = big_packet_FIFO_head[127:0];
    assign small_packet_in.slot  = big_packet_FIFO_head[399:384];
    assign small_packet_in.pad   = 4'b0;
    assign small_packet_in.last  = big_packet_FIFO_head[416];

    // Output end of the small_packetFIFO
    assign small_packet_FIFO_deq = !aosi_full && !small_packet_FIFO_empty && small_packet_FIFO_head.valid; // valid might not be needed
    assign packet_to_aosi.valid = small_packet_FIFO_head.valid && !small_packet_FIFO_empty;
    assign packet_to_aosi.data  = small_packet_FIFO_head.data;
    assign packet_to_aosi.slot  = small_packet_FIFO_head.slot;
    assign packet_to_aosi.pad   = small_packet_FIFO_head.pad;
    assign packet_to_aosi.last  = small_packet_FIFO_head.last;

    
endmodule
