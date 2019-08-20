/*

   Used to combine packets with holes in them into a combined packet, using the write strobes

*/

import AMITypes::*;

// Need to support byte strobes
module DMA_PCIS_BYTE_LANE(
    input       clk,
    input       write_enable,
    input[7:0]  data_in,
    output logic[7:0] data_out
);

    // No need to reset this value
    reg[7:0]   value;
    logic[7:0] new_value;
    
    assign data_out = value;
    
    always@(posedge clk) begin
        value <= new_value;
    end
    
    always_comb begin
        if (write_enable) begin
            new_value = data_in;
        end else begin
            new_value = value;
        end    
    end

endmodule

module DMA_PCIS_WRSTRB_FIXUP(
    
    // General signals
    input clk,
    input rst,

    // Accept possibly fragment packets
    input[511:0] packet_in,
    input[63:0]  wrstrb_in,
    input        packet_in_valid,
    output logic packet_in_grant,
    
    // Output unified packets
    output logic[511:0] packet_out,
    output logic        packet_out_valid,
    input               packet_out_grant
    
);

   // Currently do nothing
   assign packet_out = packet_in;
   assign packet_out_valid = packet_in_valid;
   assign packet_in_grant = packet_out_grant;

endmodule
