#include "aos_daemon.h"

int main(int argc, char *argv[]) {

    if (argc != 3) {
        printf("Usage: ./aos_host_sched <num_fpga> <fpga_images_json>");
        exit(EXIT_SUCCESS);
    }

    uint64_t num_fpga = std::stoull(argv[1]);
    std::string jsonFile = argv[2];

    bool initFPGA = true;

    /* Our process ID and Session ID */
    pid_t pid, sid;
    
    /* Fork off the parent process */
    pid = fork();
    if (pid < 0) {
        printf("Error - Unable to fork\n");
        exit(EXIT_FAILURE);
    }
    /* If we got a good PID, then
       we can exit the parent process. */
    if (pid > 0) {
        printf("Exiting parent\n");
        printf("Daemon pid is %d\n", pid);
        exit(EXIT_SUCCESS);
    }

    /* Change the file mode mask */
    umask(0);
            
    /* Open any logs here */        
            
    /* Create a new SID for the child process */
    sid = setsid();
    if (sid < 0) {  
        /* Log the failure */
        printf("Error - Unable to setsid\n");
        exit(EXIT_FAILURE);
    }

    /* Change the current working directory */
    if ((chdir("/")) < 0) {
        /* Log the failure */
        printf("Error - Unable to chdir\n");
        exit(EXIT_FAILURE);
    }
    
    // Intialize control over the FPGA
    aos_host fpga_handle = aos_host(num_fpga, !initFPGA);

    fpga_handle.parseImagesJson(jsonFile);

    if (initFPGA) {
        for (uint64_t fpga_id = 0; fpga_id < num_fpga; fpga_id++) {
            fpga_handle.loadDefaultImage(fpga_id);
        }
    }

    fpga_handle.init_socket();

    // Main loop
    fpga_handle.listen_loop();

    exit(EXIT_SUCCESS);

}
