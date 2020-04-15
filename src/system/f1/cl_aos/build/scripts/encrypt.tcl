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
set DNN_SRC $::env(DNN_SRC)
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
file copy -force $AOS_SRC/QuiescenceApp_SoftReg.sv $TARGET_DIR
file copy -force $AOS_SRC/RRWCArbiter.sv $TARGET_DIR
file copy -force $AOS_SRC/RespMerge.sv $TARGET_DIR
file copy -force $AOS_SRC/TwoInputArbiter.sv $TARGET_DIR
file copy -force $AOS_SRC/AmorphOSSoftReg.sv $TARGET_DIR
#file copy -force $AOS_SRC/AmorphOSPCIE.sv $TARGET_DIR
file copy -force $AOS_SRC/AmorphOSMem.sv $TARGET_DIR
file copy -force $AOS_SRC/AmorphOSMem2SDRAM.sv $TARGET_DIR
# DNN Weaver
file copy -force $DNN_SRC/include/dw_params.vh $TARGET_DIR
file copy -force $DNN_SRC/include/common.vh $TARGET_DIR
file copy -force $DNN_SRC/include/norm_lut.mif $TARGET_DIR
file copy -force $DNN_SRC/include/rd_mem_controller.mif $TARGET_DIR
file copy -force $DNN_SRC/include/wr_mem_controller.mif $TARGET_DIR
file copy -force $DNN_SRC/include/pu_controller_bin.mif $TARGET_DIR
file copy -force $DNN_SRC/source/axi_master/axi_master.v $TARGET_DIR
file copy -force $DNN_SRC/source/axi_master_wrapper/axi_master_wrapper.v $TARGET_DIR
file copy -force $DNN_SRC/source/axi_master/wburst_counter.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/FIFO/fifo.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/FIFO/fifo_fwft.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/FIFO/xilinx_bram_fifo.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/ROM/ROM.v $TARGET_DIR
file copy -force $DNN_SRC/source/axi_slave/axi_slave.v $TARGET_DIR
file copy -force $DNN_SRC/source/dnn_accelerator/dnn_accelerator.v $TARGET_DIR
file copy -force $DNN_SRC/source/mem_controller/mem_controller.v $TARGET_DIR
file copy -force $DNN_SRC/source/mem_controller/mem_controller_top.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/MACC/multiplier.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/MACC/macc.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/COUNTER/counter.v $TARGET_DIR
file copy -force $DNN_SRC/source/PU/PU.v $TARGET_DIR
file copy -force $DNN_SRC/source/PE/PE.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/REGISTER/register.v $TARGET_DIR
file copy -force $DNN_SRC/source/normalization/normalization.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/PISO/piso.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/PISO/piso_norm.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/SIPO/sipo.v $TARGET_DIR
file copy -force $DNN_SRC/source/pooling/pooling.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/COMPARATOR/comparator.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/MUX/mux_2x1.v $TARGET_DIR
file copy -force $DNN_SRC/source/PE_buffer/PE_buffer.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/lfsr/lfsr.v $TARGET_DIR
file copy -force $DNN_SRC/source/vectorgen/vectorgen.v $TARGET_DIR
file copy -force $DNN_SRC/source/PU/PU_controller.v $TARGET_DIR
file copy -force $DNN_SRC/source/weight_buffer/weight_buffer.v $TARGET_DIR
file copy -force $DNN_SRC/source/primitives/RAM/ram.v $TARGET_DIR
file copy -force $DNN_SRC/source/data_packer/data_packer.v $TARGET_DIR
file copy -force $DNN_SRC/source/data_unpacker/data_unpacker.v $TARGET_DIR
file copy -force $DNN_SRC/source/activation/activation.v $TARGET_DIR
file copy -force $DNN_SRC/source/read_info/read_info.v $TARGET_DIR
file copy -force $DNN_SRC/source/buffer_read_counter/buffer_read_counter.v $TARGET_DIR
file copy -force $DNN_SRC/source/loopback/loopback_top.v $TARGET_DIR
file copy -force $DNN_SRC/source/loopback/loopback.v $TARGET_DIR
file copy -force $DNN_SRC/source/loopback_pu_controller/loopback_pu_controller_top.v $TARGET_DIR
file copy -force $DNN_SRC/source/loopback_pu_controller/loopback_pu_controller.v $TARGET_DIR
file copy -force $DNN_SRC/source/serdes/serdes.v $TARGET_DIR
file copy -force $DNN_SRC/source/ami/dnn2ami_wrapper.sv $TARGET_DIR
file copy -force $DNN_SRC/source/ami/mem_controller_top_ami.sv $TARGET_DIR
file copy -force $DNN_SRC/source/ami/dnn_accelerator_ami.sv $TARGET_DIR
file copy -force $DNN_SRC/source/ami/dnnweaver_ami_top.sv $TARGET_DIR
#file copy -force $DNN_SRC/source/ami/DNNDrive.sv $TARGET_DIR
file copy -force $DNN_SRC/source/ami/DNNDrive_SoftReg.sv $TARGET_DIR
file copy -force $DNN_SRC/source/ami/DNN2AMI.sv $TARGET_DIR
file copy -force $DNN_SRC/source/ami/DNN2AMI_WRPath.sv $TARGET_DIR
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
