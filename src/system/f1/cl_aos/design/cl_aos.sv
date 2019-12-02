/*

    Top level module for running on an F1 instance

    Written by Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module cl_aos (
   `include "cl_ports.vh" // Fixed port definition
);

`include "cl_common_defines.vh"      // CL Defines for all examples
`include "cl_id_defines.vh"          // Defines for ID0 and ID1 (PCI ID's)
`include "cl_aos_defines.vh" // CL Defines for cl_hello_world

// CL Version

`ifndef CL_VERSION
   `define CL_VERSION 32'hee_ee_ee_00
`endif  

logic rst_main_n_sync;

//--------------------------------------------
// Start with Tie-Off of Unused Interfaces
//--------------------------------------------
// the developer should use the next set of `include
// to properly tie-off any unused interface
// The list is put in the top of the module
// to avoid cases where developer may forget to
// remove it from the end of the file

// User defined interrupts, NOT USED
`include "unused_apppf_irq_template.inc"
// Function level reset, NOT USED
`include "unused_flr_template.inc"
// Main PCI-e in/out interfaces, currently not used
`include "unused_pcim_template.inc"
`include "unused_dma_pcis_template.inc"
// Unused AXIL interfaces
`include "unused_cl_sda_template.inc"
`include "unused_sh_ocl_template.inc"
//`include "unused_sh_bar1_template.inc"

// Gen vars
genvar i;
genvar app_num;
//------------------------------------
// Reset Synchronization
//------------------------------------
logic pre_sync_rst_n;

always_ff @(negedge rst_main_n or posedge clk_main_a0)
   if (!rst_main_n)
   begin
      pre_sync_rst_n  <= 0;
      rst_main_n_sync <= 0;
   end
   else
   begin
      pre_sync_rst_n  <= 1;
      rst_main_n_sync <= pre_sync_rst_n;
   end

// Global Signals
logic global_clk;
logic global_rst_n;
logic global_rst;

assign global_clk   = clk_main_a0;
assign global_rst_n = rst_main_n_sync;
assign global_rst   = !rst_main_n_sync;
   

//------------------------------------
// PCI-E
//------------------------------------

PCIEPacket					app_pcie_packet_in[F1_NUM_APPS-1:0];
wire 						app_pcie_full_out[F1_NUM_APPS-1:0];
PCIEPacket		            app_pcie_packet_out[F1_NUM_APPS-1:0];
logic			            app_pcie_grant_in[F1_NUM_APPS-1:0];
   
// Dummy PCI-e
PCIEPacket dummy_pcie_packet;
assign dummy_pcie_packet.valid = 1'b0;
	
generate
	for (app_num = 0; app_num < F1_NUM_APPS; app_num = app_num + 1) begin : dummy_pcie_signals
		assign app_pcie_packet_in[app_num] = dummy_pcie_packet;
		assign app_pcie_grant_in[app_num]  = 1'b0;
	end
endgenerate
   
//------------------------------------
// App and port enables
//------------------------------------
logic								app_enable [F1_NUM_APPS-1:0];
logic								port_enable[F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];

// App enables
//assign app_enable[0] = 1'b1; // app 0 is always enabled
// Port enables
//assign port_enable[0][0] = 1'b1;
//assign port_enable[0][1] = 1'b1;

genvar port_num;
generate
	for (app_num = 0; app_num < F1_NUM_APPS; app_num = app_num + 1) begin : enables_set
		assign app_enable[app_num] = 1'b1;
		for (port_num = 0; port_num < AMI_NUM_PORTS; port_num = port_num + 1) begin : ports_enable
			assign port_enable[app_num][port_num] = 1'b1;
		end
	end
endgenerate
   
//------------------------------------
// SoftReg
//------------------------------------

// Mapped onto BAR1 
/* AppPF
  |   |------- BAR1
  |   |         * 32-bit BAR, non-prefetchable
  |   |         * 2MiB (0 to 0x1F-FFFF)
  |   |         * Maps to BAR1 AXI-L of the CL
  |   |         * Typically used for CL application registers 
*/

	// AXIL2SR to AmorphOS
    SoftRegReq  softreg_req_from_axil2sr;
    logic       softreg_req_grant_to_axil2sr;

    SoftRegResp softreg_resp_to_axil2sr;
    logic       softreg_resp_grant_from_axil2sr;  

    // AmorphOS to apps SoftReg
	SoftRegReq					 app_softreg_req[F1_NUM_APPS-1:0];
	SoftRegResp					 app_softreg_resp[F1_NUM_APPS-1:0];
    
    // SoftReg signals that could be generated internally by AmorphOS
    SoftRegReq  softreg_req_from_aos_internal[F1_NUM_APPS-1:0]; // will connect to the AMICombiner (maybe other things)
    SoftRegReq  softreg_req_from_aos_host[F1_NUM_APPS-1:0];

    SoftRegResp softreg_resp_to_aos[F1_NUM_APPS-1:0];

    generate
        for (app_num = 0; app_num < F1_NUM_APPS; app_num = app_num + 1) begin : gen_softreg_combiner
            SoftRegCombiner
            sr_combiner
            (
                // General Signals
                .clk(global_clk),
                .rst(global_rst),
                // Soft register interface
                .softreg_req_from_aos_internal(softreg_req_from_aos_internal[app_num]),
                .softreg_req_from_aos_host(softreg_req_from_aos_host[app_num]),
                .softreq_req_to_app(app_softreg_req[app_num]),
                .softreg_resp_from_app(app_softreg_resp[app_num]),
                .softreq_resp_to_aos(softreg_resp_to_aos[app_num])   
            );
        end
    end
     
	generate
		if (F1_AXIL_USE_EXTENDER == 1) begin : extender_axil2sr
			AXIL2SR_Extended
			axil2sr_inst_extended
			(
				// General Signals
				.clk(global_clk),
				.rst(global_rst), // expects active high

				// Write Address
				.sh_bar1_awvalid(sh_bar1_awvalid),
				.sh_bar1_awaddr(sh_bar1_awaddr),
				.bar1_sh_awready(bar1_sh_awready),

				//Write data
				.sh_bar1_wvalid(sh_bar1_wvalid),
				.sh_bar1_wdata(sh_bar1_wdata),
				.sh_bar1_wstrb(sh_bar1_wstrb),
				.bar1_sh_wready(bar1_sh_wready),

				//Write response
				.bar1_sh_bvalid(bar1_sh_bvalid),
				.bar1_sh_bresp(bar1_sh_bresp),
				.sh_bar1_bready(sh_bar1_bready),

				//Read address
				.sh_bar1_arvalid(sh_bar1_arvalid),
				.sh_bar1_araddr(sh_bar1_araddr),
				.bar1_sh_arready(bar1_sh_arready),

				//Read data/response
				.bar1_sh_rvalid(bar1_sh_rvalid),
				.bar1_sh_rdata(bar1_sh_rdata),
				.bar1_sh_rresp(bar1_sh_rresp),
				.sh_bar1_rready(sh_bar1_rready),

				// Interface to SoftReg
				// Requests
				.softreg_req(softreg_req_from_axil2sr),
				.softreg_req_grant(softreg_req_grant_to_axil2sr),
				// Responses
				.softreg_resp(softreg_resp_to_axil2sr),
				.softreg_resp_grant(softreg_resp_grant_from_axil2sr)
			);
		end else begin : normal_axil2sr
			AXIL2SR
			axil2sr_inst 
			(
				// General Signals
				.clk(global_clk),
				.rst(global_rst), // expects active high

				// Write Address
				.sh_bar1_awvalid(sh_bar1_awvalid),
				.sh_bar1_awaddr(sh_bar1_awaddr),
				.bar1_sh_awready(bar1_sh_awready),

				//Write data
				.sh_bar1_wvalid(sh_bar1_wvalid),
				.sh_bar1_wdata(sh_bar1_wdata),
				.sh_bar1_wstrb(sh_bar1_wstrb),
				.bar1_sh_wready(bar1_sh_wready),

				//Write response
				.bar1_sh_bvalid(bar1_sh_bvalid),
				.bar1_sh_bresp(bar1_sh_bresp),
				.sh_bar1_bready(sh_bar1_bready),

				//Read address
				.sh_bar1_arvalid(sh_bar1_arvalid),
				.sh_bar1_araddr(sh_bar1_araddr),
				.bar1_sh_arready(bar1_sh_arready),

				//Read data/response
				.bar1_sh_rvalid(bar1_sh_rvalid),
				.bar1_sh_rdata(bar1_sh_rdata),
				.bar1_sh_rresp(bar1_sh_rresp),
				.sh_bar1_rready(sh_bar1_rready),

				// Interface to SoftReg
				// Requests
				.softreg_req(softreg_req_from_axil2sr),
				.softreg_req_grant(softreg_req_grant_to_axil2sr),
				// Responses
				.softreg_resp(softreg_resp_to_axil2sr),
				.softreg_resp_grant(softreg_resp_grant_from_axil2sr)
			);
		end
	endgenerate

	// MemDrive connectors
	AMIRequest                   md_mem_reqs        [1:0];
	wire                         md_mem_req_grants  [1:0];
	AMIResponse                  md_mem_resps       [1:0];
	wire                         md_mem_resp_grants [1:0];
	// SimSimpleDRAM connectors
	MemReq                       ssd_mem_req_in[1:0];
	wire                         ssd_mem_req_grant_out[1:0];
	MemResp                      ssd_mem_resp_out[1:0];
	logic                        ssd_mem_resp_grant_in[1:0];

    // Connect to AmorphOS or test module
    generate
        if (F1_CONFIG_SOFTREG_CONFIG == 0) begin : axil2sr_test
            F1SoftRegLoopback
            f1softregloopback_inst
            (
                .clk(global_clk),
                .rst(global_rst), // expects active high

                .softreg_req(softreg_req_from_axil2sr),
                .softreg_req_grant(softreg_req_grant_to_axil2sr),

                .softreg_resp(softreg_resp_to_axil2sr),
                .softreg_resp_grant(softreg_resp_grant_from_axil2sr)

            );
        end else if (F1_CONFIG_SOFTREG_CONFIG == 1) begin : axil2sr_memdrive_test
			MemDrive_SoftReg
			memdrive_softreg_inst
			(
				// User clock and reset
				.clk(global_clk),
				.rst(global_rst), 

				.srcApp(1'b0),
				
				// Simplified Memory interface
				.mem_reqs(md_mem_reqs),
				.mem_req_grants(md_mem_req_grants),
				.mem_resps(md_mem_resps),
				.mem_resp_grants(md_mem_resp_grants),

				// PCIe Slot DMA interface
				.pcie_packet_in(dummy_pcie_packet),
				.pcie_full_out(),   // unused

				.pcie_packet_out(), // unused
				.pcie_grant_in(1'b0),

				// Soft register interface
				.softreg_req(softreg_req_from_axil2sr),
				.softreg_resp(softreg_resp_to_axil2sr)
			);
			
			// has to accept it, SW makes sure it isn't swamped
			assign softreg_req_grant_to_axil2sr    = softreg_req_from_axil2sr.valid;
		
			for (i = 0; i < 2; i = i + 1) begin : ssd_gen
				SimSimpleDram
				simsimpledram_inst
				(
					// User clock and reset
					.clk(global_clk),
					.rst(global_rst), 
					// Simplified Memory Interface
					.mem_req_in(ssd_mem_req_in[i]),
					.mem_req_grant_out(ssd_mem_req_grant_out[i]),
					.mem_resp_out(ssd_mem_resp_out[i]),
					.mem_resp_grant_in(ssd_mem_resp_grant_in[i])
				);			
			
				// Convert AMIRequest to MemReq
				assign ssd_mem_req_in[i].valid   = md_mem_reqs[i].valid;
				assign ssd_mem_req_in[i].isWrite = md_mem_reqs[i].isWrite;
				assign ssd_mem_req_in[i].data    = md_mem_reqs[i].data;
				assign ssd_mem_req_in[i].addr    = md_mem_reqs[i].addr;
			
				// Convert MemResp to AMIResponse
				assign md_mem_resps[i].valid     = ssd_mem_resp_out[i].valid;
				assign md_mem_resps[i].data      = ssd_mem_resp_out[i].data;
				assign md_mem_resps[i].size      = 64;
			
				// Connect the grant signals
				assign md_mem_req_grants[i]      = ssd_mem_req_grant_out[i];
				assign ssd_mem_resp_grant_in[i]  = md_mem_resp_grants[i];

			end // end for 

		end else if (F1_CONFIG_SOFTREG_CONFIG == 2) begin
			// Full AmorphOS system
			// SoftReg Interface
			if (F1_AXIL_USE_ROUTE_TREE == 0) begin : sr_no_tree
				AmorphOSSoftReg
				amorphos_softreg_inst
				(
					// User clock and reset
					.clk(global_clk),
					.rst(global_rst), 
					.app_enable(app_enable),
					// Interface to Host
					.softreg_req(softreg_req_from_axil2sr),
					.softreg_resp(softreg_resp_to_axil2sr),
					// Virtualized interface each app
					.app_softreg_req(softreg_req_from_aos_host),
					.app_softreg_resp(softreg_resp_to_aos)
				);
			end else begin : sr_with_tree
				AmorphOSSoftReg_RouteTree #(.SR_NUM_APPS(F1_NUM_APPS)) amorphos_softreg_inst_route_tree
				(
					// User clock and reset
					.clk(global_clk),
					.rst(global_rst), 
					.app_enable(app_enable),
					// Interface to Host
					.softreg_req(softreg_req_from_axil2sr),
					.softreg_resp(softreg_resp_to_axil2sr),
					// Virtualized interface each app
					.app_softreg_req(softreg_req_from_aos_host),
					.app_softreg_resp(softreg_resp_to_aos)
				);
			end
			// has to accept it, SW makes sure it isn't swamped
			assign softreg_req_grant_to_axil2sr    = softreg_req_from_axil2sr.valid;
		end // end else

    endgenerate

//------------------------------------
// Memory Interfaces
//------------------------------------

// AmorphOS connectors to the apps
AMIRequest                   app_mem_reqs        [F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
logic                        app_mem_req_grants  [F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
AMIResponse                  app_mem_resps       [F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
wire                         app_mem_resp_grants [F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
// AmorphOS connectors to AMI2AXI4
AMIRequest                   ami2_ami2axi4_req_out        [F1_NUM_MEM_CHANNELS-1:0];
wire                         ami2_ami2axi4_req_grant_in   [F1_NUM_MEM_CHANNELS-1:0];
AMIResponse                  ami2_ami2axi4_resp_in        [F1_NUM_MEM_CHANNELS-1:0];
logic                        ami2_ami2axi4_resp_grant_out [F1_NUM_MEM_CHANNELS-1:0];

// AmorphOS connectors for internally generated memory requests
AMIRequest                   mem_reqs_aos_internal[F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
wire                         mem_req_grants_internal[F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
AMIResponse                  mem_resps_internal[F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
wire                         mem_resp_grants_internal[F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];


// AmorphOSMem
genvar ami_num;
generate
	if (F1_CONFIG_AMI_ENABLED == 0) begin
		// statically map ports 0/1 to channels 0/1 for a single app
		assign ami2_ami2axi4_req_out        = app_mem_reqs[0];
		assign app_mem_req_grants[0]        = ami2_ami2axi4_req_grant_in;
		assign app_mem_resps[0]             = ami2_ami2axi4_resp_in;
		assign ami2_ami2axi4_resp_grant_out = app_mem_resp_grants[0];
	end else if (F1_CONFIG_AMI_ENABLED == 1) begin
		AmorphOSMem
		amorphosmem_inst
		(
			// User clock and reset
			.clk(global_clk),
			.rst(global_rst), 
			// Enable signals
			.app_enable(app_enable),
			.port_enable(port_enable),
			// AMI interface to the apps
			// Submitting requests
			.mem_req_in(app_mem_reqs),
			.mem_req_grant_out(app_mem_req_grants),
			// Reading responses
			.mem_resp_out(app_mem_resps),
			.mem_resp_grant_in(app_mem_resp_grants),
			// Interface to mem interface modules per channel
			.ch2mem_inter_req_out(ami2_ami2axi4_req_out),
			.ch2mem_inter_req_grant_in(ami2_ami2axi4_req_grant_in),
			.ch2mem_inter_resp_in(ami2_ami2axi4_resp_in),
			.ch2mem_inter_resp_grant_out(ami2_ami2axi4_resp_grant_out)
		);
	end else if (F1_CONFIG_AMI_ENABLED == 2) begin
		for (ami_num = 0; ami_num < NUM_AMI_INSTS; ami_num = ami_num + 1) begin : multi_ami
			AmorphOSMem
			ami_inst
			(
				// User clock and reset
				.clk(global_clk),
				.rst(global_rst), 
				// Enable signals
				.app_enable(app_enable[(8*ami_num)+7:(ami_num*8)]),
				.port_enable(port_enable[(8*ami_num)+7:(ami_num*8)]),
				// AMI interface to the apps
				// Submitting requests
				.mem_req_in(app_mem_reqs[(8*ami_num)+7:(ami_num*8)]),
				.mem_req_grant_out(app_mem_req_grants[(8*ami_num)+7:(ami_num*8)]),
				// Reading responses
				.mem_resp_out(app_mem_resps[(8*ami_num)+7:(ami_num*8)]),
				.mem_resp_grant_in(app_mem_resp_grants[(8*ami_num)+7:(ami_num*8)]),
				// Interface to mem interface modules per channel
				.ch2mem_inter_req_out(ami2_ami2axi4_req_out[(ami_num*CHANNELS_PER_AMI)+(CHANNELS_PER_AMI-1):(ami_num*CHANNELS_PER_AMI)]),
				.ch2mem_inter_req_grant_in(ami2_ami2axi4_req_grant_in[(ami_num*CHANNELS_PER_AMI)+(CHANNELS_PER_AMI-1):(ami_num*CHANNELS_PER_AMI)]),
				.ch2mem_inter_resp_in(ami2_ami2axi4_resp_in[(ami_num*CHANNELS_PER_AMI)+(CHANNELS_PER_AMI-1):(ami_num*CHANNELS_PER_AMI)]),
				.ch2mem_inter_resp_grant_out(ami2_ami2axi4_resp_grant_out[(ami_num*CHANNELS_PER_AMI)+(CHANNELS_PER_AMI-1):(ami_num*CHANNELS_PER_AMI)])
			);
		end	
	end
endgenerate

// AXI-4 interfaces for DDR A, B, DDR
// 0 = A
// 1 = B
// 2 = D
// Address Write
logic[15:0]  cl_sh_ddr_awid_abd[2:0];
logic[63:0]  cl_sh_ddr_awaddr_abd[2:0];
logic[7:0]   cl_sh_ddr_awlen_abd[2:0];
logic[2:0]   cl_sh_ddr_awsize_abd[2:0];
logic        cl_sh_ddr_awvalid_abd [2:0];
logic[2:0]   sh_cl_ddr_awready_abd;
// Write Data
logic[15:0]  cl_sh_ddr_wid_abd[2:0];
logic[511:0] cl_sh_ddr_wdata_abd[2:0];
logic[63:0]  cl_sh_ddr_wstrb_abd[2:0];
logic[2:0]   cl_sh_ddr_wlast_abd;
logic[2:0]   cl_sh_ddr_wvalid_abd;
logic[2:0]   sh_cl_ddr_wready_abd;
// Write Response
logic[15:0]  sh_cl_ddr_bid_abd[2:0];
logic[1:0]   sh_cl_ddr_bresp_abd[2:0];
logic[2:0]   sh_cl_ddr_bvalid_abd;
logic[2:0]   cl_sh_ddr_bready_abd;
// Address Read
logic[15:0]  cl_sh_ddr_arid_abd[2:0];
logic[63:0]  cl_sh_ddr_araddr_abd[2:0];
logic[7:0]   cl_sh_ddr_arlen_abd[2:0];
logic[2:0]   cl_sh_ddr_arsize_abd[2:0];
logic[2:0]   cl_sh_ddr_arvalid_abd;
logic[2:0]   sh_cl_ddr_arready_abd;
// Read Response
logic[15:0]  sh_cl_ddr_rid_abd[2:0];
logic[511:0] sh_cl_ddr_rdata_abd[2:0];
logic[1:0]   sh_cl_ddr_rresp_abd[2:0];
logic[2:0]   sh_cl_ddr_rlast_abd;
logic[2:0]   sh_cl_ddr_rvalid_abd;
logic[2:0]   cl_sh_ddr_rready_abd;

// DDR is ready signal
logic[2:0]   sh_cl_ddr_is_ready_abd;

// setup defines to control the conditional compilation
parameter DDR_A_PRESENT_CL = (F1_CONFIG_DDR_CONFIG > 1 ?  1'b1 : 1'b0); // 2 or 4 channel mode
parameter DDR_B_PRESENT_CL = (F1_CONFIG_DDR_CONFIG > 2 ?  1'b1 : 1'b0); // 4 channel mode
parameter DDR_D_PRESENT_CL = (F1_CONFIG_DDR_CONFIG > 2 ?  1'b1 : 1'b0); // 4 channel mode

parameter NUM_AMI2AXI4_ABD = (F1_CONFIG_DDR_CONFIG > 2 ? 3 : (F1_CONFIG_DDR_CONFIG > 1 ? 1 : 0));

// Signals for stats interface (mustbe tied off to not hang the interface)
// Inputs
logic [7:0]  sh_ddr_stat_addr_abd[2:0];
logic        sh_ddr_stat_wr_abd[2:0];
logic        sh_ddr_stat_rd_abd[2:0];
logic [31:0] sh_ddr_stat_wdata_abd[2:0];
// Outputs
logic        ddr_sh_stat_ack_abd[2:0];
logic[31:0]  ddr_sh_stat_rdata_abd[2:0];
logic[7:0]   ddr_sh_stat_int_abd[2:0];

generate
	if (F1_CONFIG_DDR_CONFIG > 1) begin
		// DDR A
		if (DDR_A_PRESENT_CL == 1'b1) begin
			// Inputs
			assign sh_ddr_stat_addr_abd[0]  = sh_ddr_stat_addr0;
			assign sh_ddr_stat_wr_abd[0]    = sh_ddr_stat_wr0;
			assign sh_ddr_stat_rd_abd[0]    = sh_ddr_stat_rd0;
			assign sh_ddr_stat_wdata_abd[0] = sh_ddr_stat_wdata0;
			// Outputs
			assign ddr_sh_stat_ack0         = ddr_sh_stat_ack_abd[0];
			assign ddr_sh_stat_rdata0       = ddr_sh_stat_rdata_abd[0];
			assign ddr_sh_stat_int0         = ddr_sh_stat_int_abd[0];
		end else begin // not present
			// Inputs
			assign sh_ddr_stat_addr_abd[0]  = 8'h00;
			assign sh_ddr_stat_wr_abd[0]    = 1'b0;
			assign sh_ddr_stat_rd_abd[0]    = 1'b0;
			assign sh_ddr_stat_wdata_abd[0] = 32'b0;		
			// Outputs
			assign ddr_sh_stat_ack0         = 1'b1; // needed to not hang the interface
			assign ddr_sh_stat_rdata0       = 32'b0;
			assign ddr_sh_stat_int0         = 8'b0;
		end
		// DDR B
		if (DDR_B_PRESENT_CL == 1'b1) begin
			// Inputs
			assign sh_ddr_stat_addr_abd[1]  = sh_ddr_stat_addr1;
			assign sh_ddr_stat_wr_abd[1]    = sh_ddr_stat_wr1;
			assign sh_ddr_stat_rd_abd[1]    = sh_ddr_stat_rd1;
			assign sh_ddr_stat_wdata_abd[1] = sh_ddr_stat_wdata1;
			// Outputs
			assign ddr_sh_stat_ack1         = ddr_sh_stat_ack_abd[1];
			assign ddr_sh_stat_rdata1       = ddr_sh_stat_rdata_abd[1];
			assign ddr_sh_stat_int1         = ddr_sh_stat_int_abd[1];
		end else begin // not present
			// Inputs
			assign sh_ddr_stat_addr_abd[1]  = 8'h00;
			assign sh_ddr_stat_wr_abd[1]    = 1'b0;
			assign sh_ddr_stat_rd_abd[1]    = 1'b0;
			assign sh_ddr_stat_wdata_abd[1] = 32'b0;		
			// Outputs
			assign ddr_sh_stat_ack1         = 1'b1; // needed to not hang the interface
			assign ddr_sh_stat_rdata1       = 32'b0;
			assign ddr_sh_stat_int1         = 8'b0;
		end
		// DDR D
		if (DDR_D_PRESENT_CL == 1'b1) begin
			// Inputs
			assign sh_ddr_stat_addr_abd[2]  = sh_ddr_stat_addr2;
			assign sh_ddr_stat_wr_abd[2]    = sh_ddr_stat_wr2;
			assign sh_ddr_stat_rd_abd[2]    = sh_ddr_stat_rd2;
			assign sh_ddr_stat_wdata_abd[2] = sh_ddr_stat_wdata2;
			// Outputs
			assign ddr_sh_stat_ack2         = ddr_sh_stat_ack_abd[2];
			assign ddr_sh_stat_rdata2       = ddr_sh_stat_rdata_abd[2];
			assign ddr_sh_stat_int2         = ddr_sh_stat_int_abd[2];
		end else begin // not present
			// Inputs
			assign sh_ddr_stat_addr_abd[2]  = 8'h00;
			assign sh_ddr_stat_wr_abd[2]    = 1'b0;
			assign sh_ddr_stat_rd_abd[2]    = 1'b0;
			assign sh_ddr_stat_wdata_abd[2] = 32'b0;		
			// Outputs
			assign ddr_sh_stat_ack2         = 1'b1; // needed to not hang the interface
			assign ddr_sh_stat_rdata2       = 32'b0;
			assign ddr_sh_stat_int2         = 8'b0;
		end
	end // if 
endgenerate

generate
	// All DDR disabled
	if (F1_CONFIG_DDR_CONFIG == 0) begin
		// Memory, currently not used
		`include "unused_ddr_a_b_d_template.inc"
		`include "unused_ddr_c_template.inc"
	// Only DDR C is enabled
	end else if (F1_CONFIG_DDR_CONFIG == 1) begin 
		`include "unused_ddr_a_b_d_template.inc"
	// DDR C and A enabled (two channel mode) OR
	// DDR C A,B,D (four channel mode)
	end else if ((F1_CONFIG_DDR_CONFIG == 2) || (F1_CONFIG_DDR_CONFIG == 3)) begin 
			(* dont_touch = "true" *) logic sh_ddr_sync_rst_n;
			//lib_pipe #(.WIDTH(1), .STAGES(4)) SH_DDR_SLC_RST_N (.clk(clk), .rst_n(1'b1), .in_bus(rst_main_n_sync), .out_bus(sh_ddr_sync_rst_n));
			sh_ddr #(
				 .DDR_A_PRESENT(DDR_A_PRESENT_CL),
				 .DDR_B_PRESENT(DDR_B_PRESENT_CL),
				 .DDR_D_PRESENT(DDR_D_PRESENT_CL)
			) SH_DDR
		    (
			// General signals
		   .clk(clk_main_a0),
		   .rst_n(rst_main_n_sync),
		   .stat_clk(clk_main_a0),
		   .stat_rst_n(rst_main_n_sync),
			// DDR connections for DDR A
		   .CLK_300M_DIMM0_DP(CLK_300M_DIMM0_DP),
		   .CLK_300M_DIMM0_DN(CLK_300M_DIMM0_DN),
		   .M_A_ACT_N(M_A_ACT_N),
		   .M_A_MA(M_A_MA),
		   .M_A_BA(M_A_BA),
		   .M_A_BG(M_A_BG),
		   .M_A_CKE(M_A_CKE),
		   .M_A_ODT(M_A_ODT),
		   .M_A_CS_N(M_A_CS_N),
		   .M_A_CLK_DN(M_A_CLK_DN),
		   .M_A_CLK_DP(M_A_CLK_DP),
		   .M_A_PAR(M_A_PAR),
		   .M_A_DQ(M_A_DQ),
		   .M_A_ECC(M_A_ECC),
		   .M_A_DQS_DP(M_A_DQS_DP),
		   .M_A_DQS_DN(M_A_DQS_DN),
		   .cl_RST_DIMM_A_N(cl_RST_DIMM_A_N),
			// DDR connections for DDR B
		   .CLK_300M_DIMM1_DP(CLK_300M_DIMM1_DP),
		   .CLK_300M_DIMM1_DN(CLK_300M_DIMM1_DN),
		   .M_B_ACT_N(M_B_ACT_N),
		   .M_B_MA(M_B_MA),
		   .M_B_BA(M_B_BA),
		   .M_B_BG(M_B_BG),
		   .M_B_CKE(M_B_CKE),
		   .M_B_ODT(M_B_ODT),
		   .M_B_CS_N(M_B_CS_N),
		   .M_B_CLK_DN(M_B_CLK_DN),
		   .M_B_CLK_DP(M_B_CLK_DP),
		   .M_B_PAR(M_B_PAR),
		   .M_B_DQ(M_B_DQ),
		   .M_B_ECC(M_B_ECC),
		   .M_B_DQS_DP(M_B_DQS_DP),
		   .M_B_DQS_DN(M_B_DQS_DN),
		   .cl_RST_DIMM_B_N(cl_RST_DIMM_B_N),
			// DDR connections for DDR D
		   .CLK_300M_DIMM3_DP(CLK_300M_DIMM3_DP),
		   .CLK_300M_DIMM3_DN(CLK_300M_DIMM3_DN),
		   .M_D_ACT_N(M_D_ACT_N),
		   .M_D_MA(M_D_MA),
		   .M_D_BA(M_D_BA),
		   .M_D_BG(M_D_BG),
		   .M_D_CKE(M_D_CKE),
		   .M_D_ODT(M_D_ODT),
		   .M_D_CS_N(M_D_CS_N),
		   .M_D_CLK_DN(M_D_CLK_DN),
		   .M_D_CLK_DP(M_D_CLK_DP),
		   .M_D_PAR(M_D_PAR),
		   .M_D_DQ(M_D_DQ),
		   .M_D_ECC(M_D_ECC),
		   .M_D_DQS_DP(M_D_DQS_DP),
		   .M_D_DQS_DN(M_D_DQS_DN),
		   .cl_RST_DIMM_D_N(cl_RST_DIMM_D_N),

		   //------------------------------------------------------
		   // DDR-4 Interface from CL (AXI-4)
		   //------------------------------------------------------
		   // Address Write
		   .cl_sh_ddr_awid(cl_sh_ddr_awid_abd),
		   .cl_sh_ddr_awaddr(cl_sh_ddr_awaddr_abd),
		   .cl_sh_ddr_awlen(cl_sh_ddr_awlen_abd),
		   .cl_sh_ddr_awsize(cl_sh_ddr_awsize_abd),
		   .cl_sh_ddr_awvalid(cl_sh_ddr_awvalid_abd),
		   .sh_cl_ddr_awready(sh_cl_ddr_awready_abd),
			// Write Data
		   .cl_sh_ddr_wid(cl_sh_ddr_wid_abd),
		   .cl_sh_ddr_wdata(cl_sh_ddr_wdata_abd),
		   .cl_sh_ddr_wstrb(cl_sh_ddr_wstrb_abd),
		   .cl_sh_ddr_wlast(cl_sh_ddr_wlast_abd),
		   .cl_sh_ddr_wvalid(cl_sh_ddr_wvalid_abd),
		   .sh_cl_ddr_wready(sh_cl_ddr_wready_abd),
			// Write Response
		   .sh_cl_ddr_bid(sh_cl_ddr_bid_abd),
		   .sh_cl_ddr_bresp(sh_cl_ddr_bresp_abd),
		   .sh_cl_ddr_bvalid(sh_cl_ddr_bvalid_abd),
		   .cl_sh_ddr_bready(cl_sh_ddr_bready_abd),
			// Read Address
		   .cl_sh_ddr_arid(cl_sh_ddr_arid_abd),
		   .cl_sh_ddr_araddr(cl_sh_ddr_araddr_abd),
		   .cl_sh_ddr_arlen(cl_sh_ddr_arlen_abd),
		   .cl_sh_ddr_arsize(cl_sh_ddr_arsize_abd),
		   .cl_sh_ddr_arvalid(cl_sh_ddr_arvalid_abd),
		   .sh_cl_ddr_arready(sh_cl_ddr_arready_abd),
			// Read Data
		   .sh_cl_ddr_rid(sh_cl_ddr_rid_abd),
		   .sh_cl_ddr_rdata(sh_cl_ddr_rdata_abd),
		   .sh_cl_ddr_rresp(sh_cl_ddr_rresp_abd),
		   .sh_cl_ddr_rlast(sh_cl_ddr_rlast_abd),
		   .sh_cl_ddr_rvalid(sh_cl_ddr_rvalid_abd),
		   .cl_sh_ddr_rready(cl_sh_ddr_rready_abd),

			// Pass through from the shell
		   .sh_cl_ddr_is_ready(sh_cl_ddr_is_ready_abd),
			//-----------------------------------------------------------------------------
			// DDR Stats interfaces for DDR controllers in the CL.  This must be hooked up
			// to the sh_ddr.sv for the DDR interfaces to function.  If the DDR controller is
			// not used (removed through parameter on the sh_ddr instantiated), then the 
			// associated stats interface should not be hooked up and the ddr_sh_stat_ackX signal
			// should be tied high.
			//-----------------------------------------------------------------------------
			// Stats interface
			// A
		   .sh_ddr_stat_addr0  (sh_ddr_stat_addr_abd[0]),
		   .sh_ddr_stat_wr0    (sh_ddr_stat_wr_abd[0]), 
		   .sh_ddr_stat_rd0    (sh_ddr_stat_rd_abd[0]), 
		   .sh_ddr_stat_wdata0 (sh_ddr_stat_wdata_abd[0]), 
		   .ddr_sh_stat_ack0   (ddr_sh_stat_ack_abd[0]),
		   .ddr_sh_stat_rdata0 (ddr_sh_stat_rdata_abd[0]),
		   .ddr_sh_stat_int0   (ddr_sh_stat_int_abd[0]),
           // B
		   .sh_ddr_stat_addr1  (sh_ddr_stat_addr_abd[1]),
		   .sh_ddr_stat_wr1    (sh_ddr_stat_wr_abd[1]), 
		   .sh_ddr_stat_rd1    (sh_ddr_stat_rd_abd[1]), 
		   .sh_ddr_stat_wdata1 (sh_ddr_stat_wdata_abd[1]),
		   .ddr_sh_stat_ack1   (ddr_sh_stat_ack_abd[1]),
		   .ddr_sh_stat_rdata1 (ddr_sh_stat_rdata_abd[1]),
		   .ddr_sh_stat_int1   (ddr_sh_stat_int_abd[1]),
            // D
		   .sh_ddr_stat_addr2  (sh_ddr_stat_addr_abd[2]),
		   .sh_ddr_stat_wr2    (sh_ddr_stat_wr_abd[2]), 
		   .sh_ddr_stat_rd2    (sh_ddr_stat_rd_abd[2]), 
		   .sh_ddr_stat_wdata2 (sh_ddr_stat_wdata_abd[2]) , 
		   .ddr_sh_stat_ack2   (ddr_sh_stat_ack_abd[2]) ,
		   .ddr_sh_stat_rdata2 (ddr_sh_stat_rdata_abd[2]),
		   .ddr_sh_stat_int2   (ddr_sh_stat_int_abd[2])
		   
		   );
	end
	
	// Add the AMI2AXI4 modules
	// Enable DDR C
	if (F1_CONFIG_DDR_CONFIG > 0) begin
	    AMI2AXI4
		ami2axi4_c_inst
		(
			// General Signals
			.clk(global_clk),
			.rst(global_rst),
			.channel_id(4'b0000),
			// AmorphOS Memory Interface
			// Incoming requests, can be Read or Write
			.in_ami_req(ami2_ami2axi4_req_out[0]),
			.out_ami_req_grant(ami2_ami2axi4_req_grant_in[0]),
			// Outgoing requests, always read responses
			.out_ami_resp(ami2_ami2axi4_resp_in[0]),
			.in_ami_resp_grant(ami2_ami2axi4_resp_grant_out[0]),
			// AXI-4 signals to DDR
			// Write Address Channel (aw = address write)
			.cl_sh_ddr_awid(cl_sh_ddr_awid),    // tag for the write address group
			.cl_sh_ddr_awaddr(cl_sh_ddr_awaddr),  // address of first transfer in write burst
			.cl_sh_ddr_awlen(cl_sh_ddr_awlen),   // number of transfers in a burst (+1 to this value)
			.cl_sh_ddr_awsize(cl_sh_ddr_awsize),  // size of each transfer in the burst
			.cl_sh_ddr_awvalid(cl_sh_ddr_awvalid), // write address valid, signals the write address and control info is correct
			.sh_cl_ddr_awready(sh_cl_ddr_awready), // slave is ready to ass
			// Write Data Channel (w = write data)
			.cl_sh_ddr_wid(cl_sh_ddr_wid),     // write id tag
			.cl_sh_ddr_wdata(cl_sh_ddr_wdata),   // write data
			.cl_sh_ddr_wstrb(cl_sh_ddr_wstrb),   // write strobes, indicates which byte lanes hold valid data, 1 strobe bit per 8 bits to write
			.cl_sh_ddr_wlast(cl_sh_ddr_wlast),   // indicates the last transfer
			.cl_sh_ddr_wvalid(cl_sh_ddr_wvalid),  // indicates the write data and strobes are valid
			.sh_cl_ddr_wready(sh_cl_ddr_wready),  // indicates the slave can accept write data
			// Write Response Channel (b = write response)
			.sh_cl_ddr_bid(sh_cl_ddr_bid),     // response id tag
			.sh_cl_ddr_bresp(sh_cl_ddr_bresp),   // write response indicating the status of the transaction
			.sh_cl_ddr_bvalid(sh_cl_ddr_bvalid),  // indicates the write response is valid
			.cl_sh_ddr_bready(cl_sh_ddr_bready),  // indicates the master can accept a write response
			// Read Address Channel (ar = address read)
			.cl_sh_ddr_arid(cl_sh_ddr_arid),    // read address id for the read address group
			.cl_sh_ddr_araddr(cl_sh_ddr_araddr),  // address of first transfer in a read burst transaction
			.cl_sh_ddr_arlen(cl_sh_ddr_arlen),   // burst length, number of transfers in a burst (+1 to this value)
			.cl_sh_ddr_arsize(cl_sh_ddr_arsize),  // burst size, size of each transfer in the burst
			.cl_sh_ddr_arvalid(cl_sh_ddr_arvalid), // read address valid, signals the read address/control info is valid
			.sh_cl_ddr_arready(sh_cl_ddr_arready), // read address ready, signals the slave is ready to accept an address/control info
			// Read Data Channel (r = read data)
			.sh_cl_ddr_rid(sh_cl_ddr_rid),     // read id tag
			.sh_cl_ddr_rdata(sh_cl_ddr_rdata),   // read data
			.sh_cl_ddr_rresp(sh_cl_ddr_rresp),   // status of the read transfer
			.sh_cl_ddr_rlast(sh_cl_ddr_rlast),   // indicates last transfer in a read burst
			.sh_cl_ddr_rvalid(sh_cl_ddr_rvalid), // indicates the read data is valid
			.cl_sh_ddr_rready(cl_sh_ddr_rready), // indicates the master (AMI) can accept read data/response info
			// DDR is ready
			.sh_cl_ddr_is_ready(sh_cl_ddr_is_ready)
		);
	end
	// Possibly enable DDR A, B, D
	if (F1_CONFIG_DDR_CONFIG > 1) begin
	    for (i = 0; i < NUM_AMI2AXI4_ABD; i = i + 1) begin : ami2axi4_abd_gen
			AMI2AXI4
			ami2axi4_abd_inst
			(
				// General Signals
				.clk(global_clk),
				.rst(global_rst),
				.channel_id(1 + i),
				// AmorphOS Memory Interface
				// Incoming requests, can be Read or Write
				.in_ami_req(ami2_ami2axi4_req_out[1+i]),
				.out_ami_req_grant(ami2_ami2axi4_req_grant_in[1+i]),
				// Outgoing requests, always read responses
				.out_ami_resp(ami2_ami2axi4_resp_in[1+i]),
				.in_ami_resp_grant(ami2_ami2axi4_resp_grant_out[1+i]),
				// AXI-4 signals to DDR
				// Write Address Channel (aw = address write)
				.cl_sh_ddr_awid(cl_sh_ddr_awid_abd[i]),    // tag for the write address group
				.cl_sh_ddr_awaddr(cl_sh_ddr_awaddr_abd[i]),  // address of first transfer in write burst
				.cl_sh_ddr_awlen(cl_sh_ddr_awlen_abd[i]),   // number of transfers in a burst (+1 to this value)
				.cl_sh_ddr_awsize(cl_sh_ddr_awsize_abd[i]),  // size of each transfer in the burst
				.cl_sh_ddr_awvalid(cl_sh_ddr_awvalid_abd[i]), // write address valid, signals the write address and control info is correct
				.sh_cl_ddr_awready(sh_cl_ddr_awready_abd[i]), // slave is ready to ass
				// Write Data Channel (w = write data)
				.cl_sh_ddr_wid(cl_sh_ddr_wid_abd[i]),     // write id tag
				.cl_sh_ddr_wdata(cl_sh_ddr_wdata_abd[i]),   // write data
				.cl_sh_ddr_wstrb(cl_sh_ddr_wstrb_abd[i]),   // write strobes, indicates which byte lanes hold valid data, 1 strobe bit per 8 bits to write
				.cl_sh_ddr_wlast(cl_sh_ddr_wlast_abd[i]),   // indicates the last transfer
				.cl_sh_ddr_wvalid(cl_sh_ddr_wvalid_abd[i]),  // indicates the write data and strobes are valid
				.sh_cl_ddr_wready(sh_cl_ddr_wready_abd[i]),  // indicates the slave can accept write data
				// Write Response Channel (b = write response)
				.sh_cl_ddr_bid(sh_cl_ddr_bid_abd[i]),     // response id tag
				.sh_cl_ddr_bresp(sh_cl_ddr_bresp_abd[i]),   // write response indicating the status of the transaction
				.sh_cl_ddr_bvalid(sh_cl_ddr_bvalid_abd[i]),  // indicates the write response is valid
				.cl_sh_ddr_bready(cl_sh_ddr_bready_abd[i]),  // indicates the master can accept a write response
				// Read Address Channel (ar = address read)
				.cl_sh_ddr_arid(cl_sh_ddr_arid_abd[i]),    // read address id for the read address group
				.cl_sh_ddr_araddr(cl_sh_ddr_araddr_abd[i]),  // address of first transfer in a read burst transaction
				.cl_sh_ddr_arlen(cl_sh_ddr_arlen_abd[i]),   // burst length, number of transfers in a burst (+1 to this value)
				.cl_sh_ddr_arsize(cl_sh_ddr_arsize_abd[i]),  // burst size, size of each transfer in the burst
				.cl_sh_ddr_arvalid(cl_sh_ddr_arvalid_abd[i]), // read address valid, signals the read address/control info is valid
				.sh_cl_ddr_arready(sh_cl_ddr_arready_abd[i]), // read address ready, signals the slave is ready to accept an address/control info
				// Read Data Channel (r = read data)
				.sh_cl_ddr_rid(sh_cl_ddr_rid_abd[i]),     // read id tag
				.sh_cl_ddr_rdata(sh_cl_ddr_rdata_abd[i]),   // read data
				.sh_cl_ddr_rresp(sh_cl_ddr_rresp_abd[i]),   // status of the read transfer
				.sh_cl_ddr_rlast(sh_cl_ddr_rlast_abd[i]),   // indicates last transfer in a read burst
				.sh_cl_ddr_rvalid(sh_cl_ddr_rvalid_abd[i]), // indicates the read data is valid
				.cl_sh_ddr_rready(cl_sh_ddr_rready_abd[i]), // indicates the master (AMI) can accept read data/response info
				// DDR is ready
				.sh_cl_ddr_is_ready(sh_cl_ddr_is_ready_abd[i])
			);
		end // for
		
		for (i = 0; i < (3 - NUM_AMI2AXI4_ABD); i = i + 1) begin : ami2axi4_abd_disable_gen
			// Write Address Channel
			assign cl_sh_ddr_awid_abd[2-i]    = 16'b0;
			assign cl_sh_ddr_awaddr_abd[2-i]  = 64'b0;
			assign cl_sh_ddr_awlen_abd[2-i]   = 8'b0;
			assign cl_sh_ddr_awsize_abd[2-i]  = 3'b000;
			assign cl_sh_ddr_awvalid_abd[2-i] = 1'b0;
			// Write Data Channel
			assign cl_sh_ddr_wid_abd[2-i]     = 16'b0;
			assign cl_sh_ddr_wdata_abd[2-i]   = 512'b0;
			assign cl_sh_ddr_wstrb_abd[2-i]   = 64'b0;
			assign cl_sh_ddr_wlast_abd[2-i]   = 1'b0;
			assign cl_sh_ddr_wvalid_abd[2-i]  = 1'b0;
			// Write Response Channel
			assign cl_sh_ddr_bready_abd[2-i]  = 1'b0;
			// Read Address Channel
			assign cl_sh_ddr_arid_abd[2-i]    = 16'b0;
			assign cl_sh_ddr_araddr_abd[2-i]  = 64'b0;
			assign cl_sh_ddr_arlen_abd[2-i]   = 8'b0;
			assign cl_sh_ddr_arsize_abd[2-i]  = 3'b000;
			assign cl_sh_ddr_arvalid_abd[2-i] = 1'b0;
			// Read Data Channel
			assign cl_sh_ddr_rready_abd[2-i]  = 1'b0;
		end // for
		
	end // if
	
endgenerate

//------------------------------------
// Apps 
//------------------------------------

generate

	if (F1_ALL_APPS_SAME == 1) begin
		for (app_num = 0; app_num < F1_NUM_APPS; app_num = app_num + 1) begin : multi_inst
			if (F1_CONFIG_APPS == 1) begin : multi_memdrive
					MemDrive_SoftReg
					memdrive_softreg_inst
					(
						// User clock and reset
						.clk(global_clk),
						.rst(global_rst), 

						.srcApp(app_num),
						
						// Simplified Memory interface
						.mem_reqs(app_mem_reqs[app_num]),
						.mem_req_grants(app_mem_req_grants[app_num]),
						.mem_resps(app_mem_resps[app_num]),
						.mem_resp_grants(app_mem_resp_grants[app_num]),

						// PCIe Slot DMA interface
						.pcie_packet_in(dummy_pcie_packet),
						.pcie_full_out(),   // unused

						.pcie_packet_out(), // unused
						.pcie_grant_in(1'b0),

						// Soft register interface
						.softreg_req(app_softreg_req[app_num]),
						.softreg_resp(app_softreg_resp[app_num])
					);
			end else if (F1_CONFIG_APPS == 2) begin : multi_dnnweaver
					DNNDrive_SoftReg
					#(
						.USE_DUMMY(0)
					)
					dnndrive_softreg_inst
					(
						// User clock and reset
						.clk(global_clk),
						.rst(global_rst), 

						.srcApp(app_num),
						
						// Simplified Memory interface
						.mem_reqs(app_mem_reqs[app_num]),
						.mem_req_grants(app_mem_req_grants[app_num]),
						.mem_resps(app_mem_resps[app_num]),
						.mem_resp_grants(app_mem_resp_grants[app_num]),

						// PCIe Slot DMA interface
						.pcie_packet_in(dummy_pcie_packet),
						.pcie_full_out(),   // unused

						.pcie_packet_out(), // unused
						.pcie_grant_in(1'b0),

						// Soft register interface
						.softreg_req(app_softreg_req[app_num]),
						.softreg_resp(app_softreg_resp[app_num])
					);
			end else if (F1_CONFIG_APPS == 3) begin : multi_bitcoin
					BitcoinTop_SoftReg
					bitcoin_softreg_inst
					(
						// User clock and reset
						.clk(global_clk),
						.rst(global_rst), 

						.srcApp(app_num),
						
						// Simplified Memory interface
						.mem_reqs(app_mem_reqs[app_num]),
						.mem_req_grants(app_mem_req_grants[app_num]),
						.mem_resps(app_mem_resps[app_num]),
						.mem_resp_grants(app_mem_resp_grants[app_num]),

						// PCIe Slot DMA interface
						.pcie_packet_in(dummy_pcie_packet),
						.pcie_full_out(),   // unused

						.pcie_packet_out(), // unused
						.pcie_grant_in(1'b0),

						// Soft register interface
						.softreg_req(app_softreg_req[app_num]),
						.softreg_resp(app_softreg_resp[app_num])
					);
			end
		end // for
	end else begin

	end

endgenerate

//------------------------------------
// Misc/Debug Bridge
//------------------------------------
/*
// Outputs need to be assigned
output logic[31:0] cl_sh_status0,           //Functionality TBD
output logic[31:0] cl_sh_status1,           //Functionality TBD
output logic[31:0] cl_sh_id0,               //15:0 - PCI Vendor ID
											//31:16 - PCI Device ID
output logic[31:0] cl_sh_id1,               //15:0 - PCI Subsystem Vendor ID
											//31:16 - PCI Subsystem ID
output logic[15:0] cl_sh_status_vled,       //Virtual LEDs, monitored through FPGA management PF and tools

output logic tdo (for debug)
*/

assign cl_sh_id0[31:0]       = `CL_SH_ID0;
assign cl_sh_id1[31:0]       = `CL_SH_ID1;
assign cl_sh_status0[31:0]   = 32'h0000_0000;
assign cl_sh_status1[31:0]   = 32'h0000_0000;

assign cl_sh_status_vled = 16'h0000;

assign tdo = 1'b0; // TODO: Not really sure what this does since we're not creating a debug bridge

// Counters

//-------------------------------------------------------------
// These are global counters that increment every 4ns.  They
// are synchronized to clk_main_a0.  Note if clk_main_a0 is
// slower than 250MHz, the CL will see skips in the counts
//-------------------------------------------------------------
//input[63:0] sh_cl_glcount0                   //Global counter 0
//input[63:0] sh_cl_glcount1                   //Global counter 1

//------------------------------------
// Tie-Off HMC Interfaces
//------------------------------------

   assign hmc_iic_scl_o            =  1'b0;
   assign hmc_iic_scl_t            =  1'b0;
   assign hmc_iic_sda_o            =  1'b0;
   assign hmc_iic_sda_t            =  1'b0;

   assign hmc_sh_stat_ack          =  1'b0;
   //assign hmc_sh_stat_rdata[31:0]  = 32'b0;
   //assign hmc_sh_stat_int[7:0]     =  8'b0;

//------------------------------------
// Tie-Off Aurora Interfaces
//------------------------------------
   assign aurora_sh_stat_ack   =  1'b0;
   assign aurora_sh_stat_rdata = 32'b0;
   assign aurora_sh_stat_int   =  8'b0;

endmodule
