//
// Types used throughout the AMI memory system
//

`ifndef AMITYPES_SV_INCLUDED
`define AMITYPES_SV_INCLUDED

package AMITypes;

// For Heterogenous config
// 0 - DNNWeaver
// 1 - Bitcoin
// 2 - MemDrive
// 3 - Unused
parameter AMI_HETERO_TOTAL  = 4;
parameter bit[1:0] AMI_HETERO_CONFIG[AMI_HETERO_TOTAL-1:0] = '{2 , 0 , 0 , 0};

/*AMI_HETERO_CONFIG[0] = 2; // app 0 MemDrive
AMI_HETERO_CONFIG[1] = 0; // app 1 DNNWeaver
AMI_HETERO_CONFIG[2] = 0; // app 2
AMI_HETERO_CONFIG[3] = 0; // app 3*/

parameter AMI_NUM_REAL_DNN = 4;
parameter AMI_NUM_APPS     = 1;
parameter AMI_NUM_PORTS    = 2;
parameter AMI_NUM_CHANNELS = 4;

parameter AMI_CHANNEL_BITS = (AMI_NUM_CHANNELS > 1 ? $clog2(AMI_NUM_CHANNELS) : 1);
parameter AMI_APP_BITS     = (AMI_NUM_APPS  > 1 ? $clog2(AMI_NUM_APPS)  : 1);
parameter AMI_PORT_BITS    = (AMI_NUM_PORTS > 1 ? $clog2(AMI_NUM_PORTS) : 1);

parameter AMI_ADDR_WIDTH = 64;
parameter AMI_DATA_WDITH = 512 + 64;
parameter AMI_REQ_SIZE_WIDTH = 6; // enables 64 byte size

parameter USE_SOFT_FIFO = 1;

parameter DISABLE_INTERLEAVE = 1'b0;

// TODO: Ensure these are sized so one app can not backup another
parameter ADDR_XLAT_Q_DEPTH       = (USE_SOFT_FIFO ? 3 : 9);
parameter ADDR_XLATED_Q_DEPTH     = (USE_SOFT_FIFO ? 3 : 9);
parameter CHANNEL_MERGE_Q_DEPTH   = (USE_SOFT_FIFO ? 3 : 9);
parameter RESP_MERGE_CHAN_Q_DEPTH = (USE_SOFT_FIFO ? 4 : 10)-1;
parameter RESP_MERGE_OUT_Q_DEPTH  = (USE_SOFT_FIFO ? 4 : 10)-1;
parameter RESP_MERGE_TAG_Q_DEPTH  = (USE_SOFT_FIFO ? 4 : 10)-1;
parameter CHAN_ARB_REQ_Q_DEPTH    = (USE_SOFT_FIFO ? 3 : 9);
parameter CHAN_ARB_TAG_Q_DEPTH    = (USE_SOFT_FIFO ? 3 : 9);
parameter CHAN_ARB_RESP_Q_DEPTH   = (USE_SOFT_FIFO ? 3 : 9);

parameter AMI2SDRAM_REQ_IN_Q_DEPTH  = (USE_SOFT_FIFO ? 3 : 9);
parameter AMI2SDRAM_RESP_IN_Q_DEPTH = (USE_SOFT_FIFO ? 3 : 9);

parameter AMI2DNN_MACRO_RD_Q_DEPTH   = (USE_SOFT_FIFO ? 3 : 9);
parameter AMI2DNN_MACRO_WR_Q_DEPTH   = (USE_SOFT_FIFO ? 3 : 9);
parameter AMI2DNN_REQ_Q_DEPTH        = (USE_SOFT_FIFO ? 3 : 9);
parameter AMI2DNN_WR_REQ_Q_DEPTH     = (USE_SOFT_FIFO ? 3 : 9);
parameter AMI2DNN_RESP_IN_Q_DEPTH    = (USE_SOFT_FIFO ? 3 : 9);
parameter AMI2DNN_READ_TAG_Q_DEPTH   = (USE_SOFT_FIFO ? 3 : 9);


parameter BLOCK_BUFFER_REQ_IN_Q_DEPTH   = (USE_SOFT_FIFO ? 3 : 9);
parameter BLOCK_BUFFER_RESP_OUT_Q_DEPTH = (USE_SOFT_FIFO ? 3 : 9);

