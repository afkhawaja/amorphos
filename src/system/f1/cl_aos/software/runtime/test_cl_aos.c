// By Ahmed Khawaja
// Some contents copied from the Amazon example

// Normal C includes
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <assert.h>
#include <string.h>
#include <unistd.h>

       //int usleep(useconds_t usec);

// FPGA specific includes
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <utils/lcd.h>
#include <utils/sh_dpi_tasks.h>

/* use the stdout logger for printing debug information  */
const struct logger *logger = &logger_stdout;

static uint16_t pci_vendor_id = 0x1D0F; /* Amazon PCI Vendor ID */
static uint16_t pci_device_id = 0xF000; /* PCI Device ID preassigned by Amazon for F1 applications */

/* (0 to 0x1F-FFFF) is legal for BAR1 
	Bits 16-20 are always 0
    Bits 15-13 are the app select bits
    Bits 12- 0 are for the app to use
	Bits 0-3
*/
uint64_t applyAppMaskForBar1(uint32_t app_id, uint64_t offset) {
	uint64_t tmp = app_id;
	return (tmp << 13) | offset;
}

uint32_t upper32(uint64_t value) {
	return (value >> 32) & 0xFFFFFFFF;
}

uint32_t lower32(uint64_t value) {
	return value & 0xFFFFFFFF;
}

int check_afi_ready(int slot_id);

void usage(char* program_name) {
    printf("usage: %s [--slot <slot-id>][<poke-value>]\n", program_name);
}

int main(int argc, char **argv) {

	uint32_t value = 0xefbeadde;
	int slot_id = 0;
	int rc;
	uint64_t tmp;
	int num_apps = 8;
	uint32_t loop_iter = 0;
	uint32_t read0 = 0;
	uint32_t read1 = 0;
	uint64_t read64_0 = 0;
	uint64_t read64_1 = 0;
	// Mem Drive
	uint64_t start_addr0 = 0x0;
	uint64_t total_subs  = 0x15;
	uint64_t mask = 0xFFFFFFFFFFFFFFFF;
	uint64_t mode = 0x1; // write == 1, read = 0
	uint64_t start_addr1 = 0xC000;
	uint64_t addr_delta  = 6;
	uint64_t canary0     = 0xFEEBFEEBBEEFBEEF;
	uint64_t canary1     = 0xDAEDDAEDDEADDEAD;

    // Process command line args
    {
        int i;
        int value_set = 0;
        for (i = 1; i < argc; i++) {
            if (!strcmp(argv[i], "--slot")) {
                i++;
                if (i >= argc) {
                    printf("error: missing slot-id\n");
                    usage(argv[0]);
                    return 1;
                }
                sscanf(argv[i], "%d", &slot_id);
            } else if (!value_set) {
                sscanf(argv[i], "%x", &value);
                value_set = 1;
            } else {
                printf("error: Invalid arg: %s", argv[i]);
                usage(argv[0]);
                return 1;
            }
        }
    }

    /* initialize the fpga_pci library so we could have access to FPGA PCIe from this applications */
    rc = fpga_pci_init();
    fail_on(rc, out, "Unable to initialize the fpga_pci library");
	printf("fpga_pci library intialized correctly\n");
	
	/* check the afi */
    rc = check_afi_ready(slot_id);
    fail_on(rc, out, "AFI not ready\n");
	printf("AFI is ready\n");
	
	/* Attach to BAR1 */
	pci_bar_handle_t pci_bar1_handle = PCI_BAR_HANDLE_INIT;
    rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR1, 0, &pci_bar1_handle);
    fail_on(rc, out, "Unable to attach to the AFI on slot id %d\n", slot_id);
	printf("Attached to BAR1\n");
	
	/* Program the Apps to start */

	/* program MemDrive */
	// 0 start addr
    for (loop_iter = 0; loop_iter < num_apps; loop_iter = loop_iter + 1) {
    	printf("Starting app %d\n", loop_iter);
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x00), lower32(start_addr0));
	    fail_on(rc, out, "Unable to write to the fpga 0!");
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x04), upper32(start_addr0));
	    fail_on(rc, out, "Unable to write to the fpga 1!");
		// 1 total subs
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x08), lower32(total_subs));
	    fail_on(rc, out, "Unable to write to the fpga 2!");
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x0C), upper32(total_subs));
	    fail_on(rc, out, "Unable to write to the fpga 3!");
		// 2 mask
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x10), lower32(mask));
	    fail_on(rc, out, "Unable to write to the fpga 4!");
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x14), upper32(mask));
	    fail_on(rc, out, "Unable to write to the fpga 5!");
		// 3 mode Write == 1, Read == 0
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x18), lower32(mode));
	    fail_on(rc, out, "Unable to write to the fpga 6!");
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x1C), upper32(mode));
	    fail_on(rc, out, "Unable to write to the fpga 7!");
		// 4 start addr 2
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x20), lower32(start_addr1));
	    fail_on(rc, out, "Unable to write to the fpga 8!");
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x24), upper32(start_addr1));
	    fail_on(rc, out, "Unable to write to the fpga 9!");
		// 5 addr delta
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x28), lower32(addr_delta));
	    fail_on(rc, out, "Unable to write to the fpga 10!");
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x2C), upper32(addr_delta));
	    fail_on(rc, out, "Unable to write to the fpga 11!");
		// 6 canary 0
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x30), lower32(canary0));
	    fail_on(rc, out, "Unable to write to the fpga 12!");
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x34), upper32(canary0));
	    fail_on(rc, out, "Unable to write to the fpga 13!");
		// 7 canary 1
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x38), lower32(canary1));
	    fail_on(rc, out, "Unable to write to the fpga 14!");
	    rc = fpga_pci_poke(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x3C), upper32(canary1));
	    fail_on(rc, out, "Unable to write to the fpga 15!");
	}

    printf("Going to sleep to let the apps finish\n");
    usleep(20 * 1000000);

	/* Get responses back from the apps */
	for (loop_iter = 0; loop_iter < num_apps; loop_iter = loop_iter + 1) {
		printf("Trying to read from App %d\n", loop_iter);
		rc = fpga_pci_peek(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x0) , &read0);
		fail_on(rc, out, "Unable to read read from the fpga!");
		rc = fpga_pci_peek(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x4) , &read1);
		fail_on(rc, out, "Unable to read read from the fpga!");
		tmp = read1;		
		read64_0 = (tmp << 32) | read0;
		printf("App %d start cycle: %x\n", loop_iter, read64_0);
		rc = fpga_pci_peek(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0x8) , &read0);
		fail_on(rc, out, "Unable to read read from the fpga!");
		rc = fpga_pci_peek(pci_bar1_handle, applyAppMaskForBar1(loop_iter, 0xC) , &read1);
		fail_on(rc, out, "Unable to read read from the fpga!");
		tmp = read1;
		read64_1 = (tmp << 32) | read0;
		printf("App %d end cycle: %x\n", loop_iter, read64_1);
		printf("App %d runtime: %x\n", loop_iter, (read64_1 - read64_0));
	}
	
	/* Clean Up */
    if (pci_bar1_handle >= 0) {
        rc = fpga_pci_detach(pci_bar1_handle);
        if (rc) {
            printf("Failure while detaching from the fpga.\n");
        } else {
			printf("Successfully detached from the fpga.\n");
		}
    }

	printf("============\nSuccessful Run\n============\n");
    return rc;
    
