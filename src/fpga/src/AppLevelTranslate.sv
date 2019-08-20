/*
	
	Accepts virtual addresses per application and translates them into
	physical addresses to be sent down the rest of the memory system

	Author: Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module AddrXlater(
input[AMI_APP_BITS-1:0] app_num,
input[63:0]  va_addr,
output logic[63:0] pa_addr
);

always_comb begin : xlate_table
	// 64 GB of total address space, divided into 8 apps is 8 GB
	if (USING_F1 == 1) begin
		if (F1_CONFIG_AMI_ENABLED == 1) begin
			case (app_num)
				0 : pa_addr = va_addr;
				1 : pa_addr = va_addr + (64'h200000000 * 1);
				2 : pa_addr = va_addr + (64'h200000000 * 2);
				3 : pa_addr = va_addr + (64'h200000000 * 3);
				4 : pa_addr = va_addr + (64'h200000000 * 4);
				5 : pa_addr = va_addr + (64'h200000000 * 5);
				6 : pa_addr = va_addr + (64'h200000000 * 6);
				7 : pa_addr = va_addr + (64'h200000000 * 7);
				default : pa_addr = va_addr;
			endcase
		end else if (F1_CONFIG_AMI_ENABLED == 2) begin
			// Multiple AMI case
			case (app_num)
				0 : pa_addr = va_addr;
				1 : pa_addr = va_addr + ((64'h200000000 >> F1_ADDR_SHIFT_XLATE) * 1);
				2 : pa_addr = va_addr + ((64'h200000000 >> F1_ADDR_SHIFT_XLATE) * 2);
				3 : pa_addr = va_addr + ((64'h200000000 >> F1_ADDR_SHIFT_XLATE) * 3);
				4 : pa_addr = va_addr + ((64'h200000000 >> F1_ADDR_SHIFT_XLATE) * 4);
				5 : pa_addr = va_addr + ((64'h200000000 >> F1_ADDR_SHIFT_XLATE) * 5);
				6 : pa_addr = va_addr + ((64'h200000000 >> F1_ADDR_SHIFT_XLATE) * 6);
				7 : pa_addr = va_addr + ((64'h200000000 >> F1_ADDR_SHIFT_XLATE) * 7);
				default : pa_addr = va_addr;
			endcase
		end
	end else begin
		case (app_num)
			// Always relevant
			0 : pa_addr = va_addr;
			// Relevant for N = 2,4,8
			1 : pa_addr = va_addr + ((AMI_NUM_APPS == 2) ? ({{31{1'b0}},3'b100,{30{1'b0}}}) : (((AMI_NUM_APPS == 4) ? ({{31{1'b0}},3'b010,{30{1'b0}}}) : ({{31{1'b0}},3'b001,{30{1'b0}}}))));
			// Only relevant if N == 4 or N == 8
			2 : pa_addr = (va_addr + ((AMI_NUM_APPS == 4) ? {{31{1'b0}},3'b100,{30{1'b0}}} : {{31{1'b0}},3'b010,{30{1'b0}}}));
			3 : pa_addr = (va_addr + ((AMI_NUM_APPS == 4) ? {{31{1'b0}},3'b110,{30{1'b0}}} : {{31{1'b0}},3'b011,{30{1'b0}}}));
			// Only relevant if N == 8
			4 : pa_addr = va_addr + {{31{1'b0}},3'b100,{30{1'b0}}};
			5 : pa_addr = va_addr + {{31{1'b0}},3'b101,{30{1'b0}}};
			6 : pa_addr = va_addr + {{31{1'b0}},3'b110,{30{1'b0}}};
			7 : pa_addr = va_addr + {{31{1'b0}},3'b111,{30{1'b0}}};		
			default : pa_addr = va_addr;
		endcase
	end // using F1 check
end

//assign pa_addr = va_addr;

endmodule

module AppLevelTranslate
(
	// Enable signal
	input								enabled,
	// App number
	input[AMI_APP_BITS-1:0]				app_num,
    // User clock and reset
    input                               clk,
    input                               rst,
	// Input from the per app/per port translation unit
	input AMIRequest					inReq[AMI_NUM_PORTS-1:0],
	// Output to per app/per port translation unit
	output logic						reqAccepted[AMI_NUM_PORTS-1:0],
	output AMIRequest					outReq[AMI_NUM_PORTS-1:0],
	input								outReq_grant[AMI_NUM_PORTS-1:0]
);
/*
// Interface for interactring with the central TLB
APP_TLB_STATE    tlb_state;
APP_TLB_STATE	 new_tlb_state;
AMIAPP_TLB_Entry tlb_entry[AMI_NUM_APP_TLB_ENTRIES];

integer unsigned tlb_num;
always@(posedge clk) begin
	if (rst) begin
		tlb_state <= DISABLED;
		for (tlb_num = 0; tlb_num < AMI_NUM_APP_TLB_ENTRIES; tlb_num = tlb_num  + 1) begin : app_tlb_reset
			tlb_entry[tlb_num].valid     <= 1'b0;
			tlb_entry[tlb_num].readable  <= 1'b0;
			tlb_entry[tlb_num].writable  <= 1'b0;
			tlb_entry[tlb_num].in_memory <= 1'b0;			
			tlb_entry[tlb_num].va_start  <= 0; 
			tlb_entry[tlb_num].va_end    <= 0; 
			tlb_entry[tlb_num].size      <= 0;
			tlb_entry[tlb_num].pa 	     <= 0;
		end
	end else begin
		tlb_state <= new_tlb_state;
	end
end

// Determine next state for the state machine
always_comb begin
	if (!enabled) begin
		new_tlb_state = DISABLED;
	end else begin
		case(tlb_state)
			DISABLED : begin
			
			end
			ENABLED: begin
			
			
			end
			PROGRAMMING: begin
			
			
			end
			default: begin
				new_tlb_state = ENABLED; // TODO: this should be set to tlb_state
			end
		endcase
	end
end

*/
// TODO: Place holder

wire[UMI_ADDR_WIDTH-1:0] xlated_pa_addr[AMI_NUM_PORTS-1:0];

genvar port_num;
generate
	for (port_num = 0; port_num < AMI_NUM_PORTS; port_num =  port_num + 1) begin : per_port_xlater
		AddrXlater
		addrXlater(
		.app_num(app_num),
		.va_addr(inReq[port_num].addr),
		.pa_addr(xlated_pa_addr[port_num])
		);
			
		assign outReq[port_num].addr    = xlated_pa_addr[port_num];
		assign outReq[port_num].data    = inReq[port_num].data;
		assign outReq[port_num].valid   = inReq[port_num].valid;
		assign outReq[port_num].isWrite = inReq[port_num].isWrite;
		assign outReq[port_num].size    = inReq[port_num].size;
		
		assign reqAccepted[port_num] = outReq_grant[port_num];

	end
endgenerate



endmodule
