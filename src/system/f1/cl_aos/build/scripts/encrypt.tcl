# Amazon FPGA Hardware Development Kit
#
# Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#    http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions and
# limitations under the License.

# TODO:
# Add check if CL_DIR and HDK_SHELL_DIR directories exist
# Add check if /build and /build/src_port_encryption directories exist
# Add check if the vivado_keyfile exist

set HDK_SHELL_DIR $::env(HDK_SHELL_DIR)
set HDK_SHELL_DESIGN_DIR $::env(HDK_SHELL_DESIGN_DIR)
set CL_DIR $::env(CL_DIR)
set AOS_SRC $::env(AOS_SRC)
set F1_SRC $::env(F1_SRC)
set TARGET_DIR $CL_DIR/build/src_post_encryption
set UNUSED_TEMPLATES_DIR $HDK_SHELL_DESIGN_DIR/interfaces
# Remove any previously encrypted files, that may no longer be used
if {[llength [glob -nocomplain -dir $TARGET_DIR *]] != 0} {
  eval file delete -force [glob $TARGET_DIR/*]
}

#---- Developr would replace this section with design files ----

# Remove any previously encrypted files, that may no longer be used
exec rm -f $TARGET_DIR/*

## Change file names and paths below to reflect your CL area.  DO NOT include AWS RTL files.
#---- Developer would replace this section with design files ----

file copy -force $CL_DIR/design/cl_aos_defines.vh             $TARGET_DIR
file copy -force $CL_DIR/design/cl_id_defines.vh                      $TARGET_DIR
#file copy -force $CL_DIR/design/cl_hello_world.sv                     $TARGET_DIR 
file copy -force $CL_DIR/../../examples/common/design/cl_common_defines.vh        $TARGET_DIR 
file copy -force $UNUSED_TEMPLATES_DIR/cl_ports.vh  $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_apppf_irq_template.inc  $TARGET_DIR
#file copy -force $UNUSED_TEMPLATES_DIR/unused_aurora_template.inc     $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_cl_sda_template.inc     $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_ddr_a_b_d_template.inc  $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_ddr_c_template.inc      $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_dma_pcis_template.inc   $TARGET_DIR
#file copy -force $UNUSED_TEMPLATES_DIR/unused_hmc_template.inc        $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_pcim_template.inc       $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_sh_bar1_template.inc    $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_flr_template.inc        $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_sh_ocl_template.inc        $TARGET_DIR
# AmorphOS
file copy -force $AOS_SRC/ShellTypes.sv $TARGET_DIR
file copy -force $AOS_SRC/AMITypes.sv $TARGET_DIR
file copy -force $F1_SRC/AOSF1Types.sv $TARGET_DIR
file copy -force $AOS_SRC/FIFO.sv $TARGET_DIR
file copy -force $AOS_SRC/SoftFIFO.sv $TARGET_DIR
file copy -force $F1_SRC/HullFIFO.sv $TARGET_DIR
file copy -force $AOS_SRC/TwoInputMux.sv $TARGET_DIR
file copy -force $AOS_SRC/FourInputMux.sv $TARGET_DIR
file copy -force $AOS_SRC/EightInputMux.sv $TARGET_DIR
file copy -force $AOS_SRC/ChannelArbiter.sv $TARGET_DIR
file copy -force $AOS_SRC/OneHotEncoder.sv $TARGET_DIR
file copy -force $AOS_SRC/OneHotMux.sv $TARGET_DIR
file copy -force $AOS_SRC/BlockBuffer.sv $TARGET_DIR
file copy -force $AOS_SRC/Counter64.sv $TARGET_DIR
file copy -force $AOS_SRC/ChannelArbiter.sv $TARGET_DIR
file copy -force $AOS_SRC/AddressTranslate.sv $TARGET_DIR
file copy -force $AOS_SRC/AppLevelTranslate.sv $TARGET_DIR
file copy -force $AOS_SRC/ChannelMerge.sv $TARGET_DIR
file copy -force $AOS_SRC/FourInputArbiter.sv $TARGET_DIR
file copy -force $AOS_SRC/MemDrive.sv $TARGET_DIR
file copy -force $AOS_SRC/MemDrive_SoftReg.sv $TARGET_DIR
file copy -force $AOS_SRC/RRWCArbiter.sv $TARGET_DIR
file copy -force $AOS_SRC/RespMerge.sv $TARGET_DIR
file copy -force $AOS_SRC/TwoInputArbiter.sv $TARGET_DIR
file copy -force $AOS_SRC/AmorphOSSoftReg.sv $TARGET_DIR
#file copy -force $AOS_SRC/AmorphOSPCIE.sv $TARGET_DIR
file copy -force $AOS_SRC/AmorphOSMem.sv $TARGET_DIR
file copy -force $AOS_SRC/AmorphOSMem2SDRAM.sv $TARGET_DIR
# F1 interfaces
file copy -force $F1_SRC/AXIL2SR.sv $TARGET_DIR
file copy -force $F1_SRC/AXIL2SR_Extended.sv $TARGET_DIR
file copy -force $F1_SRC/F1SoftRegLoopback.sv $TARGET_DIR
file copy -force $F1_SRC/AMI2AXI4_RdPath.sv $TARGET_DIR
file copy -force $F1_SRC/AMI2AXI4_WrPath.sv $TARGET_DIR
file copy -force $F1_SRC/AMI2AXI4.sv $TARGET_DIR
# Tree Modules
file copy -force $AOS_SRC/AmorphOSSoftReg_RouteTree.sv $TARGET_DIR
# Top level module
file copy -force $CL_DIR/design/cl_aos.sv                      $TARGET_DIR

#---- End of section replaced by Developr ---

# Make sure files have write permissions for the encryption
exec chmod +w {*}[glob $TARGET_DIR/*]

set TOOL_VERSION $::env(VIVADO_TOOL_VERSION)
set vivado_version [string range [version -short] 0 5]
puts "AWS FPGA: VIVADO_TOOL_VERSION $TOOL_VERSION"
puts "vivado_version $vivado_version"

# encrypt .v/.sv/.vh/inc as verilog files
encrypt -k $HDK_SHELL_DIR/build/scripts/vivado_keyfile_2017_4.txt -lang verilog  [glob -nocomplain -- $TARGET_DIR/*.{v,sv}] [glob -nocomplain -- $TARGET_DIR/*.vh] [glob -nocomplain -- $TARGET_DIR/*.inc]
# encrypt *vhdl files
encrypt -k $HDK_SHELL_DIR/build/scripts/vivado_vhdl_keyfile_2017_4.txt -lang vhdl -quiet [ glob -nocomplain -- $TARGET_DIR/*.vhd? ]