out:
    return 1;
}

 int check_afi_ready(int slot_id) {
   struct fpga_mgmt_image_info info = {0}; 
   int rc;

   /* get local image description, contains status, vendor id, and device id. */
   rc = fpga_mgmt_describe_local_image(slot_id, &info,0);
   fail_on(rc, out, "Unable to get AFI information from slot %d. Are you running as root?",slot_id);

   /* check to see if the slot is ready */
   if (info.status != FPGA_STATUS_LOADED) {
     rc = 1;
     fail_on(rc, out, "AFI in Slot %d is not in READY state !", slot_id);
   }

   printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n",
          info.spec.map[FPGA_APP_PF].vendor_id,
          info.spec.map[FPGA_APP_PF].device_id);

   /* confirm that the AFI that we expect is in fact loaded */
   if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id ||
       info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
     printf("AFI does not show expected PCI vendor id and device ID. If the AFI "
            "was just loaded, it might need a rescan. Rescanning now.\n");

     rc = fpga_pci_rescan_slot_app_pfs(slot_id);
     fail_on(rc, out, "Unable to update PF for slot %d",slot_id);
     /* get local image description, contains status, vendor id, and device id. */
     rc = fpga_mgmt_describe_local_image(slot_id, &info,0);
     fail_on(rc, out, "Unable to get AFI information from slot %d",slot_id);

     printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n",
            info.spec.map[FPGA_APP_PF].vendor_id,
            info.spec.map[FPGA_APP_PF].device_id);

     /* confirm that the AFI that we expect is in fact loaded after rescan */
     if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id ||
         info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
       rc = 1;
       fail_on(rc, out, "The PCI vendor id and device of the loaded AFI are not "
               "the expected values.");
     }
   }
    
   return rc;
 out:
   return 1;
 }
 
