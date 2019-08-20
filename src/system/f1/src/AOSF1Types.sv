`ifndef AOSF1TYPES_SV_INCLUDED
`define AOSF1TYPES_SV_INCLUDED

package  AOSF1Types;

// Used to conditionally compile certain modules
parameter USING_F1 = 1;

parameter F1_NUM_APPS = 1;
parameter F1_ALL_APPS_SAME = 1;

// MemDrive_SoftReg
parameter MEMDRIVE_SOFTREG_FIFO_Type  = 0;
parameter MEMDRIVE_SOFTREG_FIFO_Depth = 4;

parameter MEMDRIVE_SUB_Q_Type         = 0;
parameter MEMDRIVE_SUB_Q_Depth        = 5;

// DNNDrive_SoftReg
parameter DNNDRIVE_SOFTREG_Type       = 0;
parameter DNNDRIVE_SOFTREG_Depth      = 4;


// SoftReg Build Configs
// 0 - SoftReg Test
// 1 - Standalone MemDrive Test
// 2 - Full AmorphOS system
parameter F1_CONFIG_SOFTREG_CONFIG = 2;
// Build Configs
// 0 - No DDR
// 1 - DDR C only
// 2 - DDR C and A
// 3 - DDR C , A , B , D
parameter F1_CONFIG_DDR_CONFIG     = 3;
// App Configs
// 0 - None
// 1 - Single MemDrive
// 2 - Real/Dummy DNNWeaver
// 3 - Bitcoin
parameter F1_CONFIG_APPS           = 1;
// AmorphOS Memory Build Configs
// 0 - No AMI (limited to 1 app)
// 1 - AMI    (N Apps)
// 2 - Split config for multiple memory interfaces
parameter F1_CONFIG_AMI_ENABLED    = 1;
// Channels for each AMI controller
parameter CHANNELS_PER_AMI = 4;
// F1 visible channels
parameter F1_NUM_MEM_CHANNELS = 4;
// AMI insts
parameter NUM_AMI_INSTS = 1;
parameter F1_ADDR_SHIFT_XLATE = $clog2(NUM_AMI_INSTS);
// SoftReg interface over AXI-Lite
parameter F1_AXIL_USE_EXTENDER = 0;
//
parameter F1_AXIL_USE_ROUTE_TREE = 0;
// Write addresses coming from the F1 Shell
parameter F1_AXIL_wr_addr_FIFO_Type  = 0;
parameter F1_AXIL_wr_addr_FIFO_Depth = 2;
// Write data coming from the F1 Shell
parameter F1_AXIL_wr_data_FIFO_Type  = 0;
parameter F1_AXIL_wr_data_FIFO_Depth = 2;
// Read requests coming from the F1 Shell
parameter F1_AXIL_rd_req_FIFO_Type   = 0;
parameter F1_AXIL_rd_req_FIFO_Depth  = 2;
// Read response data from AOS
parameter F1_AXIL_rd_resp_FIFO_Type  = 0;
parameter F1_AXIL_rd_resp_FIFO_Depth = 2;
// Buffer output of the AXIL2SR module
parameter F1_AXIL_buffer_sr_req_FIFO_Type = 0;
parameter F1_AXIL_buffer_sr_req_FIFO_Depth = 2;

// Interface to memory via AXI-4

// Read Path
// Buffer AMI requests from the apps
parameter F1_AMI2AXI4_RdPath_RdReqFIFO_Type  = 0;
parameter F1_AMI2AXI4_RdPath_RdReqFIFO_Depth = 2;
// Buffer AMI responses back to the apps
parameter F1_AMI2AXI4_RdPath_RdRespFIFO_Type  = 0;
parameter F1_AMI2AXI4_RdPath_RdRespFIFO_Depth = 2;
  
//  Write Path
// Buffered AMI requests, data portion
parameter F1_AMI2AXI4_WrPath_WrReq_Data_FIFO_Type  = 0;
parameter F1_AMI2AXI4_WrPath_WrReq_Data_FIFO_Depth = 2;
// Buffered AMI requests, address portion
parameter F1_AMI2AXI4_WrPath_WrReq_Addr_FIFO_Type  = 0;
parameter F1_AMI2AXI4_WrPath_WrReq_Addr_FIFO_Depth = 2;

// Write data buffers for the PCIS interface
parameter F1_PCIS2ABD_WrPath_WrDataFIFO_Type  = 0;
parameter F1_PCIS2ABD_WrPath_WrDataFIFO_Depth = 8;
parameter F1_PCIS2ABD_WrPath_WrIdFIFO_Type  = 0;
parameter F1_PCIS2ABD_WrPath_WrIdFIFO_Depth = 8;

// Read data buffers for PCIS interface
parameter F1_PCIS2ABD_RdPath_RdReqFIFO_Type  = 0;
parameter F1_PCIS2ABD_RdPath_RdReqFIFO_Depth = 8;

parameter F1_PCIS2ABD_RdPath_RdRespIDFIFO_Type  = 0;
parameter F1_PCIS2ABD_RdPath_RdRespIDFIFO_Depth = 8;

endpackage
`endif
