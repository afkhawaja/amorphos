/*
	
	Top level module virtualizing the PCI-E interface
	
	Author: Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;

module AmorphOSPCIE
(
    // User clock and reset
    input                               clk,
    input                               rst,
	input								app_enable[AMI_NUM_APPS-1:0],
	// Interface to Host
	// Incoming packets
	input  PCIEPacket					pcie_packet_in,
	output logic						pcie_full_out,
	// Outgoing packets
	output PCIEPacket					pcie_packet_out,
	input								pcie_grant_in,
	// Virtualized interface each application
	output PCIEPacket					app_pcie_packet_in[AMI_NUM_APPS-1:0],
	input 								app_pcie_full_out[AMI_NUM_APPS-1:0],
	input  PCIEPacket					app_pcie_packet_out[AMI_NUM_APPS-1:0],
	output logic						app_pcie_grant_in[AMI_NUM_APPS-1:0]
);

	genvar app_num;

	// Route packet from shell to appropriate app
	// Input queues
	wire             inQ_empty[AMI_NUM_APPS-1:0];
	wire[AMI_NUM_APPS-1:0] inQ_full;
	logic            inQ_enq[AMI_NUM_APPS-1:0];
	logic            inQ_deq[AMI_NUM_APPS-1:0];
	PCIEPacket       inQ_in[AMI_NUM_APPS-1:0];
	PCIEPacket       inQ_out[AMI_NUM_APPS-1:0];

	wire             unified_inQ_empty;
	wire             unified_inQ_full;
	logic            unified_inQ_enq;
	logic            unified_inQ_deq;
	PCIEPacket       unified_inQ_in;
	PCIEPacket       unified_inQ_out;
	
	logic[AMI_NUM_APPS-1:0] valid_route;
	logic[AMI_NUM_APPS-1:0] proxy_full;
	
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : pcie_in_queues
			if (USE_SOFT_FIFO) begin : SoftFIFOs_in
				SoftFIFO
				#(
					.WIDTH					($bits(PCIEPacket)),
					.LOG_DEPTH				(VIRT_PCIE_IN_Q_SIZE)
				)
				pcieInQ
				(
					.clock					(clk),
					.reset_n				(~rst),
					.wrreq					(inQ_enq[app_num]),
					.data                   (inQ_in[app_num]),
					.full                   (inQ_full[app_num]),
					.q                      (inQ_out[app_num]),
					.empty                  (inQ_empty[app_num]),
					.rdreq                  (inQ_deq[app_num])
				);

			end else begin : FIFOs_in
				FIFO
				#(
					.WIDTH					($bits(PCIEPacket)),
					.LOG_DEPTH				(VIRT_PCIE_IN_Q_SIZE)
				)
				pcieInQ
				(
					.clock					(clk),
					.reset_n				(~rst),
					.wrreq					(inQ_enq[app_num]),
					.data                   (inQ_in[app_num]),
					.full                   (inQ_full[app_num]),
					.q                      (inQ_out[app_num]),
					.empty                  (inQ_empty[app_num]),
					.rdreq                  (inQ_deq[app_num])
				);
			end
			// Writing into the queues
			assign valid_route[app_num]  = !unified_inQ_empty && unified_inQ_out.valid && !inQ_full[app_num] && (app_num[VIRT_PCIE_RESV_BITS-1:0] == unified_inQ_out.slot[5:(6-VIRT_PCIE_RESV_BITS)]);
			assign inQ_enq[app_num]      = valid_route[app_num];
			assign inQ_in[app_num].valid = valid_route[app_num] ? 1'b1 : 1'b0;
			assign inQ_in[app_num].data  = valid_route[app_num] ? unified_inQ_out.data : 0;
			assign inQ_in[app_num].slot  = valid_route[app_num] ? {{(PCIE_SLOT_WIDTH-6+VIRT_PCIE_RESV_BITS){1'b0}},unified_inQ_out.slot[5-VIRT_PCIE_RESV_BITS:0]} : 0; // remove the upper bits
			assign inQ_in[app_num].pad   = valid_route[app_num] ? unified_inQ_out.pad  : 0;
			assign inQ_in[app_num].last  = valid_route[app_num] ? unified_inQ_out.last : 0;

			assign inQ_deq[app_num]                  = !inQ_empty[app_num] && inQ_out[app_num].valid && !app_pcie_full_out[app_num];
			assign app_pcie_packet_in[app_num].valid = inQ_deq[app_num];
			assign app_pcie_packet_in[app_num].data  = inQ_out[app_num].data;
			assign app_pcie_packet_in[app_num].slot  = inQ_out[app_num].slot;
			assign app_pcie_packet_in[app_num].pad   = inQ_out[app_num].pad;
			assign app_pcie_packet_in[app_num].last  = inQ_out[app_num].last;
			
			assign proxy_full[app_num] = app_pcie_full_out[app_num];

		end
	endgenerate

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFOs_unified_in
			SoftFIFO
			#(
				.WIDTH					($bits(PCIEPacket)),
				.LOG_DEPTH				(VIRT_PCIE_UNIFIED_IN_Q_SIZE)
			)
			unified_pcieInQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(unified_inQ_enq),
				.data                   (unified_inQ_in),
				.full                   (unified_inQ_full),
				.q                      (unified_inQ_out),
				.empty                  (unified_inQ_empty),
				.rdreq                  (unified_inQ_deq)
			);

		end else begin : FIFOs_unified_in
			FIFO
			#(
				.WIDTH					($bits(PCIEPacket)),
				.LOG_DEPTH				(VIRT_PCIE_UNIFIED_IN_Q_SIZE)
			)
			unified_pcieInQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(unified_inQ_enq),
				.data                   (unified_inQ_in),
				.full                   (unified_inQ_full),
				.q                      (unified_inQ_out),
				.empty                  (unified_inQ_empty),
				.rdreq                  (unified_inQ_deq)
			);
		end
	endgenerate
	
	assign unified_inQ_in  = pcie_packet_in;
	assign unified_inQ_deq = (|valid_route);
	
	assign unified_inQ_enq = pcie_packet_in.valid && !unified_inQ_full; // less restrictive condition
	assign pcie_full_out   = unified_inQ_full || (|inQ_full);// || (|proxy_full); // might need to add proxy_full term
	
	/*generate
		logic[AMI_NUM_APPS-1:0] valid_route;
		logic[AMI_NUM_APPS-1:0] app_pcie_full_out_tmp;
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : app_mux_logic
			assign valid_route[app_num] = pcie_packet_in.valid && !app_pcie_full_out[app_num] && (app_num[VIRT_PCIE_RESV_BITS-1:0] == pcie_packet_in.slot[5:(6-VIRT_PCIE_RESV_BITS)]);
			assign app_pcie_packet_in[app_num].valid = valid_route[app_num] ? 1'b1 : 1'b0;
			assign app_pcie_packet_in[app_num].data  = valid_route[app_num] ? pcie_packet_in.data : 0;
			assign app_pcie_packet_in[app_num].slot  = valid_route[app_num] ? {{(PCIE_SLOT_WIDTH-6+VIRT_PCIE_RESV_BITS){1'b0}},pcie_packet_in.slot[5-VIRT_PCIE_RESV_BITS:0]} : 0; // remove the upper bits
			assign app_pcie_packet_in[app_num].pad   = valid_route[app_num] ? pcie_packet_in.pad : 0;
			assign app_pcie_packet_in[app_num].last  = valid_route[app_num] ? pcie_packet_in.last : 0;
			assign app_pcie_full_out_tmp[app_num]    = valid_route[app_num] && app_pcie_full_out[app_num];
		end
		assign pcie_full_out = (|app_pcie_full_out_tmp);
	endgenerate
	*/
	//assign app_pcie_packet_in[0] = pcie_packet_in;
	//assign pcie_full_out         = app_pcie_full_out[0];
	
	// Route packets from app to the shell
	// Response queue
	wire             respQ_empty[AMI_NUM_APPS-1:0];
	wire             respQ_full[AMI_NUM_APPS-1:0];
	logic            respQ_enq[AMI_NUM_APPS-1:0];
	logic            respQ_deq[AMI_NUM_APPS-1:0];
	PCIEPacket       respQ_in[AMI_NUM_APPS-1:0];
	PCIEPacket       respQ_out[AMI_NUM_APPS-1:0];

	wire             unified_respQ_empty;
	wire             unified_respQ_full;
	logic            unified_respQ_enq;
	logic            unified_respQ_deq;
	PCIEPacket       unified_respQ_in;
	PCIEPacket       unified_respQ_out;
	
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : pcie_resp_queues
			if (USE_SOFT_FIFO) begin : SoftFIFOs_out
				SoftFIFO
				#(
					.WIDTH					($bits(PCIEPacket)),
					.LOG_DEPTH				(VIRT_PCIE_RESP_Q_SIZE)
				)
				pcieRespQ
				(
					.clock					(clk),
					.reset_n				(~rst),
					.wrreq					(respQ_enq[app_num]),
					.data                   (respQ_in[app_num]),
					.full                   (respQ_full[app_num]),
					.q                      (respQ_out[app_num]),
					.empty                  (respQ_empty[app_num]),
					.rdreq                  (respQ_deq[app_num])
				);

			end else begin : FIFOs_out
				FIFO
				#(
					.WIDTH					($bits(PCIEPacket)),
					.LOG_DEPTH				(VIRT_PCIE_RESP_Q_SIZE)
				)
				pcieRespQ
				(
					.clock					(clk),
					.reset_n				(~rst),
					.wrreq					(respQ_enq[app_num]),
					.data                   (respQ_in[app_num]),
					.full                   (respQ_full[app_num]),
					.q                      (respQ_out[app_num]),
					.empty                  (respQ_empty[app_num]),
					.rdreq                  (respQ_deq[app_num])
				);
			end
			// Writing into the queues
			assign respQ_in[app_num].valid = app_pcie_packet_out[app_num].valid;
			assign respQ_in[app_num].data  = app_pcie_packet_out[app_num].data;
			assign respQ_in[app_num].pad   = app_pcie_packet_out[app_num].pad;
			assign respQ_in[app_num].last  = app_pcie_packet_out[app_num].last;
			assign respQ_in[app_num].slot  = {{10{1'b0}},app_num[AMI_APP_BITS-1:0],app_pcie_packet_out[app_num].slot[6-AMI_APP_BITS-1:0]};

			assign respQ_enq[app_num] = (app_enable[app_num] == 1'b1) && app_pcie_packet_out[app_num].valid && !respQ_full[app_num];
			assign app_pcie_grant_in[app_num] = respQ_enq[app_num];
		end
	endgenerate

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFOs_unified_out
			SoftFIFO
			#(
				.WIDTH					($bits(PCIEPacket)),
				.LOG_DEPTH				(VIRT_PCIE_UNIFIED_RESP_Q_SIZE)
			)
			unified_pcieRespQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(unified_respQ_enq),
				.data                   (unified_respQ_in),
				.full                   (unified_respQ_full),
				.q                      (unified_respQ_out),
				.empty                  (unified_respQ_empty),
				.rdreq                  (unified_respQ_deq)
			);

		end else begin : FIFOs_unified_out
			FIFO
			#(
				.WIDTH					($bits(PCIEPacket)),
				.LOG_DEPTH				(VIRT_PCIE_UNIFIED_RESP_Q_SIZE)
			)
			unified_pcieRespQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(unified_respQ_enq),
				.data                   (unified_respQ_in),
				.full                   (unified_respQ_full),
				.q                      (unified_respQ_out),
				.empty                  (unified_respQ_empty),
				.rdreq                  (unified_respQ_deq)
			);
		end
	endgenerate

	// Unified outputQ to shell
	assign pcie_packet_out.valid = unified_respQ_out.valid && !unified_respQ_empty;
	assign pcie_packet_out.data  = unified_respQ_out.data;
	assign pcie_packet_out.slot  = unified_respQ_out.slot;
	assign pcie_packet_out.pad   = unified_respQ_out.pad;
	assign pcie_packet_out.last  = unified_respQ_out.last;

	assign unified_respQ_deq = pcie_grant_in && unified_respQ_out.valid && !unified_respQ_empty;

	// Variables for state to determine which app is writing into the unifiedQ
	logic transaction_active;
	logic new_transaction_active;
	logic[AMI_NUM_APPS-1:0] active_app;
	logic[AMI_NUM_APPS-1:0] new_active_app;
	
	always@(posedge clk) begin
		if (rst) begin
			transaction_active <= 1'b0;
			active_app <= 0;
		end else begin
			transaction_active <= new_transaction_active;
			active_app <= new_active_app;
		end
	end	

	// Mux out the correct output to the unified queue
	logic[AMI_NUM_APPS-1:0] select_app_to_write;
	OneHotMux
	#(
		.WIDTH($bits(PCIEPacket)),
		.N(AMI_NUM_APPS)
	)
	resp_select_mux
	(
		.data(respQ_out),
		.select(select_app_to_write),
		.out(unified_respQ_in)
	);

	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : mux_out_logic_pcie
			assign select_app_to_write[app_num] = transaction_active && active_app[app_num] && !unified_respQ_full && !respQ_empty[app_num] && respQ_out[app_num].valid;
			assign respQ_deq[app_num] = unified_respQ_enq && select_app_to_write[app_num];
		end
	endgenerate
	
	assign unified_respQ_enq = transaction_active && (|select_app_to_write) && unified_respQ_in.valid && !unified_respQ_full;

	// Arbitrate which queue we submit from
	logic[AMI_NUM_APPS-1:0] arb_req;
	wire[AMI_NUM_APPS-1:0]  arb_grant;	
	logic select_new_app;
	logic last_packet;
	
	assign last_packet = transaction_active && unified_respQ_enq && unified_respQ_in.last;
	
	always_comb begin
		// determine if we need the arbiter to select a new current app
		if (last_packet || !transaction_active) begin
			select_new_app = 1'b1;
			new_transaction_active = (|arb_grant);
			new_active_app = (|arb_grant) ? arb_grant : 0;
		end else begin
			select_new_app = 1'b0;
			new_transaction_active = transaction_active;
			new_active_app         = active_app;
		end
	end
	
	generate
		for (app_num = 0; app_num < AMI_NUM_APPS; app_num = app_num + 1) begin : new_arb_logic
			assign arb_req[app_num] = select_new_app && !respQ_empty[app_num] && respQ_out[app_num].valid && (!active_app[app_num]); // can cause deadlock if app runs by itself first
		end
	endgenerate	
	
	RRWCArbiter 
	#(
		.N(AMI_NUM_APPS)
	)
	pcie_resp_arbiter
	(
		// General signals
		.clk(clk),
		.rst(rst),
		// Request vector
		.req(arb_req),
		// Grant vector
		.grant(arb_grant)
	);
	
endmodule