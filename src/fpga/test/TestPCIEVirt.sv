// testbench for the PCIE virtualization
`timescale 1 ns / 1 ns

import ShellTypes::*;
import AMITypes::*;

module testPCIE_virt();

	// General signals
	reg clk;
	reg rst;
	reg     app_enable[AMI_NUM_APPS-1:0];
	
	// Clock
	always #1 clk = !clk;

	// Interface to Host
	// Incoming packets
	PCIEPacket					pcie_packet_in;
	logic						pcie_full_out;
	// Outgoing packets
	PCIEPacket					pcie_packet_out;
	logic						pcie_grant_in;
	// Virtualized interface each application
	PCIEPacket					app_pcie_packet_in[AMI_NUM_APPS-1:0];
	reg 						app_pcie_full_out[AMI_NUM_APPS-1:0];
	PCIEPacket					app_pcie_packet_out[AMI_NUM_APPS-1:0];
	logic						app_pcie_grant_in[AMI_NUM_APPS-1:0];

	// PCI-E virtualization
	AmorphOSPCIE amorphos_pcie
	(
		// User clock and reset
		.clk(clk),
		.rst(rst),
		.app_enable(app_enable),
		// Interface to Host
		// Incoming packets
		.pcie_packet_in(pcie_packet_in),
		.pcie_full_out(pcie_full_out),
		// Outgoing packets
		.pcie_packet_out(pcie_packet_out),
		.pcie_grant_in(pcie_grant_in),
		// Virtualized interface eacg application
		.app_pcie_packet_in(app_pcie_packet_in),
		.app_pcie_full_out(app_pcie_full_out),
		.app_pcie_packet_out(app_pcie_packet_out),
		.app_pcie_grant_in(app_pcie_grant_in)
	);	
	 
	
// Submit requests
initial begin
	$display("Starting AMI Test\n");	
	pcie_packet_in = '{valid: 1'b0, slot: 0, data: 0, last: 0 , pad : 0};

	clk = 1'b0;
	rst = 1'b1;
	#2
	rst = 1'b0;
	for (int i = 0; i < 4; i = i + 1) begin
		pcie_packet_in = '{valid: 1'b1, slot: i, data: i, last: 1'b1 , pad : 0};
		#2
		while(pcie_full_out != 1'b0) begin
			#2
			$display("Packet not accepted (pcie_full_out asserted)");
		end
		$display("Packet accepted! Slot: %d, Data: %h", i, i);
	end
	pcie_packet_in = '{valid: 1'b0, slot: 0, data: 0, last: 0 , pad : 0};
	#2
	for (int i = 0; i < 4; i = i + 1) begin
		pcie_packet_in = '{valid: 1'b1, slot: i+32, data: i+32, last: 1'b1 , pad : 0};
		#2
		while(pcie_full_out != 1'b0) begin
			#2
			$display("Packet not accepted (pcie_full_out asserted)");
		end
		$display("Packet accepted! Slot: %d, Data: %h", i+32, i+32);
	end
	pcie_packet_in = '{valid: 1'b0, slot: 0, data: 0, last: 0 , pad : 0};	
	
end

// Get the responses
initial begin
	#2
	for (int k = 0; k < 8; k = k + 1) begin 
		#2
		while(!pcie_packet_out.valid) begin
			#2
			$display("No Valid packet to accept, waiting for packet %d", k);
		end
		$display("Response packet, Slot: %d Data: %h Pad: %h Last: %h", pcie_packet_out.slot ,pcie_packet_out.data, pcie_packet_out.pad, pcie_packet_out.last);
		pcie_grant_in = 1'b1;
	end
	#2
	pcie_grant_in = 1'b0;
end

// Simulate app as a queue

wire             unified_respQ_empty[1:0];
wire             unified_respQ_full[1:0];
logic            unified_respQ_enq[1:0];
logic            unified_respQ_deq[1:0];
PCIEPacket       unified_respQ_in[1:0];
PCIEPacket       unified_respQ_out[1:0];

SoftFIFO
#(
	.WIDTH					($bits(PCIEPacket)),
	.LOG_DEPTH				(VIRT_PCIE_UNIFIED_RESP_Q_SIZE)
)
unified_pcieRespQ_0
(
	.clock					(clk),
	.reset_n				(~rst),
	.wrreq					(unified_respQ_enq[0]),
	.data                   (unified_respQ_in[0]),
	.full                   (unified_respQ_full[0]),
	.q                      (unified_respQ_out[0]),
	.empty                  (unified_respQ_empty[0]),
	.rdreq                  (unified_respQ_deq[0])
);

SoftFIFO
#(
	.WIDTH					($bits(PCIEPacket)),
	.LOG_DEPTH				(VIRT_PCIE_UNIFIED_RESP_Q_SIZE)
)
unified_pcieRespQ_1
(
	.clock					(clk),
	.reset_n				(~rst),
	.wrreq					(unified_respQ_enq[1]),
	.data                   (unified_respQ_in[1]),
	.full                   (unified_respQ_full[1]),
	.q                      (unified_respQ_out[1]),
	.empty                  (unified_respQ_empty[1]),
	.rdreq                  (unified_respQ_deq[1])
);

// App 0, just a queue of packets

always_comb begin

	app_enable[0] = 1'b1;

	unified_respQ_in[0]  = app_pcie_packet_in[0];
	unified_respQ_enq[0] = app_pcie_packet_in[0].valid && !unified_respQ_full[0];
	
	app_pcie_full_out[0] = unified_respQ_full[0];
	
	app_pcie_packet_out[0].valid = unified_respQ_out[0].valid && !unified_respQ_empty[0];
	app_pcie_packet_out[0].data  = unified_respQ_out[0].data;
	app_pcie_packet_out[0].slot  = unified_respQ_out[0].slot;
	app_pcie_packet_out[0].pad   = unified_respQ_out[0].pad;
	app_pcie_packet_out[0].last  = unified_respQ_out[0].last;
	
	unified_respQ_deq[0] = app_pcie_grant_in[0];
	
end

always_comb begin

	app_enable[1] = 1'b1;

	unified_respQ_in[1]  = app_pcie_packet_in[1];
	unified_respQ_enq[1] = app_pcie_packet_in[1].valid && !unified_respQ_full[1];
	
	app_pcie_full_out[1] = unified_respQ_full[1];
	
	app_pcie_packet_out[1].valid = unified_respQ_out[1].valid && !unified_respQ_empty[1];
	app_pcie_packet_out[1].data  = unified_respQ_out[1].data;
	app_pcie_packet_out[1].slot  = unified_respQ_out[1].slot;
	app_pcie_packet_out[1].pad   = 3;//unified_respQ_out[1].pad;
	app_pcie_packet_out[1].last  = unified_respQ_out[1].last;
	
	unified_respQ_deq[1] = app_pcie_grant_in[1];
	
end


endmodule 
