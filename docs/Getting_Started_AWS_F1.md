# AmorphOS on Amazon AWS F1

## Overview

This getting started guide will help walk you through getting AmorphOS working on Amazon F1. This guide assumes you have AWS access, are able to create an F1 FPGA instance (1 FPGA version is sufficient for this guide), are able to clone the
[AWS FPGA](https://github.com/aws/aws-fpga) repo, follow their [getting started](https://github.com/aws/aws-fpga#gettingstarted) guide, create the FPGA bitstream, use AWS Command Line Interface/S3 to upload the bitstream, and finally run 
it on an F1 instance. We strongly believe the AWS F1 instructions are well written and will help you quickly setup an F1 system. The rest of this guide covers how to get AmorphOS working on F1. Please note, the bulk transfer capabilities of AmorphOS,
for F1 systems, require the [XDMA](https://github.com/aws/aws-fpga/blob/master/sdk/linux_kernel_drivers/xdma/xdma_install.md) driver provided by Amazon to be installed, running, and built with a proper PCIE Vendor ID (all AmorphOS source code uses 
the same vendor ID).

AmorphOS will be the high level Custom Logic (CL) in the F1 design, with any number of applications you wish to instantiate as modules
instantiated inside this CL.

By following this guide, you will be able to get multiple instances of the [MemDrive example](https://github.com/afkhawaja/amorphos/tree/master/example/memdrive) running on AmorphOS on F1. The guide will also explain how to launch and configure
the AmorphOS Host Scheduler.

## Source code setup

To simplify the rest of this guide, let's set an environment variable to the top level directory (most likely 
/home/centos/src/project_data/ on AWS CentOS machines) where you have the aws-fpga repository
checked out

```
export AWS_FPGA_DIR=/home/centos/src/project_data
```

We will now clone this repository at the same level.

```
cd $AWS_FPGA_DIR
git clone https://github.com/afkhawaja/amorphos.git
```

Now you should have aws-fpga and amorphos directories checked out at the same level.

Next we will copy the AmorphOS CL directory to where F1 expects it for the build process:

```
cp -r $AWS_FPGA_DIR/amorphos/src/system/f1/cl_aos $AWS_FPGA_DIR/aws-fpga/hdk/cl/developer_designs/cl_aos
```

The F1 build process requires the CL_DIR environment variable to be set:

```
export CL_DIR=$AWS_FPGA_DIR//aws-fpga/hdk/cl/developer_designs/cl_aos
```


## Build the bitstream/Upload it to S3

Source the F1 hdk_setup file:

```
source $AWS_FPGA_DIR/aws-fpga/hdk_setup.sh
```

Launch the  build process:

```
cd $CL_DIR/build/scripts
./aws_build_dcp_from_cl.sh -strategy CONGESTION
```
In the current directory, you will now see a time stamped file ending in .nohup.out, which you can use to check the status of your
build. You will see a message like this when the build is complete:

```
AWS FPGA: (21:24:52) - Build complete.
INFO: [Common 17-206] Exiting Vivado at Mon June 24 21:24:52 2019...
```
This portion of the build process builds a tarball, we now need to upload it to Amazon S3 and request it be converted  to a finalized
FPGA image we can run directly on an F1 system. The tarball will be located at $CL_DIR/build/checkpoints/to_aws and will have the
same time stamp as the .nohup.out file. It should look like <time-stamp>.Developer_CL.tar .

Please see the F1 instructions [here](https://github.com/aws/aws-fpga/tree/master/hdk#step3) for the S3 upload and fpga-image creation.
The most important part of this step is that the aws ec2 create-fpga-image command will output both an AFI ID and an AGFI ID, which the
AmorphOS scheduler will require to flash the FPGA with our image.

You can use the aws ec2 describe-fpga-images command to track the status of the FPGA image creation process, proceed when this returns a
State Code of available.

At this point, we are done with image creation (and the HDK) and we recommend you restart your terminal, since we will need to source
the SDK environment now instead.

## Build the source code for the MemDrive host side application


## Build the AmorphOS Host Scheduler

## Create config JSON for the scheduler

## Launch AmorphOS Scheduler

## Run MemDrive host side application
