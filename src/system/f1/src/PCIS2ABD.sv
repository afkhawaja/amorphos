/*

Handles PCI-e transactions over AXI4 mastered from the host to the FPGA
ABD stands for AmorphOS Bulk Data

PCIS corresponds to BAR4

128GiB (0 to 0x1F-FFFF-FFFF)

Bottom 127 GiB usable by PCIS, upper 1 GiB reserved

Everything is aligned to a 512 bit boundary (64 byte), so the bottom 6 bits are 0, ( addr[5:0] == 0 )

Written by Ahmed Khawaja

*/

import AMITypes::*;
import AOSF1Types::*;

module PCIS2ABD#(parameter NUM_APPS = 1)(

    // General Signals
    input clk,
    input rst,

    // AXI ID
    // 0x20 : PCI Interface
    // 0x00 : XDMA Channel 0
    // 0x01 : XDMA Channel 1
    // 0x02 : XDMA Channel 2
    // 0x03 : XDMA Channel 3
    // NOTE: XDMA is currently not used

    // Write Address channel
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
    
    // CL DMA Full Signals
    // NOTE: I think this is only for XDMA
    output logic   cl_sh_dma_wr_full, // Resources low for dma writes  (DMA_PCIS AXI ID: 0x00-0x03)
    output logic   cl_sh_dma_rd_full,  // Resources low for dma reads   (DMA_PCIS AXI ID: 0x00-0x03)

    // Interface to AmorphOS
    
);

////////////////////////////////
//////// Write Path
////////////////////////////////

// Signals to the rest of AmorphOS

logic write_accept_packet;
logic write_packet_valid;
ABDInternalPacket write_packet;

// Instantiate Write Path
 PCIS2ABD_WrPath
 PCIS2ABD_WrPath_Main(

    // General Signals
    .clk(clk),
    .rst(rst),
 
    // Write Address channel
    .sh_cl_dma_pcis_awid(sh_cl_dma_pcis_awid),
    .sh_cl_dma_pcis_awaddr(sh_cl_dma_pcis_awaddr),
    .sh_cl_dma_pcis_awlen(sh_cl_dma_pcis_awlen),
    .sh_cl_dma_pcis_awsize(sh_cl_dma_pcis_awsize),
    .sh_cl_dma_pcis_awvalid(sh_cl_dma_pcis_awvalid),
    .cl_sh_dma_pcis_awready(cl_sh_dma_pcis_awready),

    // Write Data Channel
    .sh_cl_dma_pcis_wdata(sh_cl_dma_pcis_wdata),
    .sh_cl_dma_pcis_wstrb(sh_cl_dma_pcis_wstrb),
    .sh_cl_dma_pcis_wlast(sh_cl_dma_pcis_wlast),
    .sh_cl_dma_pcis_wvalid(sh_cl_dma_pcis_wvalid),
    .cl_sh_dma_pcis_wready(cl_sh_dma_pcis_wready),

    // Write Response Channel
    .cl_sh_dma_pcis_bid(cl_sh_dma_pcis_bid),
    .cl_sh_dma_pcis_bresp(cl_sh_dma_pcis_bresp),
    .cl_sh_dma_pcis_bvalid(cl_sh_dma_pcis_bvalid),
    .sh_cl_dma_pcis_bready(sh_cl_dma_pcis_bready),

    // connection to the rest of AmorphOS
    .accept_packet(write_accept_packet),
    .packet_valid(write_packet_valid),
    .write_packet(write_packet)

);

////////////////////////////////
//////// Read Path
////////////////////////////////

// Signals to the rest of AmorphOS

logic read_accept_packet;
logic read_packet_valid;
ABDInternalPacket read_packet;

// Instantiate Read Path

PCIS2ABD_RdPath
PCIS2ABD_RdPath_Main
(

    // General Signals
    .clk(clk),
    .rst(rst),

    // Read Address Channel
    .sh_cl_dma_pcis_arid(sh_cl_dma_pcis_arid),
    .sh_cl_dma_pcis_araddr(sh_cl_dma_pcis_araddr),
    .sh_cl_dma_pcis_arlen(sh_cl_dma_pcis_arlen),
    .sh_cl_dma_pcis_arsize(sh_cl_dma_pcis_arsize),
    .sh_cl_dma_pcis_arvalid(sh_cl_dma_pcis_arvalid),
    .cl_sh_dma_pcis_arready(cl_sh_dma_pcis_arready),

    // Read Data Channel
    .cl_sh_dma_pcis_rid(cl_sh_dma_pcis_rid),
    .cl_sh_dma_pcis_rdata(cl_sh_dma_pcis_rdata),
    .cl_sh_dma_pcis_rresp(cl_sh_dma_pcis_rresp),
    .cl_sh_dma_pcis_rlast(cl_sh_dma_pcis_rlast),
    .cl_sh_dma_pcis_rvalid(cl_sh_dma_pcis_rvalid),
    .sh_cl_dma_pcis_rready(sh_cl_dma_pcis_rready),

    // Connection to the rest of AmorphOS
    .accept_packet(read_accept_packet),
    .packet_valid(read_packet_valid),
    .read_packet(read_packet)

);


endmodule
