# Source Code Structure

The AmorphOS codebase is broken up into two parts, [host](https://github.com/afkhawaja/amorphos/tree/master/src/host) and [fpga](https://github.com/afkhawaja/amorphos/tree/master/src/fpga).
Host code are what run on the CPU host controlling the FPGA(s). It includes header files for the host side interface and the source code for the scheduler daemon responsible
for scheduling multiple applications on the FPGA(s). FPGA code are the logic portions of AmorphOS that will compiled into the bitstream running on the FPGA. AmorphOS is logically
the combination of these two parts and provides abstracted (yet powerful) interfaces on both the CPU and FPGA sides to allow for easier portability.
