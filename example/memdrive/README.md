# MemDrive Example Application

MemDrive is a sample application provided to illustrate how an application should be written on both the host and FPGA sides. It is able 
to receive control inputs from the host and do read/write patterns to DRAM. MemDrive is the featured example for running AmorphOS on AWS
F1 (guide here)[https://github.com/afkhawaja/amorphos/blob/master/docs/Getting_Started_AWS_F1.md]. 

MemDrive_Cntrl.sv is the SystemVerilog source for the MemDrive application and provides a good example of how an Application on the FPGA
side is to interact with AmorphOS's interfaces. MemDrive is programmable by the host to programmatically generate two concurrent read/write
memory access patterns to the FPGA DRAM and check the result. A common usage for MemDrive is to confirm the AmorphOS memory system is
working as intended. This is done by writting specific values to DRAM and then reading them back and confirming all the values are
as expected. MemDrive can also be used to confirm concurrency works by having each instance write unique values to memory and 
checking them to ensure they never cross over, even though the virtual addresses used in each is the same. MemDrive can also be used
to measure system memory bandwidth. memdrive_client.c is self documented to demonstrate how MemDrive is to be programmed.
