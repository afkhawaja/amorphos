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

-define VIVADO_SIM

-sourcelibext .v
-sourcelibext .sv
-sourcelibext .svh
-sourcelibext .vh
-sourcelibext .txt

-sourcelibdir ${CL_ROOT}/../../examples/common/design
-sourcelibdir ${CL_ROOT}/design
-sourcelibdir ${CL_ROOT}/verif/sv
-sourcelibdir ${SH_LIB_DIR}
-sourcelibdir ${SH_INF_DIR}
-sourcelibdir ${SH_SH_DIR}
-sourcelibdir ${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/hdl
-sourcelibdir ${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/sim
-sourcelibdir ${AOS_SRC}
-sourcelibdir ${F1_SRC}
-sourcelibdir ${DNN_SRC}
-sourcelibdir ${DNN_SRC}/include
-sourcelibdir ${BC_SRC}

-include ${CL_ROOT}/common/design
-include ${CL_ROOT}/../../examples/common/design
-include ${CL_ROOT}/verif/sv
-include ${SH_LIB_DIR}
-include ${SH_INF_DIR}
-include ${SH_SH_DIR}
-include ${HDK_COMMON_DIR}/verif/include
-include ${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/ip/ip_0/hdl/verilog
-include ${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice_light/hdl
-include ${AOS_SRC}
-include ${F1_SRC}
-include ${DNN_SRC}
-include ${DNN_SRC}/include
-include ${BC_SRC}

#${CL_ROOT}/common/design/cl_common_defines.vh
${CL_ROOT}/../../examples/common/design/cl_common_defines.vh
${CL_ROOT}/design/cl_aos_defines.vh
${HDK_SHELL_DESIGN_DIR}/ip/ila_vio_counter/sim/ila_vio_counter.v
${HDK_SHELL_DESIGN_DIR}/ip/ila_0/sim/ila_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/hdl/bd_a493.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/ip/ip_0/sim/bd_a493_xsdbm_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/ip/ip_0/hdl/xsdbm_v3_0_vl_rfs.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/ip/ip_0/hdl/ltlib_v1_0_vl_rfs.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/ip/ip_1/sim/bd_a493_lut_buffer_0.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/ip/ip_1/hdl/lut_buffer_v2_0_vl_rfs.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/bd_0/hdl/bd_a493_wrapper.v
${HDK_SHELL_DESIGN_DIR}/ip/cl_debug_bridge/sim/cl_debug_bridge.v
${HDK_SHELL_DESIGN_DIR}/ip/vio_0/sim/vio_0.v
${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice_light/sim/axi_register_slice_light.v
${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice/sim/axi_register_slice.v
${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice_light/hdl/axi_register_slice_v2_1_vl_rfs.v
${HDK_SHELL_DESIGN_DIR}/ip/axi_register_slice_light/hdl/axi_infrastructure_v1_1_vl_rfs.v
${SH_LIB_DIR}/../ip/axi_clock_converter_0/sim/axi_clock_converter_0.v
${DNN_SRC}/common.vh

# Added for AmorphOS and Apps
${AOS_SRC}/ShellTypes.sv
${AOS_SRC}/AMITypes.sv
${F1_SRC}/AOSF1Types.sv
${AOS_SRC}/FIFO.sv
${AOS_SRC}/SoftFIFO.sv
${F1_SRC}/HullFIFO.sv
${AOS_SRC}/TwoInputMux.sv
${AOS_SRC}/FourInputMux.sv
${AOS_SRC}/EightInputMux.sv
${AOS_SRC}/ChannelArbiter.sv
${AOS_SRC}/OneHotMux.sv
${AOS_SRC}/BlockBuffer.sv
${AOS_SRC}/Counter64.sv
${AOS_SRC}/ChannelArbiter.sv
${AOS_SRC}/AddressTranslate.sv
${AOS_SRC}/AppLevelTranslate.sv
${AOS_SRC}/ChannelMerge.sv
${AOS_SRC}/FourInputArbiter.sv
${AOS_SRC}/MemDrive.sv
${AOS_SRC}/MemDrive_SoftReg.sv
${AOS_SRC}/QuiescenceApp_SoftReg.sv
${AOS_SRC}/RRWCArbiter.sv
${AOS_SRC}/RespMerge.sv
${AOS_SRC}/TwoInputArbiter.sv
${AOS_SRC}/AmorphOSSoftReg.sv
${AOS_SRC}/AmorphOSPCIE.sv
${AOS_SRC}/AmorphOSMem.sv
${AOS_SRC}/AmorphOSMem2SDRAM.sv

# DNN Weaver
${DNN_SRC}/include/common.vh
${DNN_SRC}/source/axi_master/axi_master.v
${DNN_SRC}/source/axi_master_wrapper/axi_master_wrapper.v
${DNN_SRC}/source/axi_master/wburst_counter.v
${DNN_SRC}/source/primitives/FIFO/fifo.v
${DNN_SRC}/source/primitives/FIFO/fifo_fwft.v
${DNN_SRC}/source/primitives/FIFO/xilinx_bram_fifo.v
${DNN_SRC}/source/primitives/ROM/ROM.v
${DNN_SRC}/source/axi_slave/axi_slave.v
${DNN_SRC}/source/dnn_accelerator/dnn_accelerator.v
${DNN_SRC}/source/mem_controller/mem_controller.v
${DNN_SRC}/source/mem_controller/mem_controller_top.v
${DNN_SRC}/source/primitives/MACC/multiplier.v
${DNN_SRC}/source/primitives/MACC/macc.v
${DNN_SRC}/source/primitives/COUNTER/counter.v
${DNN_SRC}/source/PU/PU.v
${DNN_SRC}/source/PE/PE.v
${DNN_SRC}/source/primitives/REGISTER/register.v
${DNN_SRC}/source/normalization/normalization.v
${DNN_SRC}/source/primitives/PISO/piso.v
${DNN_SRC}/source/primitives/PISO/piso_norm.v
${DNN_SRC}/source/primitives/SIPO/sipo.v
${DNN_SRC}/source/pooling/pooling.v
${DNN_SRC}/source/primitives/COMPARATOR/comparator.v
${DNN_SRC}/source/primitives/MUX/mux_2x1.v
${DNN_SRC}/source/PE_buffer/PE_buffer.v
${DNN_SRC}/source/primitives/lfsr/lfsr.v
${DNN_SRC}/source/vectorgen/vectorgen.v
${DNN_SRC}/source/PU/PU_controller.v
${DNN_SRC}/source/weight_buffer/weight_buffer.v
${DNN_SRC}/source/primitives/RAM/ram.v
${DNN_SRC}/source/data_packer/data_packer.v
${DNN_SRC}/source/data_unpacker/data_unpacker.v
${DNN_SRC}/source/activation/activation.v
${DNN_SRC}/source/read_info/read_info.v
${DNN_SRC}/source/buffer_read_counter/buffer_read_counter.v
${DNN_SRC}/source/loopback/loopback_top.v
${DNN_SRC}/source/loopback/loopback.v
${DNN_SRC}/source/loopback_pu_controller/loopback_pu_controller_top.v
${DNN_SRC}/source/loopback_pu_controller/loopback_pu_controller.v
${DNN_SRC}/source/serdes/serdes.v
${DNN_SRC}/source/ami/dnn2ami_wrapper.sv
${DNN_SRC}/source/ami/mem_controller_top_ami.sv
${DNN_SRC}/source/ami/dnn_accelerator_ami.sv
${DNN_SRC}/source/ami/dnnweaver_ami_top.sv
${DNN_SRC}/source/ami/DNNDrive.sv
${DNN_SRC}/source/ami/DNNDrive_SoftReg.sv
${DNN_SRC}/source/ami/DNN2AMI.sv
${DNN_SRC}/source/ami/DNN2AMI_WRPath.sv

#Bitcoin
${BC_SRC}/sha-256-functions.v
${BC_SRC}/sha256_transform.v
${BC_SRC}/BitcoinTop.sv
${BC_SRC}/BitcoinTop_SoftReg.sv

# F1 interfaces
${F1_SRC}/AXIL2SR.sv
${F1_SRC}/F1SoftRegLoopback.sv
${F1_SRC}/AMI2AXI4_RdPath.sv
${F1_SRC}/AMI2AXI4_WrPath.sv
${F1_SRC}/AMI2AXI4.sv

${CL_ROOT}/design/cl_aos.sv

-f ${HDK_COMMON_DIR}/verif/tb/filelists/tb.${SIMULATOR}.f

${TEST_NAME}
