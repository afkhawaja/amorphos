# AmorphOS

AmorphOS is an open source Operating System for reconfigurable FPGAs. The primary goals of this project are to provide operating system functionality on reconfigurable platforms, to provide a cross-platform interface,
abstract away many system resources, and allow concurrency in a secure manner. Out of the box, AmorphOS enables a user to quickly develop an FPGA application and launch multiple instances on a single or multiple FPGAs 
on [AWS F1](https://github.com/aws/aws-fpga). AmorphOS also can run on the [Microsoft Catapult](https://www.microsoft.com/en-us/research/project/project-catapult/) research platform. The intention is AmorphOS is ported 
to as many FPGA platforms as possible, to enable AmorphOS interface compliant applications to be run on different platforms without needing to be rewritten. AmorphOS also provides a library of components that can be used to
assist in application design. The FPGA portion of AmorphOS is written in SystemVerilog and the host (CPU) side is written in C++.

AmorphOS currently provides the following:

- AmorphOS Application Interface
     - Config Register, directing control of the FPGA application
     - Bulk Data, allows DMA of bulk data from host to FPGA and vice versa, and reading/writes contents of DRAM
     - Memory Interface, protected multi-ported access to FPGA DRAM
- Host Side Scheduler
     - Provides simple user facing C++ for interfacing with FPGA applications
     - Capable of scheduling multiple applications to run concurrently on the FPGA
     - Capable of controlling multiple FPGAs and migrating applications between them

## Citing us

If AmorphOS or any of its components are used in your work, please cite the original [paper](https://www.usenix.org/conference/osdi18/presentation/khawaja) which appeared in the 13th USENIX Symposium on Operating Systems Design and Implementation, OSDI'18.

MLA
```
Khawaja, Ahmed, et al. "Sharing, protection, and compatibility for reconfigurable fabric with amorphos." 13th {USENIX} Symposium on Operating Systems Design and Implementation ({OSDI} 18). 2018.
```

Bibtex
```
@inproceedings{khawaja2018sharing,
  title={Sharing, protection, and compatibility for reconfigurable fabric with amorphos},
  author={Khawaja, Ahmed and Landgraf, Joshua and Prakash, Rohith and Wei, Michael and Schkufza, Eric and Rossbach, Christopher J},
  booktitle={13th $\{$USENIX$\}$ Symposium on Operating Systems Design and Implementation ($\{$OSDI$\}$ 18)},
  pages={107--127},
  year={2018}
}
```

## License

```
Copyright 2018 Christopher Rossbach

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Maintained By

Ahmed Khawaja (akhawaja@utexas.edu)

## Other
XDMA Driver

On Amazon F1, make sure the XMDA is installed (https://github.com/aws/aws-fpga/blob/master/sdk/linux_kernel_drivers/xdma/xdma_install.md), running, and was built with a proper PCIE Vendor ID.