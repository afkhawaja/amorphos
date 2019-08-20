
import AMITypes::*;

module DMA_PCIM_CONTROLLER(
    // general signals
    input clk,
    input rst,
    
    // Write address channel
    output logic[15:0]  cl_sh_pcim_awid,
    output logic[63:0]  cl_sh_pcim_awaddr,
    output logic[7:0]   cl_sh_pcim_awlen,
    output logic[2:0]   cl_sh_pcim_awsize,
    output logic[18:0]  cl_sh_pcim_awuser, // RESERVED (not used)
    output logic        cl_sh_pcim_awvalid,
    input               sh_cl_pcim_awready,

    // Write data channel
    output logic[511:0] cl_sh_pcim_wdata,
    output logic[63:0]  cl_sh_pcim_wstrb,
    output logic        cl_sh_pcim_wlast,
    output logic        cl_sh_pcim_wvalid,
    input               sh_cl_pcim_wready,

	// Write response channel
    input logic[15:0]   sh_cl_pcim_bid,
    input logic[1:0]    sh_cl_pcim_bresp,
    input logic         sh_cl_pcim_bvalid,
    output logic        cl_sh_pcim_bready,

    // Read address channel
    output logic[15:0]  cl_sh_pcim_arid, // Note max 32 outstanding txns are supported, width is larger to allow bits for AXI fabrics
    output logic[63:0]  cl_sh_pcim_araddr,
    output logic[7:0]   cl_sh_pcim_arlen,
    output logic[2:0]   cl_sh_pcim_arsize,
    output logic[18:0]  cl_sh_pcim_aruser, // RESERVED (not used)
    output logic        cl_sh_pcim_arvalid,
    input               sh_cl_pcim_arready,

    // Read data channel
    input[15:0]         sh_cl_pcim_rid,
    input[511:0]        sh_cl_pcim_rdata,
    input[1:0]          sh_cl_pcim_rresp,
    input               sh_cl_pcim_rlast,
    input               sh_cl_pcim_rvalid,
    output logic        cl_sh_pcim_rready,

    // Other shell signals
    input[1:0]          cfg_max_payload,  // Max payload size - 00:128B, 01:256B, 10:512B
    input[2:0]          cfg_max_read_req, // Max read requst size - 000b:128B, 001b:256B, 010b:512B, 011b:1024B 100b-2048B, 101b:4096B

    // Interface to AmorphOS
    input[511:0]        packet_in,
    input               packet_in_valid,
    output              packet_in_grant

);

    // Only doing outbound write transactions, can go ahead and disable the read address and read data channels
    assign cl_sh_pcim_arvalid = 1'b0;
    assign cl_sh_pcim_rready  = 1'b0;

    // Write Response Signals
    assign cl_sh_pcim_bready  = 1'b1; // currently we don't care about the write responses, just need to accept them

	// One problem we have is we have to know beforehand how many packets we want to set out
	
endmodule
