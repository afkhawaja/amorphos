// Amazon FPGA Hardware Development Kit
//
// Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Amazon Software License (the "License"). You may not use
// this file except in compliance with the License. A copy of the License is
// located at
//
//    http://aws.amazon.com/asl/
//
// or in the "license" file accompanying this file. This file is distributed on
// an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
// implied. See the License for the specific language governing permissions and
// limitations under the License.


module test_dnn();

import tb_type_defines_pkg::*;
`include "cl_common_defines.vh" // CL Defines with register addresses

// AXI ID
parameter [5:0] AXI_ID = 6'h0;

logic [63:0] write_data;
logic [127:0] read_data;


   initial begin
  
      $display("Testbench power up");

      tb.power_up();
      tb.nsec_delay(1000);
      tb.poke_stat(.addr(8'h0c), .ddr_idx(0), .data(32'h0000_0000));
      tb.poke_stat(.addr(8'h0c), .ddr_idx(1), .data(32'h0000_0000));
      tb.poke_stat(.addr(8'h0c), .ddr_idx(2), .data(32'h0000_0000));

      tb.nsec_delay(30000);

      // Memdrive expects 8 64-bit writes, so 16 32-bit ones
      $display("TB: Starting to give DNNDrive commands");

      for (int i = 0; i < 8; i = i + 1) begin

      	      $display("TB: Telling DNNDrive %d to start", i);
	      // 0 start addr
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0000), .data(32'h0000_0000));
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0004), .data(32'h0000_0000));
	      //  1 total_subs
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0008), .data(32'h0000_000F));
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_000C), .data(32'h0000_0000));
	      //  2 mask
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0010), .data(32'hFFFF_FFFF));
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0014), .data(32'hFFFF_FFFF));
	      //  3 mode Write == 1, Read == 0
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0018), .data(32'h0000_0000));
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_001C), .data(32'h0000_0000));
	      //  4 start addr 2
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0020), .data(32'h0000_C000));
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0024), .data(32'h0000_0000));
	      //  5 addr delta (64 bytes apart)
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0028), .data(32'h0000_0006));
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_002C), .data(32'h0000_0000));
	      //  6 canary 0
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0030), .data(32'hBEEF_BEEF));
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0034), .data(32'hFEEB_FEEB));
	      //  7 canary 1
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_0038), .data(32'hDEAD_DEAD));
	      tb.poke_bar1(.addr((i << 13) | 32'h0000_003C), .data(32'hDAED_DAED));
      end

      $display("TB: Done Starting all DNNs");	
      tb.nsec_delay(100);

      for (int j = 0; j < 8; j = j + 1) begin
	      $display("TB: Reading Result from DNNDrive %d", j);
	      tb.peek_bar1(.addr((j << 13) | 32'h0000_0000), .data(read_data[31:0]));
	      tb.peek_bar1(.addr((j << 13) | 32'h0000_0004), .data(read_data[63:32]));
	      tb.peek_bar1(.addr((j << 13) | 32'h0000_0008), .data(read_data[95:64]));
	      tb.peek_bar1(.addr((j << 13) | 32'h0000_000C), .data(read_data[127:96]));
	      $display("TB :DNN %d Read value 0 0x0%x", j, read_data[63:0]);
	      $display("TB: DNN %d Read value 1 0x0%x", j, read_data[127:64]);
      end
  
      // TB Clean Up
      $display("Test bench done");
      tb.kernel_reset();
      tb.power_down();
      
      $finish;
   end

endmodule // test_aos
