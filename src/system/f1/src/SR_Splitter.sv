import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module SR_Splitter(

    // General Signals
    input clk,
    input rst,

	input								app_enable[AMI_NUM_APPS-1:0],
	// Interface to AXIL2SR
	input  SoftRegReq					softreg_req,
	output SoftRegResp					softreg_resp,
	// Virtualized interface each app
	output SoftRegReq					app_softreg_req[(F1_SR_NUM_SPLITS*AMI_NUM_APPS)-1:0],
	input  SoftRegResp					app_softreg_resp[(F1_SR_NUM_SPLITS*AMI_NUM_APPS)-1:0]	
);

	// Distribute to a correct intermediate buffer
	





endmodule
