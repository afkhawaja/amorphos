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


module test_sr();

import tb_type_defines_pkg::*;
`include "cl_common_defines.vh" // CL Defines with register addresses

// AXI ID
parameter [5:0] AXI_ID = 6'h0;

logic [63:0] write_data;
logic [63:0] read_data;


   initial begin
  
       $display("Testbench power up");

      tb.power_up();

      $display("Writing 0x10 to address 0x0%x", 32'h0000_0000);
      tb.poke_bar1(.addr(32'h0000_0000), .data(32'h0000_00010));
      $display("Writing 0x00 to address 0x0%x", 32'h0000_0004);
      tb.poke_bar1(.addr(32'h0000_0004), .data(32'h0000_0000));

 /*     $display("Writing to BAR1");
      tb.poke(.addr(64'h0000_0000_0000_0000), .data(64'h0000_0000_0000_010), .id(AXI_ID), .size(DataSize::UINT64), .intf(AxiPort::PORT_BAR1));
*/

      //$display("Reading from address 0x0%x", 32'h0000_0000);
      $display("Reading from address 0x0%x", 32'h0000_0000);
      tb.peek_bar1(.addr(32'h0000_0000), .data(read_data[31:0]));
      $display("Reading from address 0x0%x", 32'h0000_0004);
      tb.peek_bar1(.addr(32'h0000_0004), .data(read_data[63:32]));

      $display("Read value 0x0%x",read_data);

      $display("Test bench done");
      tb.kernel_reset();

      tb.power_down();
      
      $finish;
   end

endmodule // test_aos