typedef struct packed
{
	logic                          valid;
	logic                          isWrite;
	logic [AMI_ADDR_WIDTH-1:0]     addr;
	logic [AMI_DATA_WDITH-1:0] 	   data;
	logic [AMI_REQ_SIZE_WIDTH-1:0] size;
} AMIRequest;

typedef struct packed {
	logic                          valid;
	logic [AMI_DATA_WDITH-1:0]     data;
	logic [AMI_REQ_SIZE_WIDTH-1:0] size;
} AMIResponse;

typedef struct packed
{
	logic                          valid;
	logic                          isWrite;
	logic [AMI_PORT_BITS-1:0]      srcPort;
	logic [AMI_APP_BITS-1:0]       srcApp;
	logic [AMI_CHANNEL_BITS-1:0]   channel;
	logic [AMI_ADDR_WIDTH-1:0]     addr;
	logic [AMI_DATA_WDITH-1:0]     data;
	logic [AMI_REQ_SIZE_WIDTH-1:0] size;
} AMIReq;

typedef struct packed {
	logic                        valid;
	logic [AMI_PORT_BITS-1:0]    srcPort;
	logic [AMI_APP_BITS-1:0]     srcApp;
	logic [AMI_CHANNEL_BITS-1:0] channel;
	logic [AMI_DATA_WDITH-1:0]   data;
	logic [AMI_REQ_SIZE_WIDTH-1:0] size;	
} AMIResp;

typedef struct packed {
	logic                        valid;
	logic [AMI_PORT_BITS-1:0]    srcPort;
	logic [AMI_APP_BITS-1:0]     srcApp;
	logic [AMI_CHANNEL_BITS-1:0] channel;
	logic [AMI_REQ_SIZE_WIDTH-1:0] size;
} AMITag;

// TLB
parameter AMI_NUM_APP_TLB_ENTRIES = 4;

typedef struct packed {
	logic valid;
	logic in_memory;
	logic readable;
	logic writable;
	logic [AMI_ADDR_WIDTH-1:0] va_start;
	logic [AMI_ADDR_WIDTH-1:0] va_end;
	logic [AMI_ADDR_WIDTH-1:0] size;
	logic [AMI_ADDR_WIDTH-1:0] pa;
} AMIAPP_TLB_Entry;

typedef enum {
	DISABLED,
	PROGRAMMING,
	ENABLED
} APP_TLB_STATE;

typedef struct packed {
	logic 		 valid;
	logic [31:0] addr;
	logic [19:0]  size;
} DNNMicroRdTag;

typedef struct packed {
	logic valid;
	logic isWrite;
	logic [31:0] addr;
	logic [19:0]  size;
	logic [9:0]  pu_id;
	logic [63:0] time_stamp;
} DNNWeaverMemReq;

// Bulk Data
// AmorphOS Big Bulk Data packet format
typedef struct packed {
	logic valid;
	logic[63:0]  addr;
	logic[511:0] data;
} ABDPacket;

typedef struct packed {
    logic valid;
    logic[15:0] app_id;
    ABDPacket data_packet;
} ABDInternalPacket;

// Soft Reg virtualiztion

parameter VIRT_SOFTREG_RESP_Q_SIZE = (USE_SOFT_FIFO ? 4 : 9);
parameter VIRT_SOFTREG_RESV_BITS   = (AMI_NUM_APPS  > 1 ? $clog2(AMI_NUM_APPS)  : 1);

// PCI-E virtualization

parameter VIRT_PCIE_IN_Q_SIZE = (USE_SOFT_FIFO ? 3 : 9);
parameter VIRT_PCIE_UNIFIED_IN_Q_SIZE = (USE_SOFT_FIFO ? 3 : 9);
parameter VIRT_PCIE_RESP_Q_SIZE = (USE_SOFT_FIFO ? 3 : 9);
parameter VIRT_PCIE_UNIFIED_RESP_Q_SIZE = (USE_SOFT_FIFO ? 3 : 9);
parameter VIRT_PCIE_RESV_BITS = (AMI_NUM_APPS  > 1 ? $clog2(AMI_NUM_APPS)  : 1);

endpackage
`endif
