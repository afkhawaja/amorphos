# AmorphOS on Amazon AWS F1

## Overview

This getting started guide will help walk you through getting AmorphOS working on Amazon F1. This guide assumes you have AWS access, are able to create an F1 FPGA instance (1 FPGA version is sufficient for this guide), are able to clone the
[AWS FPGA](https://github.com/aws/aws-fpga) repo, follow their [getting started](https://github.com/aws/aws-fpga#gettingstarted) guide, create the FPGA bitstream, use AWS Command Line Interface/S3 to upload the bitstream, and finally run 
it on an F1 instance. We strongly believe the AWS F1 instructions are well written and will help you quickly setup an F1 system. The rest of this guide covers how to get AmorphOS working on F1. Please note, the bulk transfer capabilities of AmorphOS,
for F1 systems, require the [XDMA](https://github.com/aws/aws-fpga/blob/master/sdk/linux_kernel_drivers/xdma/xdma_install.md) driver provided by Amazon to be installed, running, and built with a proper PCIE Vendor ID (all AmorphOS source code uses 
the same vendor ID).

By following this guide, you will be able to get multiple instances of the [MemDrive example](https://github.com/afkhawaja/amorphos/tree/master/example/memdrive) running on AmorphOS on F1. The guide will also explain how to launch and configure
the AmorphOS Host Scheduler.

## Clone this repo


## Setup all required environment variables


## Setup the CL


## Build the bitstream/Upload it to S3


## Build the source code for the MemDrive host side application


## Build the AmorphOS Host Scheduler

## Create config JSON for the scheduler

## Launch AmorphOS Scheduler

## Run MemDrive host side application